import Foundation

/// The assertions on recorded test tone: in the loopback device's audio
/// file, its level on every track, no silent stretch and a click every
/// second; in the other files that carry it, the same clicks at the same
/// time of day, each file placed by its timecode.
public enum ToneCheck {
    /// One decoded track: its samples and the time of day of its first sample.
    public struct Track: Sendable {
        public var name: String
        public var samples: [Float]
        public var sampleRate: Double
        /// Seconds of the day, from the file's timecode.
        public var startsAt: Double

        public init(name: String, samples: [Float], sampleRate: Double, startsAt: Double) {
            self.name = name
            self.samples = samples
            self.sampleRate = sampleRate
            self.startsAt = startsAt
        }

        /// Each click's time of day.
        public var clicks: [Double] { SignalAnalysis.clicks(samples, sampleRate: sampleRate).map { startsAt + $0 } }
    }

    /// A playback break this close to a failing click spacing is named in
    /// its failure: the player sees the break up to a buffer before or after
    /// the device does.
    static let breakMargin = 0.1

    /// What the check found: its failures, and the failing click spacings it pardoned.
    public struct Result: Equatable, Sendable {
        public var failures: [String] = []
        public var pardoned: [String] = []
    }

    /// The failures of the tracks of the loopback device's audio file
    /// (`played`) and of the tracks that carry it mixed with others
    /// (`mixed`); a failing click spacing names a playback break that
    /// overlaps it.
    public static func failures(played: [Track], mixed: [Track], breaks: [PlaybackBreak] = []) -> [String] {
        check(played: played, mixed: mixed, breaks: breaks).failures
    }

    /// A hole in a track, with the time of day it starts.
    struct Hole {
        var timeOfDay: Double
        var length: Double
        var start: Double
    }

    /// Pardons a failing click spacing (D67): the test's own player ran late, so the loopback device
    /// carried zeros and the recorder recorded exactly that. All of these hold: the recording has a
    /// hole (a quiet run, at sample resolution) between the two clicks that starts within the break
    /// margin of a playback break the player measured, each hole has a break of its own, and the clicks
    /// are a whole number of seconds apart (one or more clicks lost in the hole). Anything else fails.
    static func pardon(spacing earlier: Double, _ later: Double, holes: [Hole], matched: Set<Int>) -> Hole? {
        let spacing = later - earlier
        guard spacing >= 2 - EndToEndValues.clickPeriodTolerance,
              abs(spacing - spacing.rounded()) <= EndToEndValues.clickPeriodTolerance else { return nil }
        let inside = holes.enumerated().filter { $0.element.start >= earlier && $0.element.start <= later }
        guard !inside.isEmpty, inside.allSatisfy({ matched.contains($0.offset) }) else { return nil }
        return inside.first?.element
    }

    public static func check(played: [Track], mixed: [Track], breaks: [PlaybackBreak] = []) -> Result {
        var result = Result()
        var failures: [String] = []
        guard let reference = played.first else { return Result(failures: ["no track carries the test tone"]) }
        let referenceClicks = reference.clicks
        for track in played {
            let clicks = SignalAnalysis.clicks(track.samples, sampleRate: track.sampleRate)
            let level = SignalAnalysis.toneLevel(track.samples, sampleRate: track.sampleRate, clicks: clicks)
            if abs(level - TestTone.levelDecibels) > EndToEndValues.levelTolerance {
                failures.append(String(format: "%@: the tone's level is %.1f dBFS, expected %.1f dBFS", track.name, level,
                                       TestTone.levelDecibels))
            }
            let quiet = SignalAnalysis.quietWindows(track.samples, sampleRate: track.sampleRate,
                                                    threshold: TestTone.levelDecibels - EndToEndValues.quietBelowTone)
            if let first = quiet.first {
                failures.append(String(format: "%@: %d silent stretches of 0.1 s, the first at %.1f s", track.name, quiet.count, first))
            }
            let holes = SignalAnalysis.quietRuns(
                track.samples, sampleRate: track.sampleRate,
                below: Float(TestTone.amplitude * EndToEndValues.holeBelowTonePeak), atLeast: EndToEndValues.holeSeconds
            ).map { Hole(timeOfDay: track.startsAt + $0.start, length: $0.length, start: $0.start) }
            // Each hole is matched to a break of its own, within the break margin.
            var unused = Array(breaks.indices)
            var matched = Set<Int>()
            for (index, hole) in holes.enumerated() {
                if let found = unused.first(where: { abs(breaks[$0].timeOfDay - hole.timeOfDay) <= breakMargin }) {
                    unused.removeAll { $0 == found }
                    matched.insert(index)
                }
            }
            var pardonedGaps: [(earlier: Double, later: Double)] = []
            var failingSpacings: [(Double, Double)] = []
            for (earlier, later) in zip(clicks, clicks.dropFirst()) where abs(later - earlier - 1) > EndToEndValues.clickPeriodTolerance {
                if let hole = pardon(spacing: earlier, later, holes: holes, matched: matched) {
                    pardonedGaps.append((earlier, later))
                    let broke = breaks.first { abs($0.timeOfDay - hole.timeOfDay) <= breakMargin }?.timeOfDay ?? hole.timeOfDay
                    result.pardoned.append(String(
                        format: "%@: pardoned: playback broke at %.3f s, %.1f ms quiet in the recording, clicks %.3f s apart",
                        track.name, broke - track.startsAt, hole.length * 1000, later - earlier))
                } else {
                    failingSpacings.append((earlier, later))
                }
            }
            let lostClicks = pardonedGaps.reduce(0) { $0 + Int(($1.later - $1.earlier).rounded()) - 1 }
            let expectedClicks = Int(Double(track.samples.count) / track.sampleRate) - 1 - lostClicks
            if clicks.count < expectedClicks {
                failures.append("\(track.name): \(clicks.count) clicks, expected at least \(expectedClicks), one a second")
            }
            for (earlier, later) in failingSpacings.prefix(1) {
                var failure = String(format: "%@: clicks at %.4f s and %.4f s are not one second apart", track.name, earlier, later)
                let window = (track.startsAt + earlier - breakMargin)...(track.startsAt + later + breakMargin)
                if let broke = breaks.first(where: { window.contains($0.timeOfDay) }) {
                    let size = broke.samples.map { "\($0) samples" } ?? "an overload"
                    failure += String(format: "; playback on the loopback device broke at %.3f s (%@); the recording shows it",
                                      broke.timeOfDay - track.startsAt, size)
                }
                failures.append(failure)
            }
        }
        for track in played.dropFirst() + mixed {
            let clicks = track.clicks
            let offsets = SignalAnalysis.clickOffsets(referenceClicks, clicks)
            let overlap = referenceClicks.filter { $0 > track.startsAt && $0 < track.startsAt + Double(track.samples.count) / track.sampleRate }
            if offsets.count < overlap.count - 1 || offsets.isEmpty {
                failures.append("\(track.name): \(offsets.count) of the \(overlap.count) clicks found, by its timecode")
            }
            if let worst = offsets.max(by: { abs($0) < abs($1) }), abs(worst) > EndToEndValues.clickTolerance {
                failures.append(String(format: "%@: a click is %.1f ms off %@, by the timecodes", track.name, worst * 1000, reference.name))
            }
        }
        result.failures = failures
        return result
    }
}
