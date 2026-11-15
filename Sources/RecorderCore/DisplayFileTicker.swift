import CoreVideo
import Foundation
import Synchronization
import RecorderLogic

/// What a display file needs of its writer; `DisplayFileWriter` in a
/// recording, a stand-in in tests.
public protocol DisplayFileWriting: AnyObject {
    var firstTick: Int64 { get }
    /// False when the writer is not ready, so the tick waits.
    func append(_ frame: CVPixelBuffer, tick: Int64) throws(DisplayFileWriterError) -> Bool
    func finish(lastTick: Int64?) async throws(DisplayFileWriterError)
}

/// How a display file ended, for the recording manifest: its entry with
/// its end, state and late frames, and the writer's error, if any.
public struct DisplayFileEnd: Equatable, Sendable {
    public var file: RecordingManifest.DisplayFile
    public var error: DisplayFileWriterError?
}

/// One display file's ticks: frames that passed the display check go in,
/// every tick writes the newest, and at the end the file is finalized. Not
/// thread-safe: the capture's queue uses it, and once the capture ends only
/// `finish` does.
public final class DisplayFileTicker {
    public typealias MakeWriter = (_ firstTick: Int64) throws(DisplayFileWriterError)
        -> (writer: any DisplayFileWriting, entry: RecordingManifest.DisplayFile)

    public enum Outcome: Equatable, Sendable {
        case none
        case fileStarted(RecordingManifest.DisplayFile)
        case ended(DisplayTracker.StreamEnd)
    }

    private let makeWriter: MakeWriter
    private let drainTimeout: Duration
    private var ticks: TickLoop<CVPixelBuffer>
    private var writer: (any DisplayFileWriting)?
    private var entry: RecordingManifest.DisplayFile?
    /// The writer's first error, for the manifest and the person.
    private var writerError: DisplayFileWriterError?

    /// `captureStart` in nanoseconds from t0: the file's first tick is never before it.
    public init(
        captureStart: Int64, drainTimeout: Duration = .seconds(RecorderValues.lateTickBoundSeconds),
        makeWriter: @escaping MakeWriter
    ) {
        self.makeWriter = makeWriter
        self.drainTimeout = drainTimeout
        ticks = TickLoop(notBefore: captureStart)
    }

    /// A frame that passed the display check; the first starts the file.
    public func receive(_ frame: CVPixelBuffer, capturedAt time: Int64) -> Outcome {
        ticks.receive(frame, capturedAt: time)
        guard writer == nil, let firstTick = ticks.firstTick else { return .none }
        do {
            let made = try makeWriter(firstTick)
            writer = made.writer
            entry = made.entry
            return .fileStarted(made.entry)
        } catch {
            writerError = error
            return .ended(error.isDiskFull ? .diskFull : .writerFailed(error.description))
        }
    }

    /// Writes the ticks due by `now`; why the file must end, if it must.
    public func tick(now: Int64) -> DisplayTracker.StreamEnd? {
        guard let writer else { return nil }
        do {
            let outcome = try ticks.advance(to: now) { tick, frame in try writer.append(frame, tick: tick) }
            return outcome == .writerFellBehind ? .writerFellBehind : nil
        } catch {
            return failed(error)
        }
    }

    private func failed(_ error: any Error) -> DisplayTracker.StreamEnd {
        let error = error as? DisplayFileWriterError
            ?? DisplayFileWriterError(description: String(describing: error), isDiskFull: false)
        writerError = writerError ?? error
        return error.isDiskFull ? .diskFull : .writerFailed(error.description)
    }

    /// Ends the file: writes the ticks due by `now` and, with
    /// `writeWaitingTicks`, those still waiting, for at most the drain
    /// timeout on a clock that does not count sleep; then always finalizes.
    /// Nil when no file had started.
    public func finish(now: Int64, writeWaitingTicks: Bool) async -> DisplayFileEnd? {
        guard let writer, var file = entry else { return nil }
        if writerError == nil, writeWaitingTicks {
            _ = tick(now: now)
            if writerError == nil { await drain(writer) }
        }
        do {
            try await writer.finish(lastTick: ticks.lastWrittenTick)
            file.state = .finalized
        } catch {
            writerError = writerError ?? error
            file.state = .notFinalized
        }
        file.end = ticks.grid.seconds(ofTick: (ticks.lastWrittenTick ?? writer.firstTick - 1) + 1)
        file.framesRepeatedForLateness = ticks.framesRepeatedForLateness
        self.writer = nil
        ticks = TickLoop(notBefore: ticks.notBefore)
        return DisplayFileEnd(file: file, error: writerError)
    }

    private func drain(_ writer: any DisplayFileWriting) async {
        let clock = SuspendingClock()
        let deadline = clock.now + drainTimeout
        while true {
            let left: Int
            do {
                left = try ticks.drain { tick, frame in try writer.append(frame, tick: tick) }
            } catch {
                _ = failed(error)
                return
            }
            if left == 0 { return }
            if clock.now >= deadline {
                writerError = DisplayFileWriterError(
                    description: "the writer took none of the last \(left) ticks within \(drainTimeout)", isDiskFull: false)
                return
            }
            try? await clock.sleep(for: .milliseconds(5))
        }
    }
}

/// What the stream lifecycle needs of a stream; `SCStream` in a recording.
public protocol CaptureStream: AnyObject, Sendable {
    func startCapture() async throws
    func stopCapture() async throws
}

/// Starts and stops a capture's stream once, also when the stop comes while
/// the stream is still starting: a stream started after the stop was asked
/// for is stopped as soon as it runs, and one not started yet never starts.
public final class StreamLifecycle: Sendable {
    private struct State {
        var stopRequested = false
        var stream: (any CaptureStream)?
        var isRunning = false
    }

    private let state = Mutex(State())

    public init() {}

    public func start(_ stream: any CaptureStream) async throws {
        let proceed = state.withLock { state -> Bool in
            guard !state.stopRequested else { return false }
            state.stream = stream
            return true
        }
        guard proceed else { return }
        try await stream.startCapture()
        let stopNow = state.withLock { state -> Bool in
            state.isRunning = true
            return state.stopRequested
        }
        if stopNow {
            try? await stream.stopCapture()
            state.withLock { $0.stream = nil }
        }
    }

    /// Stops the stream if it runs and releases it.
    public func stop() async {
        let running = state.withLock { state -> (any CaptureStream)? in
            guard !state.stopRequested else { return nil }
            state.stopRequested = true
            guard state.isRunning else { return nil }
            defer { state.stream = nil }
            return state.stream
        }
        try? await running?.stopCapture()
    }
}
