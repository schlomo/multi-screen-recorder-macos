import Testing
@testable import RecorderLogic

@Suite struct MicrophonesGuideTrackMixTests {
    private let millisecond: Int64 = 1_000_000

    /// A mix at 1 kHz with no delay, so positions are milliseconds.
    private func mix(delay: Duration = .zero) -> MicrophonesGuideTrackMix {
        MicrophonesGuideTrackMix(sampleRate: 1000, delay: delay)
    }

    @Test func theMixIsTheSumOfAllChannelsDividedByTheRootOfTheirCount() {
        var guide = mix()
        guide.add(input: "MacBook Pro Microphone", channelCount: 1)
        guide.add(input: "RØDE Wireless GO II RX", channelCount: 2)
        #expect(guide.channelCount == 3)
        guide.receive([[0.3, 0.3]], from: "MacBook Pro Microphone", at: 0)
        guide.receive([[0.1, -0.2], [0.2, -0.4]], from: "RØDE Wireless GO II RX", at: 0)
        let mixed = guide.mix(until: 2 * millisecond)
        let root3 = Float(3).squareRoot()
        #expect(mixed.count == 2)
        #expect(abs(mixed[0] - 0.6 / root3) < 1e-6)
        #expect(abs(mixed[1] - -0.3 / root3) < 1e-6)
        #expect(guide.mixedUpTo == 2)
    }

    @Test func theMixIsClampedToPlusMinusOne() {
        var guide = mix()
        guide.add(input: "A", channelCount: 2)
        guide.receive([[1, -1], [1, -1]], from: "A", at: 0)
        #expect(guide.mix(until: 2 * millisecond) == [1, -1])
    }

    @Test func eachInputIsPlacedByItsOwnTimestampsAndAMissingInputIsSilence() {
        var guide = mix()
        guide.add(input: "A", channelCount: 1)
        guide.add(input: "B", channelCount: 1)
        let half = 1 / Float(2).squareRoot()
        guide.receive([[1, 1]], from: "A", at: 2 * millisecond)
        guide.receive([[0.2]], from: "B", at: 3 * millisecond)
        let mixed = guide.mix(until: 5 * millisecond)
        let expected: [Float] = [0, 0, half, 1.2 * half, 0]
        #expect(mixed.count == expected.count)
        for (sample, want) in zip(mixed, expected) { #expect(abs(sample - want) < 1e-6, "\(mixed)") }
    }

    @Test func theMixRunsTheDelayBehindRealTime() {
        var guide = mix(delay: .milliseconds(200))
        guide.add(input: "A", channelCount: 1)
        #expect(guide.mix(until: 150 * millisecond).isEmpty)
        guide.receive([[0.5, 0.5]], from: "A", at: 0)
        #expect(guide.mix(until: 201 * millisecond) == [0.5])
        #expect(guide.mix(until: 203 * millisecond) == [0.5, 0])
        #expect(guide.mixedUpTo == 3)
    }

    @Test func samplesAtPositionsAlreadyMixedAreDropped() {
        var guide = mix()
        guide.add(input: "A", channelCount: 1)
        _ = guide.mix(until: 2 * millisecond)
        guide.receive([[0.1, 0.2, 0.3]], from: "A", at: 1 * millisecond)
        #expect(guide.mix(until: 4 * millisecond) == [0.2, 0.3])
    }

    @Test func anInputThatLeavesNoLongerCounts() {
        var guide = mix()
        guide.add(input: "A", channelCount: 1)
        guide.add(input: "B", channelCount: 1)
        guide.remove(input: "B")
        guide.receive([[0.5]], from: "A", at: 0)
        #expect(guide.channelCount == 1)
        #expect(guide.mix(until: 1 * millisecond) == [0.5])
    }

    @Test func withNoInputTheMixIsSilence() {
        var guide = mix()
        #expect(guide.mix(until: 3 * millisecond) == [0, 0, 0])
    }

    @Test func theDelayIsTheDesignsStartingPoint() {
        #expect(MicrophonesGuideTrackMix().delay == 200 * millisecond)
        #expect(MicrophonesGuideTrackMix().sampleRate == RecorderValues.audioSampleRate)
    }
}
