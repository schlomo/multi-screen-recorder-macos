import Foundation
import RecorderLogic
import Synchronization
import Testing
@testable import RecorderCore

/// A stand-in for `recording.log`: what was appended, and what had
/// reached the disk at each synchronize.
private final class StandInFile: RecordingLogFile {
    private struct State {
        var appended = ""
        var synchronized = ""
        var fails = false
        var closed = false
    }

    private let state = Mutex(State())

    var appended: String { state.withLock { $0.appended } }
    var synchronized: String { state.withLock { $0.synchronized } }
    var closed: Bool { state.withLock { $0.closed } }
    func fail(_ fails: Bool) { state.withLock { $0.fails = fails } }

    func append(_ data: Data) throws {
        try state.withLock { state in
            if state.fails { throw POSIXError(.ENOSPC) }
            state.appended += String(decoding: data, as: UTF8.self)
        }
    }

    func synchronize() throws {
        state.withLock { $0.synchronized = $0.appended }
    }

    func close() throws {
        state.withLock { $0.closed = true }
    }
}

private final class StandInClock: Sendable {
    private let nanoseconds = Atomic<Int64>(0)
    var now: Int64 { nanoseconds.load(ordering: .relaxed) }
    func set(_ value: Int64) { nanoseconds.store(value, ordering: .relaxed) }
}

private final class Reports: Sendable {
    private let reports = Mutex<[ErrorDetail?]>([])
    var all: [ErrorDetail?] { reports.withLock { $0 } }
    func add(_ report: ErrorDetail?) { reports.withLock { $0.append(report) } }
}

/// The recording log (D64): appended, synchronized after each event and
/// problem, its detail lines written at the latest after the flush interval.
@Suite struct RecordingLogTests {
    private let berlin = TimeZone(identifier: "Europe/Berlin")!
    private let start = Date(timeIntervalSince1970: 1_794_777_271)  // 2026-11-15 22:14:31 in Berlin
    private let second: Int64 = 1_000_000_000
    private let file = StandInFile()
    private let clock = StandInClock()
    private let reports = Reports()

    private func log() -> RecordingLog {
        let clock = clock
        let reports = reports
        return RecordingLog(file: file, started: start, timeZone: berlin, now: { clock.now },
                            writing: { reports.add($0) })
    }

    private func at(_ seconds: Int64) { clock.set(seconds * second) }

    @Test func detailLinesWaitAndAnEventWritesThemWithItAndSynchronizes() {
        let log = log()
        at(3)
        log.detail("start Screen 1 DELL", category: "recorder")
        #expect(file.appended == "")
        at(4)
        log.event("22:14:35 +4.0s screen connected: DELL")
        #expect(file.synchronized == "22:14:34 +3.0s debug recorder: start Screen 1 DELL\n22:14:35 +4.0s screen connected: DELL\n")
        log.problem(RecordingProblem(at: 4 * second, problem: "Screen DELL", error: "it broke"))
        #expect(file.synchronized.hasSuffix("22:14:35 +4.0s problem: Screen DELL: it broke\n"))
        #expect(reports.all.isEmpty)
    }

    @Test func eachWriteAppendsAndNeverRewrites() {
        let log = log()
        log.event("one")
        let first = file.appended
        log.event("two")
        #expect(file.appended == first + "two\n")
    }

    @Test func detailLinesAreWrittenOnceTheyWaitedTheFlushInterval() {
        let log = log()
        log.event("first")
        at(1)
        log.detail("waits", category: "recorder")
        at(9)
        log.flushIfDue()
        #expect(!file.appended.contains("waits"))
        at(10)
        log.flushIfDue()
        #expect(file.synchronized.hasSuffix("+1.0s debug recorder: waits\n"))
        let written = file.appended
        at(30)
        log.flushIfDue()
        #expect(file.appended == written)
    }

    @Test func closeWritesWhatWaitsAndClosesAndLaterLinesGoNowhere() {
        let log = log()
        log.detail("ended: result ok", category: "recorder")
        log.close()
        #expect(file.synchronized.hasSuffix("debug recorder: ended: result ok\n"))
        #expect(file.closed)
        let written = file.appended
        log.event("after")
        #expect(file.appended == written)
    }

    @Test func aFailureIsReportedOnceAndAgainOnlyAfterWritingWorkedAgain() throws {
        let log = log()
        file.fail(true)
        log.event("lost")
        log.event("lost too")
        #expect(reports.all.count == 1)
        let failure = try #require(reports.all.first ?? nil)
        #expect(failure.domain == NSPOSIXErrorDomain)
        #expect(failure.code == Int(ENOSPC))
        file.fail(false)
        log.event("back")
        #expect(reports.all.count == 2)
        #expect(reports.all.last == .some(nil))
        #expect(file.appended == "back\n")
    }

    @Test func theFileIsCreatedNewAndOnlyAppendedTo() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "recording-log-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appending(path: RecordingNames.recordingLog)
        let file = try AppendOnlyFile(creating: url)
        try file.append(Data("one\n".utf8))
        try file.synchronize()
        try file.append(Data("two\n".utf8))
        try file.close()
        #expect(try String(contentsOf: url, encoding: .utf8) == "one\ntwo\n")
        #expect(throws: POSIXError.self) { try AppendOnlyFile(creating: url) }
    }
}
