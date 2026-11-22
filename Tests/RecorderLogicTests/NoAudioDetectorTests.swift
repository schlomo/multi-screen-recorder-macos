import Testing
@testable import RecorderLogic

/// Which of an audio input's samples are placed in its audio files, and
/// where it has no audio, at a threshold of 100 samples and 8 leading zeros.
@Suite struct NoAudioDetectorTests {
    private func detector() -> NoAudioDetector {
        NoAudioDetector(threshold: 100, leadingZeros: 8)
    }

    private func zeros(_ count: Int, channels: Int = 1) -> [[Float]] {
        Array(repeating: [Float](repeating: 0, count: count), count: channels)
    }

    private func sound(_ count: Int, channels: Int = 1) -> [[Float]] {
        Array(repeating: [Float](repeating: 0.25, count: count), count: channels)
    }

    private func joined(_ chunks: [[Float]]...) -> [[Float]] {
        chunks[0].indices.map { channel in chunks.flatMap { $0[channel] } }
    }

    @Test func soundIsPlacedWhole() {
        var detector = detector()
        #expect(detector.steps(for: sound(50), isPlacing: false) == [.place(frames: 0..<50, leadingZeros: 0)])
        #expect(detector.steps(for: sound(50), isPlacing: true) == [.place(frames: 0..<50, leadingZeros: 0)])
    }

    @Test func zerosBeforeTheFirstSoundAreNotPlacedButTheLeadingZerosBeforeIt() {
        var detector = detector()
        #expect(detector.steps(for: zeros(30), isPlacing: false).isEmpty)
        #expect(detector.steps(for: joined(zeros(20), sound(10)), isPlacing: false) == [.place(frames: 20..<30, leadingZeros: 8)])
    }

    @Test func atTheVeryStartFewerZerosThanTheLeadingZerosAreAllThereIs() {
        var detector = detector()
        #expect(detector.steps(for: joined(zeros(3), sound(10)), isPlacing: false) == [.place(frames: 3..<13, leadingZeros: 3)])
    }

    @Test func zerosShorterThanTheThresholdInAFileArePlaced() {
        var detector = detector()
        _ = detector.steps(for: sound(10), isPlacing: false)
        #expect(detector.steps(for: zeros(60), isPlacing: true) == [.place(frames: 0..<60, leadingZeros: 0)])
        #expect(detector.steps(for: joined(zeros(39), sound(5)), isPlacing: true) == [.place(frames: 0..<44, leadingZeros: 0)])
        #expect(!detector.isNoAudio)
    }

    @Test func zerosForTheThresholdEndTheFileWhereTheyReachIt() {
        var detector = detector()
        _ = detector.steps(for: sound(10), isPlacing: false)
        #expect(detector.steps(for: zeros(60), isPlacing: true) == [.place(frames: 0..<60, leadingZeros: 0)])
        #expect(detector.steps(for: zeros(60), isPlacing: true) == [.place(frames: 0..<40, leadingZeros: 0), .noAudioStarted(atFrame: 40)])
        #expect(detector.isNoAudio)
        #expect(detector.steps(for: zeros(60), isPlacing: false).isEmpty)
    }

    @Test func soundAfterNoAudioStartsANewFileWithTheLeadingZeros() {
        var detector = detector()
        _ = detector.steps(for: sound(10), isPlacing: false)
        _ = detector.steps(for: zeros(100), isPlacing: true)
        #expect(detector.steps(for: joined(zeros(5), sound(10), zeros(5)), isPlacing: false) == [
            .noAudioStopped(atFrame: 5), .place(frames: 5..<20, leadingZeros: 8),
        ])
        #expect(!detector.isNoAudio)
    }

    @Test func noAudioFromTheStartGetsNoFile() {
        var detector = detector()
        #expect(detector.steps(for: zeros(99), isPlacing: false).isEmpty)
        #expect(detector.steps(for: zeros(1), isPlacing: false) == [.noAudioStarted(atFrame: 1)])
        #expect(detector.steps(for: zeros(500), isPlacing: false).isEmpty)
        #expect(detector.steps(for: sound(4), isPlacing: false) == [.noAudioStopped(atFrame: 0), .place(frames: 0..<4, leadingZeros: 8)])
    }

    @Test func noAudioThatStartsAndStopsInOneChunkEndsTheFileAndStartsAnother() {
        var detector = detector()
        _ = detector.steps(for: sound(10), isPlacing: false)
        #expect(detector.steps(for: joined(sound(10), zeros(150), sound(10)), isPlacing: true) == [
            .place(frames: 0..<110, leadingZeros: 0), .noAudioStarted(atFrame: 110), .noAudioStopped(atFrame: 160),
            .place(frames: 160..<170, leadingZeros: 8),
        ])
    }

    @Test func aFrameHasSoundWhenAnyChannelIsNotZero() {
        var detector = detector()
        let left: [Float] = [0, 0, 0.5, 0]
        let right: [Float] = [0, 0, 0, 0]
        #expect(detector.steps(for: [left, right], isPlacing: false) == [.place(frames: 2..<4, leadingZeros: 2)])
        // Negative zero is a zero too.
        #expect(detector.steps(for: [[-0.0, 0], [0, -0.0]], isPlacing: true) == [.place(frames: 0..<2, leadingZeros: 0)])
    }

    @Test func aFileThatEndedForAnotherReasonStartsAgainOnlyWithSound() {
        var detector = detector()
        _ = detector.steps(for: sound(10), isPlacing: false)
        // The capture's file ended (a gap, a change of the channel count): zeros start none.
        #expect(detector.steps(for: zeros(20), isPlacing: false).isEmpty)
        #expect(detector.steps(for: sound(5), isPlacing: false) == [.place(frames: 0..<5, leadingZeros: 8)])
    }
}
