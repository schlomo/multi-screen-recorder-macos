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
    /// False when the guide track is not ready, so the samples wait.
    func appendGuide(_ guide: GuideTrack, _ channels: [[Float]], at position: Int64) throws(DisplayFileWriterError) -> Bool
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
    /// Per guide track, the end of the samples received, from t0.
    private var guidesReceivedUpTo: [GuideTrack: Int64] = [:]
    /// Guide track samples waiting for the writer, by their position in the file.
    private var waitingGuides: [(guide: GuideTrack, position: Int64, channels: [[Float]])] = []
    /// At most this many hand-overs wait per guide track; older ones are dropped.
    private let guideWaitBound = Int(RecorderValues.lateTickBoundSeconds * 1000 / Int(RecorderValues.guideTrackInterval.nanoseconds / 1_000_000))

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
            if outcome == .writerFellBehind { return .writerFellBehind }
        } catch {
            return failed(error)
        }
        return writeGuides(writer)
    }

    /// Guide track samples, one array per channel, the first at
    /// `positionFromStart` samples from t0: the part within the file goes
    /// to the writer, the part before its first tick is dropped.
    public func receiveGuide(_ guide: GuideTrack, _ channels: [[Float]], positionFromStart: Int64) -> DisplayTracker.StreamEnd? {
        guard let writer, writerError == nil else { return nil }
        let fileStart = writer.firstTick * Int64(RecorderValues.audioSampleRate) / Int64(ticks.grid.framesPerSecond)
        let before = Int(max(0, fileStart - positionFromStart))
        guard let count = channels.first?.count, count > before else { return nil }
        guidesReceivedUpTo[guide] = max(guidesReceivedUpTo[guide] ?? 0, positionFromStart + Int64(count))
        waitingGuides.append((guide, positionFromStart + Int64(before) - fileStart, channels.map { Array($0[before...]) }))
        if waitingGuides.count(where: { $0.guide == guide }) > guideWaitBound,
           let oldest = waitingGuides.firstIndex(where: { $0.guide == guide }) {
            waitingGuides.remove(at: oldest)
        }
        return writeGuides(writer)
    }

    private func writeGuides(_ writer: any DisplayFileWriting) -> DisplayTracker.StreamEnd? {
        do {
            while let first = waitingGuides.first {
                guard try writer.appendGuide(first.guide, first.channels, at: first.position) else { return nil }
                waitingGuides.removeFirst()
            }
        } catch {
            return failed(error)
        }
        return nil
    }

    private func failed(_ error: any Error) -> DisplayTracker.StreamEnd {
        let error = error as? DisplayFileWriterError
            ?? DisplayFileWriterError(description: String(describing: error), isDiskFull: false)
        writerError = writerError ?? error
        return error.isDiskFull ? .diskFull : .writerFailed(error.description)
    }

    /// Ends the file: writes the ticks due by `now` and, with
    /// `writeWaitingTicks`, those still waiting, for at most the drain
    /// timeout on a clock that does not count sleep, and the guide tracks
    /// from where they were received up to the video's end, as `lastMix`
    /// reads the guide track (nil: not in the recording) now, waiting for
    /// the writer as long again; then always finalizes. A file ended by a
    /// failure gets neither. Nil when no file had started.
    public func finish(
        now: Int64, writeWaitingTicks: Bool,
        lastMix: (_ guide: GuideTrack, _ from: Int64, _ upTo: Int64) -> [[Float]]? = { _, _, _ in nil }
    ) async -> DisplayFileEnd? {
        guard let writer, var file = entry else { return nil }
        if writerError == nil, writeWaitingTicks {
            _ = tick(now: now)
            if writerError == nil { await drain(writer) }
            if writerError == nil, let lastTick = ticks.lastWrittenTick {
                let perTick = Int64(RecorderValues.audioSampleRate) / Int64(ticks.grid.framesPerSecond)
                let videoEnd = (lastTick + 1) * perTick
                for guide in [GuideTrack.microphones, .systemAudio] {
                    let from = guidesReceivedUpTo[guide] ?? writer.firstTick * perTick
                    guard let channels = lastMix(guide, from, videoEnd) else { continue }
                    _ = receiveGuide(guide, channels, positionFromStart: from)
                }
            }
            if writerError == nil { await drainGuides(writer) }
        }
        waitingGuides = []
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

    private func drainGuides(_ writer: any DisplayFileWriting) async {
        let clock = SuspendingClock()
        let deadline = clock.now + drainTimeout
        while writeGuides(writer) == nil, !waitingGuides.isEmpty, writerError == nil, clock.now < deadline {
            try? await clock.sleep(for: .milliseconds(5))
        }
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
