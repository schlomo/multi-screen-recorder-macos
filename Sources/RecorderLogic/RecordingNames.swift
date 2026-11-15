import Foundation

/// The names in a recording folder (D20, D31): the folder is named by the
/// recording's local start time, each file by its own.
public enum RecordingNames {
    /// "2026-11-12 14.03.05".
    public static func timeStamp(_ date: Date, timeZone: TimeZone) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        func two(_ value: Int?) -> String { String(format: "%02d", value ?? 0) }
        return "\(String(format: "%04d", parts.year ?? 0))-\(two(parts.month))-\(two(parts.day))"
            + " \(two(parts.hour)).\(two(parts.minute)).\(two(parts.second))"
    }

    public static func recordingFolder(start: Date, timeZone: TimeZone) -> String {
        timeStamp(start, timeZone: timeZone)
    }

    /// "2026-11-12 14.03.05 Display 1 - Built-in Retina Display.mov"; when that
    /// name is taken in the recording folder (a new file within the same
    /// second), " (2)", " (3)" and so on before the extension.
    public static func displayFile(
        start: Date, timeZone: TimeZone, number: Int, display: String, taken: Set<String> = []
    ) -> String {
        let base = "\(timeStamp(start, timeZone: timeZone)) Display \(number) - \(display)"
        var name = "\(base).mov"
        var copy = 2
        while taken.contains(name) {
            name = "\(base) (\(copy)).mov"
            copy += 1
        }
        return name
    }

    public static let manifest = "recording.json"
}
