import Foundation

/// The end-to-end tests' own reading of the recording's times: the
/// manifest's local timestamps, file name stamps and timecodes, all as
/// seconds of the local day, which is what the recorder writes them from.
public enum TimeOfDay {
    public static let secondsPerDay = 86_400.0

    /// The seconds of the local day of a manifest timestamp
    /// ("2026-11-12T14:03:05.120+01:00"): the time as written, in its own
    /// offset; nil when it is not of that form.
    public static func seconds(ofTimestamp timestamp: String) -> Double? {
        guard let match = timestamp.wholeMatch(
            of: /\d{4}-\d{2}-\d{2}T(\d{2}):(\d{2}):(\d{2})\.(\d{3})[+-]\d{2}:\d{2}/)
        else { return nil }
        let (hours, minutes, seconds, milliseconds) = (Int(match.1)!, Int(match.2)!, Int(match.3)!, Int(match.4)!)
        guard hours < 24, minutes < 60, seconds < 60 else { return nil }
        return Double(hours * 3600 + minutes * 60 + seconds) + Double(milliseconds) / 1000
    }

    /// The seconds of the local day a file name starts with
    /// ("2026-11-12 14.03.05 Screen 1 - …"), and the rest after the space;
    /// nil when it does not start so.
    public static func fileNameStamp(_ name: String) -> (seconds: Double, rest: Substring)? {
        guard let match = name.prefixMatch(of: #/\d{4}-\d{2}-\d{2} (\d{2})\.(\d{2})\.(\d{2}) /#) else { return nil }
        let (hours, minutes, seconds) = (Int(match.1)!, Int(match.2)!, Int(match.3)!)
        guard hours < 24, minutes < 60, seconds < 60 else { return nil }
        return (Double(hours * 3600 + minutes * 60 + seconds), name[match.range.upperBound...])
    }

    /// How far `later` is after `earlier`, both seconds of the day, across
    /// midnight: within half a day either way.
    public static func difference(_ later: Double, _ earlier: Double) -> Double {
        var difference = (later - earlier).truncatingRemainder(dividingBy: secondsPerDay)
        if difference > secondsPerDay / 2 { difference -= secondsPerDay }
        if difference < -secondsPerDay / 2 { difference += secondsPerDay }
        return difference
    }
}

/// A non-drop timecode "HH:MM:SS:FF" at a whole frame rate.
public struct TimecodeValue: Equatable, Sendable, CustomStringConvertible {
    public static let framesPerSecond = 30
    public static let framesPerDay = 86_400 * framesPerSecond

    /// The frame of the day.
    public let frame: Int

    public init(frame: Int) {
        self.frame = ((frame % Self.framesPerDay) + Self.framesPerDay) % Self.framesPerDay
    }

    public init?(_ text: String) {
        guard let match = text.wholeMatch(of: /(\d{2}):(\d{2}):(\d{2}):(\d{2})/) else { return nil }
        let (hours, minutes, seconds, frames) = (Int(match.1)!, Int(match.2)!, Int(match.3)!, Int(match.4)!)
        guard hours < 24, minutes < 60, seconds < 60, frames < Self.framesPerSecond else { return nil }
        self.init(frame: (hours * 3600 + minutes * 60 + seconds) * Self.framesPerSecond + frames)
    }

    /// The timecodes a file may have that starts `start` seconds after a
    /// recording started at `started` (seconds of the day, as the manifest
    /// writes it, to the millisecond): the frame of the day at the start,
    /// rounded to the nearest frame, plus the file's ticks. The recorder
    /// rounds the start before it is cut to the millisecond, so within half
    /// a millisecond of a half frame both neighbouring frames are possible.
    public static func possible(recordingStarted started: Double, fileStart start: Double) -> [TimecodeValue] {
        let fps = Double(framesPerSecond)
        let ticks = Int((start * fps).rounded())
        let frames = started * fps
        let halfMillisecond = 0.0005 * fps
        let candidates = Set([frames - halfMillisecond, frames + halfMillisecond].map { Int($0.rounded()) })
        return candidates.sorted().map { TimecodeValue(frame: $0 + ticks) }
    }

    /// The seconds of the day of the timecode's frame.
    public var seconds: Double { Double(frame) / Double(Self.framesPerSecond) }

    public var description: String {
        let fps = Self.framesPerSecond
        let seconds = frame / fps
        return String(format: "%02d:%02d:%02d:%02d", seconds / 3600, seconds / 60 % 60, seconds % 60, frame % fps)
    }
}
