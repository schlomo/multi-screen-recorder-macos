import Foundation
import Testing
@testable import EndToEndLogic

@Suite struct ToneCheckTests {
    static let rate = 48_000.0

    /// The test tone as recorded: `offset` samples into its own count, so
    /// the clicks fall where they would in a file that started then.
    static func recorded(seconds: Double, offset: Int64 = 12_345, gain: Float = 1, silence: Range<Int>? = nil) -> [Float] {
        let tone = TestTone(sampleRate: rate)
        return (0..<Int(seconds * rate)).map { index in
            if let silence, silence.contains(index) { return 0 }
            return tone.sample(at: Int64(index) + offset) * gain
        }
    }

    func track(_ name: String, _ samples: [Float], startsAt: Double = 1000) -> ToneCheck.Track {
        ToneCheck.Track(name: name, samples: samples, sampleRate: Self.rate, startsAt: startsAt)
    }

    @Test func theToneIsAtMinusTwentyThreeDecibels() {
        #expect(abs(TestTone.levelDecibels - -23.01) < 0.01)
        let samples = Self.recorded(seconds: 4)
        let clicks = SignalAnalysis.clicks(samples, sampleRate: Self.rate)
        #expect(abs(SignalAnalysis.toneLevel(samples, sampleRate: Self.rate, clicks: clicks) - TestTone.levelDecibels) < 0.05)
    }

    @Test func clicksAreFoundOnceASecondAtTheirSample() {
        // The tone's count starts 12_345 samples before the file: the first
        // click starts at 48_000 - 12_345, and its loudest sample is within its millisecond.
        let clicks = SignalAnalysis.clicks(Self.recorded(seconds: 4), sampleRate: Self.rate)
        #expect(clicks.count == 4)
        let first = Double(48_000 - 12_345) / Self.rate
        #expect(clicks.first.map { $0 >= first && $0 < first + TestTone.clickSeconds } == true)
        #expect(zip(clicks, clicks.dropFirst()).allSatisfy { abs($1 - $0 - 1) < 1e-9 })
        #expect(SignalAnalysis.clicks([Float](repeating: 0, count: 100), sampleRate: Self.rate) == [])
    }

    @Test func clickOffsetsPairTheNearestClicks() {
        let offsets = SignalAnalysis.clickOffsets([1, 2, 3], [1.001, 2.002, 9])
        #expect(offsets.count == 2)
        #expect(abs(offsets[0] - 0.001) < 1e-9 && abs(offsets[1] - 0.002) < 1e-9)
    }

    @Test func theToneAsPlayedPasses() {
        let played = Self.recorded(seconds: 6)
        let failures = ToneCheck.failures(
            played: [track("BlackHole, channel 1", played), track("BlackHole, channel 2", played)],
            mixed: [track("Screen 1, Audio inputs", Array(Self.recorded(seconds: 7, offset: 12_345 - 4_800)), startsAt: 999.9)])
        #expect(failures == [])
    }

    @Test func aQuieterToneFails() {
        let failures = ToneCheck.failures(played: [track("BlackHole", Self.recorded(seconds: 4, gain: 0.7))], mixed: [])
        #expect(failures == ["BlackHole: the tone's level is -26.1 dBFS, expected -23.0 dBFS"])
    }

    @Test func aSilentStretchFails() {
        let failures = ToneCheck.failures(played: [track("BlackHole", Self.recorded(seconds: 4, silence: 60_000..<72_000))], mixed: [])
        #expect(failures.contains("BlackHole: 2 silent stretches of 0.1 s, the first at 1.3 s"))
    }

    @Test func aGapBetweenClicksFails() {
        var samples = Self.recorded(seconds: 4)
        samples.removeSubrange(100_000..<100_480)
        let failures = ToneCheck.failures(played: [track("BlackHole", samples)], mixed: [])
        #expect(failures == ["BlackHole: clicks at 1.7431 s and 2.7331 s are not one second apart"])
    }

    @Test func aMixedTrackOffByMoreThanItsToleranceFails() {
        let played = Self.recorded(seconds: 6)
        // 480 samples (10 ms) later than its timecode says.
        let late = Array(Self.recorded(seconds: 6, offset: 12_345 - 480))
        let failures = ToneCheck.failures(played: [track("BlackHole", played)], mixed: [track("Screen 1, Audio inputs", late)])
        #expect(failures == ["Screen 1, Audio inputs: a click is 10.0 ms off BlackHole, by the timecodes"])
    }

    @Test func aMixedTrackWithoutTheClicksFails() {
        let silent = [Float](repeating: 0.001, count: Int(6 * Self.rate))
        let failures = ToneCheck.failures(played: [track("BlackHole", Self.recorded(seconds: 6))], mixed: [track("Screen 1, Audio inputs", silent)])
        #expect(failures.first?.hasPrefix("Screen 1, Audio inputs:") == true)
        #expect(ToneCheck.failures(played: [], mixed: []) == ["no track carries the test tone"])
    }

    @Test func aGapThatAPlaybackBreakOverlapsNamesIt() {
        var samples = Self.recorded(seconds: 4)
        samples.removeSubrange(100_000..<100_480)
        let broke = ToneCheck.failures(played: [track("BlackHole", samples)], mixed: [],
                                       breaks: [PlaybackBreak(timeOfDay: 1002.1, samples: 612)])
        #expect(broke == [
            "BlackHole: clicks at 1.7431 s and 2.7331 s are not one second apart; playback on the loopback device broke at 2.100 s (612 samples); the recording shows it",
        ])
        let elsewhere = ToneCheck.failures(played: [track("BlackHole", samples)], mixed: [],
                                           breaks: [PlaybackBreak(timeOfDay: 1003.5, samples: 612)])
        #expect(elsewhere == ["BlackHole: clicks at 1.7431 s and 2.7331 s are not one second apart"])
        let overload = ToneCheck.failures(played: [track("BlackHole", samples)], mixed: [],
                                          breaks: [PlaybackBreak(timeOfDay: 1002.1, samples: nil)])
        #expect(overload.first?.hasSuffix("playback on the loopback device broke at 2.100 s (an overload); the recording shows it") == true)
    }

    /// The tone with a hole of zeros of `length` samples from `start`; with a hole that swallows a
    /// click, the clicks on either side are two seconds apart.
    private func withHole(_ start: Int, length: Int = 1_536, seconds: Double = 8, removing removed: Int = 0) -> [Float] {
        var samples = Self.recorded(seconds: seconds)
        for index in start..<(start + length) { samples[index] = 0 }
        if removed > 0 { samples.removeSubrange(start..<(start + removed)) }
        return samples
    }

    /// A hole from sample 131_000 (2.7292 s) swallows the click at 2.7428 s.
    private let holeAt = 131_000
    private var brokeAtTheHole: PlaybackBreak { PlaybackBreak(timeOfDay: 1000 + 2.731, samples: nil) }

    @Test func aHoleAtAPlaybackBreakWithWholeSecondSpacingIsPardoned() throws {
        let result = ToneCheck.check(played: [track("BlackHole", withHole(holeAt))], mixed: [], breaks: [brokeAtTheHole])
        #expect(result.failures == [])
        let line = try #require(result.pardoned.first)
        #expect(result.pardoned.count == 1)
        #expect(line.hasPrefix("BlackHole: pardoned: playback broke at 2.731 s, 32."), "\(line)")
        #expect(line.hasSuffix(" ms quiet in the recording, clicks 2.000 s apart"), "\(line)")
    }

    @Test func aHoleWithoutAPlaybackBreakFails() {
        let result = ToneCheck.check(played: [track("BlackHole", withHole(holeAt))], mixed: [], breaks: [])
        #expect(result.failures == ["BlackHole: clicks at 1.7431 s and 3.7431 s are not one second apart"])
        #expect(result.pardoned == [])
    }

    @Test func aBreakFarFromTheHoleDoesNotPardonIt() {
        let result = ToneCheck.check(played: [track("BlackHole", withHole(holeAt))], mixed: [],
                                     breaks: [PlaybackBreak(timeOfDay: 1000 + 2.9, samples: nil)])
        #expect(result.failures.count == 1)
        #expect(result.pardoned == [])
    }

    @Test func aBreakWithoutAHoleWhoseSpacingIsOffFails() {
        var samples = Self.recorded(seconds: 4)
        samples.removeSubrange(100_000..<100_480)
        let result = ToneCheck.check(played: [track("BlackHole", samples)], mixed: [], breaks: [PlaybackBreak(timeOfDay: 1002.1, samples: nil)])
        #expect(result.failures.count == 1)
        #expect(result.pardoned == [])
    }

    @Test func aHoleAtABreakWhoseSpacingIsOffByAFractionFails() {
        // 96 samples (2 ms) taken out of the hole: the clicks are 1.998 s apart, not a whole number of seconds.
        let result = ToneCheck.check(played: [track("BlackHole", withHole(holeAt, removing: 96))], mixed: [], breaks: [brokeAtTheHole])
        #expect(result.failures.count == 1)
        #expect(result.pardoned == [])
    }

    @Test func moreHolesThanBreaksFail() {
        var samples = withHole(holeAt)
        // A second hole, swallowing the click at 5.7428 s, with no break of its own.
        for index in 275_000..<276_536 { samples[index] = 0 }
        let result = ToneCheck.check(played: [track("BlackHole", samples)], mixed: [], breaks: [brokeAtTheHole])
        #expect(result.failures.count == 1)
        #expect(result.pardoned.count == 1)
    }

    @Test func quietRunsAreFoundAtSampleResolutionAndTheToneHasNone() {
        let samples = withHole(holeAt)
        let runs = SignalAnalysis.quietRuns(samples, sampleRate: Self.rate, below: 0.005, atLeast: 0.001)
        #expect(runs.count == 1)
        #expect(abs((runs.first?.start ?? 0) - 2.7292) < 0.001 && abs((runs.first?.length ?? 0) - 0.032) < 0.001)
        #expect(SignalAnalysis.quietRuns(Self.recorded(seconds: 4), sampleRate: Self.rate, below: 0.005, atLeast: 0.001).isEmpty)
    }

    @Test func theToneFollowsTheRenderSampleTimeAcrossASkippedCycle() {
        var clock = PlaybackClock()
        #expect(clock.render(sampleTime: 5_000, frames: 512) == .init(firstIndex: 0, skipped: nil))
        #expect(clock.render(sampleTime: 5_512, frames: 512) == .init(firstIndex: 512, skipped: nil))
        // A cycle of 612 samples never rendered: the tone goes on where the time is.
        #expect(clock.render(sampleTime: 6_636, frames: 512) == .init(firstIndex: 1_636, skipped: 612))
        #expect(clock.render(sampleTime: 7_148, frames: 512) == .init(firstIndex: 2_148, skipped: nil))
    }
}
