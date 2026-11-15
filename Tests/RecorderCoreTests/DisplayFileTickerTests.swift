import CoreVideo
import Foundation
import RecorderLogic
import Testing
@testable import RecorderCore

/// A display file's ticks with a stand-in writer: what reaches the
/// recording manifest when a writer fails, falls behind or is slow at the end.
@Suite struct DisplayFileTickerTests {
    final class StandInWriter: DisplayFileWriting, @unchecked Sendable {
        let firstTick: Int64
        var isReady = true
        var appendError: DisplayFileWriterError?
        var finishError: DisplayFileWriterError?
        private(set) var written: [Int64] = []
        private(set) var finishedAt: Int64??

        init(firstTick: Int64) { self.firstTick = firstTick }

        func append(_ frame: CVPixelBuffer, tick: Int64) throws(DisplayFileWriterError) -> Bool {
            if let appendError { throw appendError }
            guard isReady else { return false }
            written.append(tick)
            return true
        }

        func finish(lastTick: Int64?) async throws(DisplayFileWriterError) {
            finishedAt = .some(lastTick)
            if let finishError { throw finishError }
        }
    }

    private let grid = TickGrid.recording
    private let frame: CVPixelBuffer = {
        var buffer: CVPixelBuffer?
        CVPixelBufferCreate(nil, 16, 16, kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange, nil, &buffer)
        return buffer!
    }()

    /// A ticker whose writer is kept for inspection.
    private func ticker(captureStart: Int64 = 0, drainTimeout: Duration = .milliseconds(50))
        -> (DisplayFileTicker, () -> StandInWriter?) {
        nonisolated(unsafe) var made: StandInWriter?
        let ticker = DisplayFileTicker(captureStart: captureStart, drainTimeout: drainTimeout) { firstTick throws(DisplayFileWriterError) in
            let writer = StandInWriter(firstTick: firstTick)
            made = writer
            return (writer, RecordingManifest.DisplayFile(
                name: "f.mov", display: "D", displayUUID: "U", frameSize: FrameSize(width: 16, height: 16),
                start: TickGrid.recording.seconds(ofTick: firstTick), timecode: "00:00:00:00"))
        }
        return (ticker, { made })
    }

    @Test func theFileEndCarriesItsStartEntryAndItsFinalState() async throws {
        let (ticker, writer) = ticker()
        guard case .fileStarted(let entry) = ticker.receive(frame, capturedAt: 0) else { Issue.record("no file"); return }
        #expect(entry.name == "f.mov")
        #expect(ticker.tick(now: grid.time(ofTick: 2)) == nil)
        let end = try #require(await ticker.finish(now: grid.time(ofTick: 2), writeWaitingTicks: true))
        #expect(end.file.name == "f.mov")
        #expect(end.file.state == .finalized)
        #expect(end.file.end == grid.seconds(ofTick: 3))
        #expect(end.error == nil)
        #expect(writer()?.written == [0, 1, 2])
    }

    @Test func aWriterErrorReachesTheFileEnd() async throws {
        let (ticker, writer) = ticker()
        _ = ticker.receive(frame, capturedAt: 0)
        writer()?.appendError = DisplayFileWriterError(description: "cannot write f.mov: no luck", isDiskFull: false)
        #expect(ticker.tick(now: grid.time(ofTick: 1)) == .writerFailed("cannot write f.mov: no luck"))
        writer()?.finishError = DisplayFileWriterError(description: "cannot finalize f.mov: no luck", isDiskFull: false)
        let end = try #require(await ticker.finish(now: grid.time(ofTick: 1), writeWaitingTicks: false))
        #expect(end.file.state == .notFinalized)
        #expect(end.error == "cannot write f.mov: no luck")
    }

    @Test func aFullDiskEndsAsDiskFull() {
        let (ticker, writer) = ticker()
        _ = ticker.receive(frame, capturedAt: 0)
        writer()?.appendError = DisplayFileWriterError(description: "full", isDiskFull: true)
        #expect(ticker.tick(now: grid.time(ofTick: 1)) == .diskFull)
    }

    @Test func aWriterThatFellBehindIsStillFinalized() async throws {
        let (ticker, writer) = ticker()
        _ = ticker.receive(frame, capturedAt: 0)
        writer()?.isReady = false
        let behind = Int64(RecorderValues.lateTickBound) + 1
        #expect(ticker.tick(now: grid.time(ofTick: behind)) == .writerFellBehind)
        let end = try #require(await ticker.finish(now: grid.time(ofTick: behind), writeWaitingTicks: false))
        #expect(writer()?.finishedAt != nil)
        #expect(end.file.state == .finalized)
    }

    @Test func aDrainThatTimesOutStillFinalizesAndSaysSo() async throws {
        let (ticker, writer) = ticker()
        _ = ticker.receive(frame, capturedAt: 0)
        writer()?.isReady = false
        _ = ticker.tick(now: grid.time(ofTick: 3))
        let end = try #require(await ticker.finish(now: grid.time(ofTick: 3), writeWaitingTicks: true))
        #expect(writer()?.finishedAt != nil)
        #expect(end.file.state == .finalized)
        #expect(end.error?.contains("4 ticks") == true)
    }

    @Test func theTicksDueAtTheEndAreWrittenBeforeTheFileIsFinalized() async throws {
        let (ticker, writer) = ticker()
        _ = ticker.receive(frame, capturedAt: 0)
        _ = ticker.tick(now: grid.time(ofTick: 1))
        let end = try #require(await ticker.finish(now: grid.time(ofTick: 4), writeWaitingTicks: true))
        #expect(writer()?.written == [0, 1, 2, 3, 4])
        #expect(end.file.end == grid.seconds(ofTick: 5))
    }

    @Test func aWriterThatCannotBeCreatedEndsTheCapture() {
        let ticker = DisplayFileTicker(captureStart: 0) { _ throws(DisplayFileWriterError) in
            throw DisplayFileWriterError(description: "cannot create f.mov", isDiskFull: false)
        }
        #expect(ticker.receive(frame, capturedAt: 0) == .ended(.writerFailed("cannot create f.mov")))
    }

    @Test func noFileNoEnd() async {
        let (ticker, _) = ticker()
        #expect(await ticker.finish(now: 0, writeWaitingTicks: true) == nil)
    }
}

/// Stopping a stream while it is still starting.
@Suite struct StreamLifecycleTests {
    final class StandInStream: CaptureStream, @unchecked Sendable {
        private let lock = NSLock()
        private var events: [String] = []
        private var release: CheckedContinuation<Void, Never>?
        private var startedWaiting: CheckedContinuation<Void, Never>?
        var log: [String] { lock.withLock { events } }

        func startCapture() async throws {
            lock.withLock { events.append("start begun") }
            await withCheckedContinuation { continuation in
                lock.withLock {
                    release = continuation
                    startedWaiting?.resume()
                    startedWaiting = nil
                }
            }
            lock.withLock { events.append("started") }
        }

        func stopCapture() async throws {
            lock.withLock { events.append("stopped") }
        }

        func waitUntilStarting() async {
            await withCheckedContinuation { continuation in
                lock.withLock {
                    if release != nil { continuation.resume() } else { startedWaiting = continuation }
                }
            }
        }

        func finishStarting() {
            lock.withLock { release }?.resume()
        }
    }

    @Test func aStreamStoppedWhileItStartsIsStoppedOnceStarted() async throws {
        let lifecycle = StreamLifecycle()
        let stream = StandInStream()
        let starting = Task { try await lifecycle.start(stream) }
        await stream.waitUntilStarting()
        await lifecycle.stop()
        stream.finishStarting()
        try await starting.value
        #expect(stream.log == ["start begun", "started", "stopped"])
    }

    @Test func aStreamStartedAfterTheStopNeverStarts() async throws {
        let lifecycle = StreamLifecycle()
        await lifecycle.stop()
        let stream = StandInStream()
        try await lifecycle.start(stream)
        #expect(stream.log.isEmpty)
    }

    @Test func aRunningStreamIsStoppedOnce() async throws {
        let lifecycle = StreamLifecycle()
        let stream = StandInStream()
        let starting = Task { try await lifecycle.start(stream) }
        await stream.waitUntilStarting()
        stream.finishStarting()
        try await starting.value
        await lifecycle.stop()
        await lifecycle.stop()
        #expect(stream.log == ["start begun", "started", "stopped"])
    }
}
