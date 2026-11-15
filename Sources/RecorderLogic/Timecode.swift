import Foundation

/// The timecode track's values: local time of day as frames at the tick
/// grid's rate, non-drop (D21, D31). Every file shares t0 and the tick grid,
/// so tick k has the same timecode in every file.
public struct Timecode: Equatable, Sendable {
    public let framesPerSecond: Int
    /// The frame of the day at t0, rounded to the nearest frame.
    public let frameAtStart: Int64

    public init(start: Date, timeZone: TimeZone, framesPerSecond: Int = RecorderValues.framesPerSecond) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        // The clock time, also on a day with a daylight saving change.
        let parts = calendar.dateComponents([.hour, .minute, .second, .nanosecond], from: start)
        let secondsOfDay = Double((parts.hour ?? 0) * 3600 + (parts.minute ?? 0) * 60 + (parts.second ?? 0))
            + Double(parts.nanosecond ?? 0) / 1_000_000_000
        self.framesPerSecond = framesPerSecond
        frameAtStart = Int64((secondsOfDay * Double(framesPerSecond)).rounded()) % Self.framesPerDay(framesPerSecond)
    }

    private static func framesPerDay(_ framesPerSecond: Int) -> Int64 { 24 * 60 * 60 * Int64(framesPerSecond) }

    /// The frame of the day of tick k, after midnight starting over at 0.
    public func frame(ofTick tick: Int64) -> Int64 {
        (frameAtStart + tick) % Self.framesPerDay(framesPerSecond)
    }

    /// "14:03:05:04": hours, minutes, seconds and frames.
    public func text(ofTick tick: Int64) -> String {
        let frame = frame(ofTick: tick)
        let rate = Int64(framesPerSecond)
        let seconds = frame / rate
        func two(_ value: Int64) -> String { value < 10 ? "0\(value)" : "\(value)" }
        let frameDigits = String(rate - 1).count
        let frames = String(frame % rate)
        return "\(two(seconds / 3600)):\(two(seconds / 60 % 60)):\(two(seconds % 60)):"
            + String(repeating: "0", count: max(2, frameDigits) - frames.count) + frames
    }
}
