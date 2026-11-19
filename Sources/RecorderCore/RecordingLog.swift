import Foundation
import RecorderLogic
import Synchronization

/// Where the recording log's lines go: a file only ever appended to.
public protocol RecordingLogFile: AnyObject, Sendable {
    func append(_ data: Data) throws
    /// Everything appended so far is on the disk.
    func synchronize() throws
    func close() throws
}

/// `recording.log` in the recording folder (D64), opened to append only:
/// created new, never rewritten.
public final class AppendOnlyFile: RecordingLogFile {
    private let handle: FileHandle

    public init(creating url: URL) throws {
        let descriptor = open(url.path(percentEncoded: false), O_WRONLY | O_CREAT | O_EXCL | O_APPEND | O_CLOEXEC, 0o644)
        guard descriptor >= 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
        handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
    }

    public func append(_ data: Data) throws { try handle.write(contentsOf: data) }
    public func synchronize() throws { try handle.synchronize() }
    public func close() throws { try handle.close() }
}

/// The recording log (D64): every event, every problem with its full error
/// chain, and the detail lines, each line appended. After an event's or a
/// problem's line the file is synchronized to disk, so a crash leaves
/// everything up to the last one; detail lines wait in memory until then,
/// until Stop, or until a check finds they waited
/// `RecorderValues.recordingLogFlushInterval`. Writing that fails drops the
/// lines and is reported once, until writing works again; the recording
/// goes on.
///
/// A detail line, which capture threads add, only takes the short lock of
/// the waiting lines; the writing and synchronizing, which can be slow on
/// an external or network volume, happen under a lock of their own that
/// no capture thread waits on.
public final class RecordingLog: Sendable {
    private struct State {
        var file: (any RecordingLogFile)?
        var waiting: [String] = []
        var lastWrite: Int64 = 0
        var isFailing = false
    }

    private let state: Mutex<State>
    /// Serializes the writes, in the order their lines were taken.
    private let writer = Mutex(())
    private let started: Date
    private let timeZone: TimeZone
    /// Nanoseconds since the recording's start on the shared clock.
    private let now: @Sendable () -> Int64
    /// A failure to write, or nil once writing works again.
    private let writing: @Sendable (ErrorDetail?) -> Void
    private let flushInterval: Int64

    public init(
        file: any RecordingLogFile, started: Date, timeZone: TimeZone, now: @escaping @Sendable () -> Int64,
        flushInterval: Duration = RecorderValues.recordingLogFlushInterval,
        writing: @escaping @Sendable (ErrorDetail?) -> Void
    ) {
        state = Mutex(State(file: file))
        self.started = started
        self.timeZone = timeZone
        self.now = now
        self.flushInterval = flushInterval.nanoseconds
        self.writing = writing
    }

    /// A detail line, from any thread: it waits for the next write.
    public func detail(_ message: String, category: String) {
        let line = DetailLine.recordingLogText(
            message, category: category, seconds: Double(now()) / 1_000_000_000, started: started, timeZone: timeZone)
        state.withLock { $0.waiting.append(line) }
    }

    /// An event's line (`EventLine`), written with the detail lines before it, and synchronized.
    public func event(_ line: String) {
        report(write([line]))
    }

    /// A problem's line, written with the detail lines before it, and synchronized.
    public func problem(_ problem: RecordingProblem) {
        report(write([EventLine.problemText(problem, started: started, timeZone: timeZone)]))
    }

    /// Writes what waits and synchronizes now: the starting situation, before the recording starts.
    public func synchronize() {
        report(write([]))
    }

    /// Writes the detail lines once they have waited the flush interval since the last write.
    public func flushIfDue() {
        let at = now()
        let isDue = state.withLock { !$0.waiting.isEmpty && at - $0.lastWrite >= flushInterval }
        if isDue { report(write([])) }
    }

    /// Stop: writes what waits, synchronizes and closes the file; later
    /// lines go nowhere. The failure, if the log does not end complete on
    /// disk, for the recording manifest; it is not reported otherwise.
    public func close() -> ErrorDetail? {
        writer.withLock { _ in
            var failure = writeTaken([]).failure
            let file = state.withLock { state in
                defer { state.file = nil }
                return state.file
            }
            do {
                try file?.close()
            } catch {
                failure = failure ?? ErrorDetail(error)
            }
            return failure
        }
    }

    private struct Written {
        var failure: ErrorDetail?
        /// Whether writing failed now and worked before, or worked now and failed before.
        var changed: Bool
    }

    private func write(_ lines: [String]) -> Written {
        writer.withLock { _ in writeTaken(lines) }
    }

    /// Under the writer's lock: takes the waiting lines, then appends and
    /// synchronizes outside the lock of the waiting lines.
    private func writeTaken(_ lines: [String]) -> Written {
        let at = now()
        let taken: (file: (any RecordingLogFile)?, lines: [String]) = state.withLock { state in
            defer {
                state.waiting = []
                state.lastWrite = at
            }
            return (state.file, state.waiting + lines)
        }
        guard let file = taken.file else { return Written(failure: nil, changed: false) }
        let text = taken.lines.map { $0 + "\n" }.joined()
        var failure: ErrorDetail?
        do {
            try file.append(Data(text.utf8))
            try file.synchronize()
        } catch {
            failure = ErrorDetail(error)
        }
        let changed = state.withLock { state in
            defer { state.isFailing = failure != nil }
            return state.isFailing != (failure != nil)
        }
        return Written(failure: failure, changed: changed)
    }

    private func report(_ written: Written) {
        if written.changed { writing(written.failure) }
    }
}
