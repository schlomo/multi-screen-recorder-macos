import Foundation

/// A recording event as one line, as `msr record` prints it on standard
/// error and the unified log has it: "22:14:40 +9.2s display connected:
/// Wacom One 13T" (D46).
public enum EventLine {
    public static func text(_ event: RecordingEvent, started: Date, timeZone: TimeZone) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let time = calendar.dateComponents([.hour, .minute, .second], from: started + event.at)
        var line = String(format: "%02d:%02d:%02d ", time.hour ?? 0, time.minute ?? 0, time.second ?? 0)
            + elapsed(event.at) + " " + event.event.rawValue
        if let subject = event.subject { line += ": \(subject)" }
        if event.from != nil || event.to != nil {
            line += " \(event.from?.text ?? "none") → \(event.to?.text ?? "none")"
        }
        if let length = event.length { line += String(format: " %.3fs", length) }
        if let mirrors = event.mirrors { line += " mirrors \(mirrors)" }
        if let error = event.error { line += " (\(error))" }
        return line
    }

    /// A `--debug` line on standard error, with the time since the start
    /// as an event line has it while a recording runs: "debug recorder:
    /// +27.9s start Display 3 - LG".
    public static func debugText(_ message: String, category: String, seconds: Double?) -> String {
        "debug \(category): " + (seconds.map { elapsed($0) + " " } ?? "") + message
    }

    /// "+9.2s".
    private static func elapsed(_ seconds: Double) -> String { String(format: "+%.1fs", seconds) }
}
