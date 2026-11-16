import Foundation
import Testing
@testable import RecorderLogic

@Suite struct GuideTrackMixTests {
    private let millisecond: Int64 = 1_000_000

    /// A mix at 1 kHz with no delay, so positions are milliseconds.
    private func mix(delay: Duration = .zero) -> GuideTrackMix {
        GuideTrackMix(.microphones, sampleRate: 1000, delay: delay)
    }

    /// The soft limiter's output for `x`, as the design states it.
    private func limited(_ x: Float) -> Float {
        let knee = GuideTrackMix.limiterKnee
        guard abs(x) > knee else { return x }
        return (x < 0 ? -1 : 1) * (knee + (1 - knee) * tanh((abs(x) - knee) / (1 - knee)))
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
        guide.receive([[0.3, -0.2]], from: "Razer", at: 0)
        guide.receive([[0, 0]], from: "CalDigit", at: 0)
        guide.receive([[0, 0], [0, 0]], from: "BRIO", at: 0)
        #expect(guide.mix(until: 2 * millisecond)[0] == [0.3, -0.2])
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
        #expect(mixed.allSatisfy { abs($0) <= 1 })
        #expect(mixed[0] > 0.9 && mixed[1] < -0.9)
        for (sample, sum) in zip(mixed, [2, -2, 1.8, 1.2] as [Float]) { #expect(abs(sample - limited(sum)) < 1e-6) }
    }

    @Test func belowTheKneeTheLevelIsUnchanged() {
        #expect(GuideTrackMix.limiterKnee == 0.5)
        var guide = mix()
        guide.add(source: "A", channelCount: 1)
        guide.add(source: "B", channelCount: 1)
        guide.receive([[0.25, -0.3, 0.1]], from: "A", at: 0)
        guide.receive([[0.25, -0.2, -0.1]], from: "B", at: 0)
        #expect(guide.mix(until: 3 * millisecond)[0] == [0.5, -0.5, 0])
        // Just above it, the curve starts with the same slope: no step.
        #expect(abs(GuideTrackMix.limit(0.5001) - 0.5001) < 1e-6)
        #expect(GuideTrackMix.limit(100) <= 1)
        #expect(GuideTrackMix.limit(-100) >= -1)
    }

    @Test func eachInputIsPlacedByItsOwnTimestampsAndAMissingInputIsSilence() {
        var guide = mix()
        guide.add(source: "A", channelCount: 1)
        guide.add(source: "B", channelCount: 1)
        guide.receive([[0.4, 0.4]], from: "A", at: 2 * millisecond)
        guide.receive([[0.05]], from: "B", at: 3 * millisecond)
        let mixed = guide.mix(until: 5 * millisecond)[0]
        let expected: [Float] = [0, 0, 0.4, 0.45, 0]
        #expect(mixed.count == expected.count)
        for (sample, want) in zip(mixed, expected) { #expect(abs(sample - want) < 1e-6, "\(mixed)") }
    }

    @Test func aMixReadsWhatIsMixedAndWhatWaitsWithoutTakingIt() {
        var guide = mix(delay: .milliseconds(2))
        guide.add(source: "A", channelCount: 1)
        guide.receive([[0.1, 0.2, 0.3, 0.4, 0.5]], from: "A", at: 0)
        #expect(guide.mix(until: 4 * millisecond)[0] == [0.1, 0.2])
        // From before what is mixed, up past it: the recent mix, then what waits.
        #expect(guide.read(from: 1, upTo: 5)[0] == [0.2, 0.3, 0.4, 0.5])
        #expect(guide.mixedUpTo == 2)
        #expect(guide.mix(until: 7 * millisecond)[0] == [0.3, 0.4, 0.5])
        // Older than the history kept: silence.
        #expect(guide.read(from: -2, upTo: 1)[0] == [0, 0, 0.1])
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
        guide.receive([[0.5, 0.5]], from: "A", at: 0)
        #expect(guide.mix(until: 201 * millisecond)[0] == [0.5])
        #expect(guide.mix(until: 203 * millisecond)[0] == [0.5, 0])
        #expect(guide.mixedUpTo == 3)
    }

    @Test func samplesAtPositionsAlreadyMixedAreDropped() {
        var guide = mix()
        guide.add(source: "A", channelCount: 1)
        _ = guide.mix(until: 2 * millisecond)[0]
        guide.receive([[0.1, 0.2, 0.3]], from: "A", at: 1 * millisecond)
        #expect(guide.mix(until: 4 * millisecond)[0] == [0.2, 0.3])
    }

    @Test func anInputThatLeavesNoLongerCounts() {
        var guide = mix()
        guide.add(source: "A", channelCount: 1)
        guide.add(source: "B", channelCount: 1)
        guide.receive([[0.5]], from: "B", at: 0)
        guide.remove(source: "B")
        guide.receive([[0.5]], from: "A", at: 0)
        #expect(!guide.contains(source: "B"))
        #expect(guide.mix(until: 1 * millisecond)[0] == [0.5])
    }

    @Test func withNoInputTheMixIsSilence() {
        var guide = mix()
        #expect(guide.mix(until: 3 * millisecond)[0] == [0, 0, 0])
    }

    @Test func theDelayIsTheDesignsStartingPoint() {
        #expect(GuideTrackMix(.microphones).delay == 200 * millisecond)
        #expect(GuideTrackMix(.microphones).sampleRate == RecorderValues.audioSampleRate)
    }

    @Test func theSystemAudioGuideTrackKeepsItsTwoChannels() {
        var guide = GuideTrackMix(.systemAudio, sampleRate: 1000, delay: .zero)
        guide.add(source: "System audio", channelCount: 2)
        guide.receive([[0.5, 2], [-0.25, 0]], from: "System audio", at: 0)
        #expect(guide.mix(until: 3 * millisecond) == [[0.5, 1, 0], [-0.25, 0, 0]])
    }
}
