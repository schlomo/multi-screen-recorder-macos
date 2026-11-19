import Foundation
import os
import RecorderLogic
import Synchronization

/// The unified log of the app and `msr` (D46): events and problems at
/// `.notice` or higher, which macOS keeps on disk, names public. Detail
/// goes to the recording log of the running recording (D64); with
/// `--debug` also to the log at `.debug` and to standard error.
/// Read it with `CrashReport.logCommand`.
public enum RecorderLog {
    public static let subsystem = "org.schapiro.multiscreenrecorder"
    private static let debug = Atomic(false)
    /// Seconds since the recording's start, while one runs.
    private static let elapsed = Mutex<(@Sendable () -> Double)?>(nil)
    /// The running recording's recording log.
    private static let recordingLog = Mutex<RecordingLog?>(nil)

    public static func logger(_ category: String) -> Logger { Logger(subsystem: subsystem, category: category) }

    /// `--debug`: detail on standard error from now on.
    public static func enableDebug() { debug.store(true, ordering: .relaxed) }

    public static var isDebug: Bool { debug.load(ordering: .relaxed) }

    /// While a recording runs: detail lines carry the time since its start
    /// and go to its recording log; nil for both to stop.
    static func recording(since elapsed: (@Sendable () -> Double)?, log: RecordingLog?) {
        Self.elapsed.withLock { $0 = elapsed }
        recordingLog.withLock { $0 = log }
    }

    public static func notice(_ message: String, category: String) {
        logger(category).notice("\(message, privacy: .public)")
    }

    public static func error(_ message: String, category: String) {
        logger(category).error("\(message, privacy: .public)")
    }

    /// Detail: to the recording log while a recording runs; with `--debug`
    /// also `.debug` in the unified log and a line on standard error.
    public static func detail(_ message: @autoclosure () -> String, category: String) {
        let log = recordingLog.withLock { $0 }
        guard isDebug || log != nil else { return }
        let message = message()
        log?.detail(message, category: category)
        guard isDebug else { return }
        logger(category).debug("\(message, privacy: .public)")
        let seconds = elapsed.withLock { $0 }?()
        StandardErrorWriter.shared.write(EventLine.debugText(message, category: category, seconds: seconds) + "\n")
    }
}
