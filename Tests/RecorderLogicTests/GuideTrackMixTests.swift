import Foundation
import Testing
@testable import RecorderLogic

@Suite struct GuideTrackMixTests {
    private let millisecond: Int64 = 1_000_000

    /// A mix at 1 kHz with no delay, so positions are milliseconds.
    private func mix(delay: Duration = .zero) -> GuideTrackMix {
        GuideTrackMix(.audioInputs, sampleRate: 1000, delay: delay)
    }

    /// The soft limiter's output for `x`, as the design states it.
    private func limited(_ x: Float) -> Float {
        let knee = GuideTrackMix.limiterKnee, ceiling = GuideTrackMix.limiterCeiling
        guard abs(x) > knee else { return x }
        return (x < 0 ? -1 : 1) * (knee + (ceiling - knee) * tanh((abs(x) - knee) / (ceiling - knee)))
    }

    /// At Stop the last mix waits until every source has delivered up to the video's end.
    @Test func theMixHasReceivedUpToAPositionWhenEverySourceReachesIt() {
        var guide = mix()
        #expect(guide.hasReceived(upTo: 10))
        guide.add(source: "Razer", channelCount: 1)
        guide.add(source: "BRIO", channelCount: 2)
        guide.receive([[Float](repeating: 0.1, count: 10)], from: "Razer", at: 0)
        guide.receive([[Float](repeating: 0.1, count: 6), [Float](repeating: 0.1, count: 6)], from: "BRIO", at: 0)
        #expect(guide.hasReceived(upTo: 6))
        #expect(!guide.hasReceived(upTo: 10))
        guide.receive([[Float](repeating: 0.1, count: 4), [Float](repeating: 0.1, count: 4)], from: "BRIO", at: 6 * millisecond)
        #expect(guide.hasReceived(upTo: 10))
        _ = guide.mix(upTo: 8)
        #expect(guide.hasReceived(upTo: 10))
        #expect(!guide.hasReceived(upTo: 11))
    }

    @Test func eachSourceIsAveragedToMonoAndTheSourcesAreSummedAtUnityGain() {
        var guide = mix()
        guide.add(source: "MacBook Pro Microphone", channelCount: 1)
        guide.add(source: "RØDE Wireless GO II RX", channelCount: 2)
        guide.receive([[0.1, 0.1]], from: "MacBook Pro Microphone", at: 0)
        guide.receive([[0.1, -0.2], [0.2, -0.4]], from: "RØDE Wireless GO II RX", at: 0)
        let mixed = guide.mix(until: 2 * millisecond)[0]
        #expect(mixed.count == 2)
        #expect(abs(mixed[0] - 0.25) < 1e-6)
        #expect(abs(mixed[1] - -0.2) < 1e-6)
        #expect(guide.mixedUpTo == 2)
    }

    @Test func oneLiveMicrophoneAmongSilentOnesKeepsItsLevel() {
        var guide = mix()
        for name in ["Razer", "CalDigit", "BRIO", "MacBook Pro Microphone"] {
            guide.add(source: name, channelCount: name == "BRIO" ? 2 : 1)
        }
        guide.receive([[0.2, -0.15]], from: "Razer", at: 0)
        guide.receive([[0, 0]], from: "CalDigit", at: 0)
        guide.receive([[0, 0], [0, 0]], from: "BRIO", at: 0)
        #expect(guide.mix(until: 2 * millisecond)[0] == [0.2, -0.15])
    }

    @Test func aStereoSourceWithIdenticalChannelsHasItsMonoLevel() {
        var stereo = mix()
        stereo.add(source: "BRIO", channelCount: 2)
        stereo.receive([[0.3, -0.1], [0.3, -0.1]], from: "BRIO", at: 0)
        var mono = mix()
        mono.add(source: "BRIO", channelCount: 1)
        mono.receive([[0.3, -0.1]], from: "BRIO", at: 0)
        #expect(stereo.mix(until: 2 * millisecond) == mono.mix(until: 2 * millisecond))
    }

    @Test func twoLoudSourcesNeverExceedFullScale() {
        var guide = mix()
        guide.add(source: "A", channelCount: 1)
        guide.add(source: "B", channelCount: 2)
        guide.receive([[1, -1, 0.9, 1]], from: "A", at: 0)
        guide.receive([[1, -1, 0.9, 0.2], [1, -1, 0.9, 0.2]], from: "B", at: 0)
        let mixed = guide.mix(until: 4 * millisecond)[0]
        #expect(mixed.allSatisfy { abs($0) <= GuideTrackMix.limiterCeiling })
        #expect(mixed[0] > 0.5 && mixed[1] < -0.5)
        for (sample, sum) in zip(mixed, [2, -2, 1.8, 1.2] as [Float]) { #expect(abs(sample - limited(sum)) < 1e-6) }
    }

    @Test func belowTheKneeTheLevelIsUnchanged() {
        // The knee at −12 dBFS, the ceiling at −6 dBFS: D52's 6 dB between them (D75).
        #expect(abs(GuideTrackMix.limiterKnee - 0.251_19) < 1e-5)
        #expect(abs(GuideTrackMix.limiterCeiling - 0.501_19) < 1e-5)
        var guide = mix()
        guide.add(source: "A", channelCount: 1)
        guide.add(source: "B", channelCount: 1)
        guide.receive([[0.125, -0.125, 0.1]], from: "A", at: 0)
        guide.receive([[0.125, -0.125, -0.1]], from: "B", at: 0)
        #expect(guide.mix(until: 3 * millisecond)[0] == [0.25, -0.25, 0])
        // Just above it, the curve starts with the same slope: no step.
        #expect(GuideTrackMix.limit(GuideTrackMix.limiterKnee) == GuideTrackMix.limiterKnee)
        let above = GuideTrackMix.limiterKnee + 0.0001
        #expect(abs(GuideTrackMix.limit(above) - above) < 1e-6)
        #expect(GuideTrackMix.limit(100) <= GuideTrackMix.limiterCeiling)
        #expect(GuideTrackMix.limit(-100) >= -GuideTrackMix.limiterCeiling)
        #expect(GuideTrackMix.limit(2) > 0.5)
    }

    @Test func eachInputIsPlacedByItsOwnTimestampsAndAMissingInputIsSilence() {
        var guide = mix()
        guide.add(source: "A", channelCount: 1)
        guide.add(source: "B", channelCount: 1)
        guide.receive([[0.2, 0.2]], from: "A", at: 2 * millisecond)
        guide.receive([[0.05]], from: "B", at: 3 * millisecond)
        let mixed = guide.mix(until: 5 * millisecond)[0]
        let expected: [Float] = [0, 0, 0.2, 0.25, 0]
        #expect(mixed.count == expected.count)
        for (sample, want) in zip(mixed, expected) { #expect(abs(sample - want) < 1e-6, "\(mixed)") }
    }

    @Test func aPeekMixesWhatWaitsWithoutTakingIt() {
        var guide = mix(delay: .milliseconds(2))
        guide.add(source: "A", channelCount: 1)
        guide.receive([[0.05, 0.1, 0.15, 0.2, 0.25]], from: "A", at: 0)
        #expect(guide.mix(until: 4 * millisecond)[0] == [0.05, 0.1])
        let peeked = guide.peek(upTo: 6)
        #expect(peeked.start == 2)
        #expect(peeked.channels[0] == [0.15, 0.2, 0.25, 0])
        #expect(guide.peek(upTo: 1).channels[0].isEmpty)
        // Nothing was taken: the next mix still has it.
        #expect(guide.mixedUpTo == 2)
        #expect(guide.mix(until: 7 * millisecond)[0] == [0.15, 0.2, 0.25])
    }

    @Test func aSampleThatIsNotFiniteBecomesSilence() {
        #expect(GuideTrackMix.limit(.nan) == 0)
        #expect(GuideTrackMix.limit(.infinity) == 0)
        #expect(GuideTrackMix.limit(-.infinity) == 0)
        var guide = mix()
        guide.add(source: "A", channelCount: 1)
        guide.receive([[.nan, .infinity, 0.25]], from: "A", at: 0)
        #expect(guide.mix(until: 3 * millisecond)[0] == [0, 0, 0.25])
        var system = GuideTrackMix(.systemAudio, sampleRate: 1000, delay: .zero)
        system.add(source: "System audio", channelCount: 2)
        system.receive([[.nan], [-.infinity]], from: "System audio", at: 0)
        #expect(system.mix(until: 1 * millisecond) == [[0], [0]])
    }

    @Test func aBufferWhollyBeforeWhatIsMixedIsDropped() {
        var guide = mix()
        guide.add(source: "A", channelCount: 1)
        _ = guide.mix(until: 1000 * millisecond)
        guide.receive([[Float](repeating: 0.5, count: 512)], from: "A", at: 0)
        guide.receive([[0.25]], from: "A", at: 1000 * millisecond)
        #expect(guide.mix(until: 1001 * millisecond)[0] == [0.25])
    }

    @Test func theMixRunsTheDelayBehindRealTime() {
        var guide = mix(delay: .milliseconds(200))
        guide.add(source: "A", channelCount: 1)
        #expect(guide.mix(until: 150 * millisecond)[0].isEmpty)
        guide.receive([[0.25, 0.25]], from: "A", at: 0)
        #expect(guide.mix(until: 201 * millisecond)[0] == [0.25])
        #expect(guide.mix(until: 203 * millisecond)[0] == [0.25, 0])
        #expect(guide.mixedUpTo == 3)
    }

    @Test func samplesAtPositionsAlreadyMixedAreDropped() {
        var guide = mix()
        guide.add(source: "A", channelCount: 1)
        _ = guide.mix(until: 2 * millisecond)[0]
        guide.receive([[0.05, 0.1, 0.15]], from: "A", at: 1 * millisecond)
        #expect(guide.mix(until: 4 * millisecond)[0] == [0.1, 0.15])
    }

    @Test func anInputThatLeavesNoLongerCounts() {
        var guide = mix()
        guide.add(source: "A", channelCount: 1)
        guide.add(source: "B", channelCount: 1)
        guide.receive([[0.25]], from: "B", at: 0)
        guide.remove(source: "B")
        guide.receive([[0.25]], from: "A", at: 0)
        #expect(!guide.contains(source: "B"))
        #expect(guide.mix(until: 1 * millisecond)[0] == [0.25])
    }

    /// An input placed earlier by its audio delay: its sample at time t is mixed at t less the placement (D80).
    @Test func anInputPlacedEarlierIsMixedThatMuchEarlier() {
        var guide = mix()
        guide.add(source: "A", channelCount: 1)
        guide.add(source: "Late", channelCount: 1, earlierBy: 2)
        guide.receive([[0.1, 0.1, 0.1, 0.1, 0.1, 0.1]], from: "A", at: 0)
        guide.receive([[0, 0, 0.05, 0.05, 0.05, 0.05]], from: "Late", at: 0)
        // Until the late input has delivered 2 samples beyond, the mix has not received up to a position.
        #expect(!guide.hasReceived(upTo: 6))
        #expect(guide.hasReceived(upTo: 4))
        let mixed = guide.mix(until: 4 * millisecond)[0]
        for (sample, want) in zip(mixed, [Float](repeating: 0.15, count: 4)) { #expect(abs(sample - want) < 1e-6, "\(mixed)") }
        #expect(mixed.count == 4)
    }

    /// An input not in the guide track yet is received but not mixed, and not waited for; placed, its
    /// samples kept from the next position to mix on are mixed (D80).
    @Test func anInputNotPlacedYetIsKeptButNotMixed() {
        var guide = mix()
        guide.add(source: "A", channelCount: 1, earlierBy: nil)
        #expect(guide.contains(source: "A") && !guide.isMixed(source: "A"))
        guide.receive([[0.01, 0.02, 0.03, 0.04, 0.05, 0.06]], from: "A", at: 0)
        #expect(guide.hasReceived(upTo: 100))
        #expect(guide.mix(until: 2 * millisecond)[0] == [0, 0])
        guide.place(source: "A", earlierBy: 1)
        #expect(guide.isMixed(source: "A"))
        #expect(guide.mix(until: 4 * millisecond)[0] == [0.04, 0.05])
        guide.place(source: "A", earlierBy: nil)
        #expect(guide.mix(until: 5 * millisecond)[0] == [0])
    }

    /// A change of placement fades over the crossfade from the earlier placement to the new one, from the
    /// next position to mix on; then only the new one plays (D80).
    @Test func aChangeOfPlacementCrossfades() {
        let fade = Int(RecorderValues.guideTrackCrossfade.nanoseconds / millisecond)
        var guide = mix()
        guide.add(source: "A", channelCount: 1)
        // Sample n is n / 1000: the placement shows in the values.
        guide.receive([(0..<200).map { Float($0) / 1000 }], from: "A", at: 0)
        #expect(guide.mix(until: 10 * millisecond)[0].last == 0.009)
        guide.place(source: "A", earlierBy: 50)
        let mixed = guide.mix(until: Int64(10 + fade + 5) * millisecond)[0]
        for index in 0..<(fade + 5) {
            let weight = Float(min(index, fade)) / Float(fade)
            let position = Float(10 + index)
            let want = ((1 - weight) * position + weight * (position + 50)) / 1000
            #expect(abs(mixed[index] - want) < 1e-6, "at \(index): \(mixed[index]), expected \(want)")
        }
        // Moving later again needs samples already mixed at the earlier placement: they are kept.
        guide.place(source: "A", earlierBy: 0)
        let back = guide.mix(until: Int64(10 + 2 * fade + 10) * millisecond)[0]
        #expect(abs(back.last! - Float(10 + 2 * fade + 9) / 1000) < 1e-6)
    }

    @Test func withNoInputTheMixIsSilence() {
        var guide = mix()
        #expect(guide.mix(until: 3 * millisecond)[0] == [0, 0, 0])
    }

    @Test func theDelayIsTheDesignsStartingPoint() {
        #expect(GuideTrackMix(.audioInputs).delay == 1000 * millisecond)
        #expect(RecorderValues.guideTrackCrossfade == .milliseconds(20))
        #expect(GuideTrackMix(.audioInputs).sampleRate == RecorderValues.audioSampleRate)
    }

    @Test func theSystemAudioGuideTrackKeepsItsTwoChannels() {
        var guide = GuideTrackMix(.systemAudio, sampleRate: 1000, delay: .zero)
        guide.add(source: "System audio", channelCount: 2)
        guide.receive([[0.5, 2], [-0.25, 0]], from: "System audio", at: 0)
        #expect(guide.mix(until: 3 * millisecond) == [[0.5, 1, 0], [-0.25, 0, 0]])
    }
}
