import Testing
@testable import RecorderLogic

@Suite struct GuideTrackMixTests {
    private let millisecond: Int64 = 1_000_000

    /// A mix at 1 kHz with no delay, so positions are milliseconds.
    private func mix(delay: Duration = .zero) -> GuideTrackMix {
        GuideTrackMix(.microphones, sampleRate: 1000, delay: delay)
    }

    @Test func theMixIsTheSumOfAllChannelsDividedByTheRootOfTheirCount() {
        var guide = mix()
        guide.add(source: "MacBook Pro Microphone", channelCount: 1)
        guide.add(source: "RØDE Wireless GO II RX", channelCount: 2)
        #expect(guide.channelCount == 3)
        guide.receive([[0.3, 0.3]], from: "MacBook Pro Microphone", at: 0)
        guide.receive([[0.1, -0.2], [0.2, -0.4]], from: "RØDE Wireless GO II RX", at: 0)
        let mixed = guide.mix(until: 2 * millisecond)[0]
        let root3 = Float(3).squareRoot()
        #expect(mixed.count == 2)
        #expect(abs(mixed[0] - 0.6 / root3) < 1e-6)
        #expect(abs(mixed[1] - -0.3 / root3) < 1e-6)
        #expect(guide.mixedUpTo == 2)
    }

    @Test func theMixIsClampedToPlusMinusOne() {
        var guide = mix()
        guide.add(source: "A", channelCount: 2)
        guide.receive([[1, -1], [1, -1]], from: "A", at: 0)
        #expect(guide.mix(until: 2 * millisecond)[0] == [1, -1])
    }

    @Test func eachInputIsPlacedByItsOwnTimestampsAndAMissingInputIsSilence() {
        var guide = mix()
        guide.add(source: "A", channelCount: 1)
        guide.add(source: "B", channelCount: 1)
        let half = 1 / Float(2).squareRoot()
        guide.receive([[1, 1]], from: "A", at: 2 * millisecond)
        guide.receive([[0.2]], from: "B", at: 3 * millisecond)
        let mixed = guide.mix(until: 5 * millisecond)[0]
        let expected: [Float] = [0, 0, half, 1.2 * half, 0]
        #expect(mixed.count == expected.count)
        for (sample, want) in zip(mixed, expected) { #expect(abs(sample - want) < 1e-6, "\(mixed)") }
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
        guide.remove(source: "B")
        guide.receive([[0.5]], from: "A", at: 0)
        #expect(guide.channelCount == 1)
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
