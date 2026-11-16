import Foundation
import os
import RecorderLogic
import Synchronization

/// The unified log of the app and `msr` (D46): events and problems at
/// `.notice` or higher, which macOS keeps on disk, names public. With
/// `--debug`, detail goes to the log at `.debug` and to standard error.
/// Read it with `CrashReport.logCommand`.
public enum RecorderLog {
    public static let subsystem = "org.schapiro.multiscreenrecorder"
    private static let debug = Atomic(false)
    /// Seconds since the recording's start, while one runs.
    private static let elapsed = Mutex<(@Sendable () -> Double)?>(nil)

    public static func logger(_ category: String) -> Logger { Logger(subsystem: subsystem, category: category) }

    /// `--debug`: detail from now on.
    public static func enableDebug() { debug.store(true, ordering: .relaxed) }

    public static var isDebug: Bool { debug.load(ordering: .relaxed) }

    /// Detail lines carry the time since the start from now on, nil to stop.
    static func timeDetail(since elapsed: (@Sendable () -> Double)?) {
        Self.elapsed.withLock { $0 = elapsed }
    }

    public static func notice(_ message: String, category: String) {
        logger(category).notice("\(message, privacy: .public)")
    }

    public static func error(_ message: String, category: String) {
        logger(category).error("\(message, privacy: .public)")
    }

    /// Detail, only with `--debug`: `.debug` in the log and a line on standard error.
    public static func detail(_ message: @autoclosure () -> String, category: String) {
        guard isDebug else { return }
        let message = message()
        logger(category).debug("\(message, privacy: .public)")
        let seconds = elapsed.withLock { $0 }?()
        FileHandle.standardError.write(Data((EventLine.debugText(message, category: category, seconds: seconds) + "\n").utf8))
    }
}
