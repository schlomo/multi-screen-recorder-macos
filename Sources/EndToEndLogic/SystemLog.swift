import Foundation

/// The system log a failed scenario saves (D66): what macOS logged
/// about video, media, screen capture and the display while it ran, for
/// a person to read when the recorder's own logs do not say why.
public enum SystemLog {
    /// Subsystems whose name contains one of these, any case.
    static let subsystems = ["videotoolbox", "coremedia", "avfoundation", "screencapturekit", "display"]
    /// Processes that log about the screens and their capture.
    static let processes = ["WindowServer", "replayd"]

    public static let fileName = "system.log"

    /// `log show`'s predicate.
    public static var predicate: String {
        (subsystems.map { "subsystem CONTAINS[c] \"\($0)\"" } + processes.map { "process == \"\($0)\"" }).joined(separator: " OR ")
    }

    /// `log show`'s start, in the local time and to the second, a second early so the start's own lines are in.
    public static func start(_ date: Date, timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.string(from: date.addingTimeInterval(-1))
    }

    /// The arguments of `log` for the lines since `date`.
    public static func arguments(since date: Date, timeZone: TimeZone = .current) -> [String] {
        ["show", "--style", "compact", "--start", start(date, timeZone: timeZone), "--predicate", predicate]
    }
}
