import Foundation
import Testing
@testable import RecorderLogic

@Suite struct AudioDelayTests {
    /// Speech-like noise: random bursts, the same for both inputs, `shift` samples later in `other`.
    private static func pair(shift: Int, count: Int = AudioDelay.windowSeconds * AudioDelay.sampleRate, noise: Float = 0.01)
        -> (reference: [Float], other: [Float]) {
        var generator = SeededRandom(seed: 7)
        let source = (0..<(count + 2 * AudioDelay.sampleRate)).map { index -> Float in
            let burst: Float = (index / 1600) % 3 == 0 ? 0.6 : 0.05
            return burst * Float.random(in: -1...1, using: &generator)
        }
        let offset = AudioDelay.sampleRate
        let reference = (0..<count).map { source[offset + $0] + noise * Float.random(in: -1...1, using: &generator) }
        let other = (0..<count).map { source[offset + $0 - shift] + noise * Float.random(in: -1...1, using: &generator) }
        return (reference, other)
    }

    @Test(arguments: [4400, -1200, 0, 3])
    func aKnownShiftIsRecoveredWithinAMillisecond(shift: Int) throws {
        let (reference, other) = Self.pair(shift: shift)
        let window = try #require(AudioDelay.window(reference: reference, other: other))
        #expect(abs(window.lag - Double(shift) / Double(AudioDelay.sampleRate)) < 0.001)
        #expect(window.counts)
    }

    @Test func unrelatedNoiseGivesNoClearWindowAndNoDelay() throws {
        var generator = SeededRandom(seed: 3)
        let count = AudioDelay.windowSeconds * AudioDelay.sampleRate
        let reference = (0..<count).map { _ in Float.random(in: -0.1...0.1, using: &generator) }
        let other = (0..<count).map { _ in Float.random(in: -0.1...0.1, using: &generator) }
        let window = try #require(AudioDelay.window(reference: reference, other: other))
        #expect(!window.counts)
        #expect(AudioDelay.delay(ofCountedLags: []) == nil)
    }

    @Test func aSilentWindowIsNotMeasured() {
        let count = AudioDelay.windowSeconds * AudioDelay.sampleRate
        let (reference, _) = Self.pair(shift: 0)
        #expect(AudioDelay.window(reference: reference, other: [Float](repeating: 0, count: count)) == nil)
    }

    @Test func theDelayIsTheMedianOfAtLeastThreeCountedWindows() {
        #expect(AudioDelay.delay(ofCountedLags: [0.55, 0.56]) == nil)
        #expect(AudioDelay.delay(ofCountedLags: [0.55, 0.52, 0.6]) == 0.55)
        #expect(AudioDelay.delay(ofCountedLags: [0.5, 0.52, 0.6, 0.4]) == 0.51)
    }

    /// The earliest measured input is 0: a delayed reference (an Osmo, a Bluetooth microphone)
    /// moves itself later, never the others (D77).
    @Test func theDelaysAreNormalizedSoTheEarliestInputIsZero() {
        #expect(AudioDelay.normalized(["a": 0.5, "b": -0.25], reference: "r") == ["a": 0.75, "b": 0, "r": 0.25])
        #expect(AudioDelay.normalized(["a": 0.55], reference: "r") == ["a": 0.55])
        #expect(AudioDelay.normalized(["a": -0.1], reference: nil) == ["a": 0])
        #expect(AudioDelay.normalized([:], reference: "r") == [:])
    }

    /// A file's lags count against one reference: a new reference starts it again (D77).
    @Test func aNewReferenceStartsAFilesLagsAgain() {
        var lags = AudioDelay.Lags()
        for lag in [0.5, 0.5, 0.5] { lags.add(lag, file: "a", reference: "r1") }
        for lag in [-0.25, -0.25, -0.25] { lags.add(lag, file: "b", reference: "r1") }
        #expect(lags.delays(of: ["a", "b"], reference: "r1", referenceFile: "r1 file") == ["a": 0.75, "b": 0, "r1 file": 0.25])
        lags.add(0.5, file: "a", reference: "r2")
        #expect(lags.delays(of: ["a", "b"], reference: "r2", referenceFile: nil) == [:])
        for lag in [0.25, 0.25] { lags.add(lag, file: "a", reference: "r2") }
        #expect(lags.delays(of: ["a"], reference: "r2", referenceFile: nil) == ["a": 0.25])
    }

    @Test func theDelayReadsLateOrEarly() {
        #expect(AudioDelay.text(0.5504) == "550 ms late")
        #expect(AudioDelay.text(-0.03) == "30 ms early")
        #expect(AudioDelay.text(0.0002) == "0 ms")
    }

    @Test func downsamplingAveragesTheChannelsAndCarriesTheRest() {
        var carry: [Float] = []
        let first = AudioDelay.downsampled([[Float](repeating: 1, count: 8), [Float](repeating: 0, count: 8)], carry: &carry)
        #expect(first == [0.5])
        #expect(carry == [0.5, 0.5])
        let second = AudioDelay.downsampled([[Float](repeating: 0.5, count: 4)], carry: &carry)
        #expect(second == [0.5])
        #expect(carry.isEmpty)
    }
}
