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

    /// The failures of the tracks of the loopback device's audio file
    /// (`played`) and of the tracks that carry it mixed with others
    /// (`mixed`); a failing click spacing names a playback break that
    /// overlaps it.
    public static func failures(played: [Track], mixed: [Track], breaks: [PlaybackBreak] = []) -> [String] {
        var failures: [String] = []
        guard let reference = played.first else { return ["no track carries the test tone"] }
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
            let expectedClicks = Int(Double(track.samples.count) / track.sampleRate) - 1
            if clicks.count < expectedClicks {
                failures.append("\(track.name): \(clicks.count) clicks, expected at least \(expectedClicks), one a second")
            }
            for (earlier, later) in zip(clicks, clicks.dropFirst()) where abs(later - earlier - 1) > EndToEndValues.clickPeriodTolerance {
                var failure = String(format: "%@: clicks at %.4f s and %.4f s are not one second apart", track.name, earlier, later)
                let window = (track.startsAt + earlier - breakMargin)...(track.startsAt + later + breakMargin)
                if let broke = breaks.first(where: { window.contains($0.timeOfDay) }) {
                    let size = broke.samples.map { "\($0) samples" } ?? "an overload"
                    failure += String(format: "; playback on the loopback device broke at %.3f s (%@); the recording shows it",
                                      broke.timeOfDay - track.startsAt, size)
                }
                failures.append(failure)
                break
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
        return failures
    }
}
