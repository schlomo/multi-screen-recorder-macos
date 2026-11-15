import Foundation

/// A recording event as one line, as `msr record` prints it on standard
/// error and the unified log has it: "22:14:40 +9.2s display connected:
/// Wacom One 13T" (D46).
public enum EventLine {
    public static func text(_ event: RecordingEvent, started: Date, timeZone: TimeZone) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let time = calendar.dateComponents([.hour, .minute, .second], from: started + event.at)
        var line = String(format: "%02d:%02d:%02d +%.1fs %@", time.hour ?? 0, time.minute ?? 0, time.second ?? 0,
                          event.at, event.event.rawValue)
        if let display = event.display { line += ": \(display)" }
        if let from = event.from, let to = event.to { line += " \(size(from)) → \(size(to))" }
        if let mirrors = event.mirrors { line += " mirrors \(mirrors)" }
        if let error = event.error { line += " (\(error))" }
        return line
    }

    private static func size(_ size: [Int]) -> String { size.map(String.init).joined(separator: "x") }
}
