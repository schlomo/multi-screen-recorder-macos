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
        guard descriptor >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
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
/// until Stop, or at most `RecorderValues.recordingLogFlushInterval`.
/// Writing that fails drops the lines and is reported once, until writing
/// works again; the recording goes on.
public final class RecordingLog: Sendable {
    private struct State {
        var file: (any RecordingLogFile)?
        var waiting: [String] = []
        var lastWrite: Int64 = 0
        var isFailing = false
    }

    private let state: Mutex<State>
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
        let line = EventLine.detailText(
            message, category: category, seconds: Double(now()) / 1_000_000_000, started: started, timeZone: timeZone)
        state.withLock { $0.waiting.append(line) }
    }

    /// An event's line (`EventLine`), written with the detail lines before it, and synchronized.
    public func event(_ line: String) {
        write([line])
    }

    /// A problem's line, written with the detail lines before it, and synchronized.
    public func problem(_ problem: RecordingProblem) {
        write([EventLine.problemText(problem, started: started, timeZone: timeZone)])
    }

    /// Writes the detail lines that have waited for the flush interval.
    public func flushIfDue() {
        let at = now()
        let isDue = state.withLock { !$0.waiting.isEmpty && at - $0.lastWrite >= flushInterval }
        if isDue { write([]) }
    }

    /// Stop: writes what waits, synchronizes and closes the file; later lines go nowhere.
    public func close() {
        write([])
        let file = state.withLock { state in
            defer { state.file = nil }
            return state.file
        }
        try? file?.close()
    }

    private func write(_ lines: [String]) {
        let at = now()
        let (outcome, report): (Result<Void, any Error>?, Bool) = state.withLock { state in
            guard let file = state.file else { return (nil, false) }
            let text = (state.waiting + lines).map { $0 + "\n" }.joined()
            state.waiting = []
            state.lastWrite = at
            let outcome = Result { try file.append(Data(text.utf8)); try file.synchronize() }
            let isFailing = if case .failure = outcome { true } else { false }
            defer { state.isFailing = isFailing }
            return (outcome, isFailing != state.isFailing)
        }
        guard report, let outcome else { return }
        switch outcome {
        case .success: writing(nil)
        case .failure(let error): writing(ErrorDetail(error))
        }
    }
}
