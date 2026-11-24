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
        #expect(AudioDelay.Applied().delay == nil)
    }

    @Test func aSilentWindowIsNotMeasured() {
        let count = AudioDelay.windowSeconds * AudioDelay.sampleRate
        let (reference, _) = Self.pair(shift: 0)
        #expect(AudioDelay.window(reference: reference, other: [Float](repeating: 0, count: count)) == nil)
    }

    @Test func theAudioDelaysValuesAreData() {
        #expect(AudioDelay.windowsNeeded == 3)
        #expect(RecorderValues.audioDelayChangeWindowSeconds == 60)
        #expect(RecorderValues.audioDelayChangeWindows == 5)
        #expect(RecorderValues.audioDelayTolerance == 1.0 / 30)
    }

    /// Counted windows `lags`, 10 s apart from 10 s on; the audio delay after each.
    private func applied(_ lags: [Double], from start: AudioDelay.Applied = AudioDelay.Applied()) -> [Double?] {
        var applied = start
        return lags.enumerated().map { index, lag in
            applied.add(lag, at: Double(index + 1) * 10)
            // To a microsecond: a median of an even count averages two lags.
            return applied.delay.map { ($0 * 1e6).rounded() / 1e6 }
        }
    }

    /// The first counted window sets the audio delay, the third once more to the median if it lies more than
    /// a frame away; one frame or less changes nothing (D80).
    @Test func theFirstCountedWindowSetsTheAudioDelayAndTheThirdCorrectsIt() {
        #expect(applied([0.01, 0.5, 0.5]) == [0.01, 0.01, 0.5])
        #expect(applied([0.55, 0.52, 0.53]) == [0.55, 0.55, 0.55])
    }

    /// After the third, only the median of the latest 60 s, at least 5 counted windows, changes it, and only
    /// beyond a frame: a single stray window never does (D80).
    @Test func afterTheThirdOnlyTheMedianOfTheLatestMinuteChangesIt() {
        let lags = [0.55, 0.55, 0.55, 0.9, 0.47, 0.47, 0.47, 0.47, 0.47, 0.47]
        // From the 7th the latest 60 s hold 6 windows: their median 0.51, then 0.47.
        #expect(applied(lags) == [0.55, 0.55, 0.55, 0.55, 0.55, 0.55, 0.51, 0.47, 0.47, 0.47])
        // Fewer than 5 counted windows in the latest 60 s: no change, however far the median.
        var sparse = AudioDelay.Applied()
        for (index, lag) in [0.55, 0.55, 0.55].enumerated() { sparse.add(lag, at: Double(index + 1) * 10) }
        for (index, lag) in [0.3, 0.3, 0.3, 0.3].enumerated() { sparse.add(lag, at: 100 + Double(index) * 20) }
        #expect(sparse.delay == 0.55)
    }

    /// A carried-over audio delay holds until the file's own first counted window: within a frame it is
    /// confirmed, beyond it replaced; either way it is measured from then on (D80).
    @Test func aCarriedOverAudioDelayIsConfirmedOrReplacedByTheFirstOwnWindow() {
        var confirmed = AudioDelay.Applied(carriedOver: 0.55)
        #expect(confirmed.isCarriedOver)
        let changed = confirmed.add(0.56, at: 10)
        #expect(!changed)
        #expect(confirmed.delay == 0.55 && !confirmed.isCarriedOver)
        var replaced = AudioDelay.Applied(carriedOver: 0.55)
        let replacedChanged = replaced.add(0.47, at: 10)
        #expect(replacedChanged)
        #expect(replaced.delay == 0.47 && !replaced.isCarriedOver)
        #expect(applied([0.47, 0.6, 0.6], from: AudioDelay.Applied(carriedOver: 0.55)) == [0.47, 0.47, 0.6])
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
