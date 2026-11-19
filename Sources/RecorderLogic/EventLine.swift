import Foundation

/// A recording event as one line, as `msr record` prints it on standard
/// error and the unified log and the recording log have it: "22:14:40
/// +9.2s screen connected: Wacom One 13T" (D46, D64).
public enum EventLine {
    public static func text(_ event: RecordingEvent, started: Date, timeZone: TimeZone) -> String {
        var line = time(event.at, started: started, timeZone: timeZone) + " " + event.event.rawValue
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
    /// +27.9s start Screen 3 - LG".
    public static func debugText(_ message: String, category: String, seconds: Double?) -> String {
        "debug \(category): " + (seconds.map { elapsed($0) + " " } ?? "") + message
    }

    /// A problem as the recording log has it: "22:15:32 +61.3s problem:
    /// Screen LG: screen stream failed: …".
    public static func problemText(_ problem: RecordingProblem, started: Date, timeZone: TimeZone) -> String {
        time(problem.at, started: started, timeZone: timeZone) + " problem: " + problem.text
    }

    /// A detail line as the recording log has it, the `--debug` line after
    /// the local time and the time since the start: "22:14:58 +27.9s debug
    /// recorder: start Screen 3 - LG".
    public static func detailText(
        _ message: String, category: String, seconds: Double, started: Date, timeZone: TimeZone
    ) -> String {
        time(seconds, started: started, timeZone: timeZone) + " debug \(category): " + message
    }

    /// The local time and the time since the start: "22:14:40 +9.2s".
    static func time(_ seconds: Double, started: Date, timeZone: TimeZone) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let time = calendar.dateComponents([.hour, .minute, .second], from: started + seconds)
        return String(format: "%02d:%02d:%02d ", time.hour ?? 0, time.minute ?? 0, time.second ?? 0) + elapsed(seconds)
    }

    /// "+9.2s".
    private static func elapsed(_ seconds: Double) -> String { String(format: "+%.1fs", seconds) }
}
