import CoreVideo
import Foundation
import Synchronization
import RecorderLogic

/// What a screen file needs of its writer; `ScreenFileWriter` in a
/// recording, a stand-in in tests.
public protocol ScreenFileWriting: AnyObject {
    var firstTick: Int64 { get }
    /// False when the writer is not ready, so the tick waits.
    func append(_ frame: CVPixelBuffer, tick: Int64) throws(ScreenFileWriterError) -> Bool
    /// False when the guide track is not ready, so the samples wait.
    func appendGuide(_ guide: GuideTrack, _ channels: [[Float]], at position: Int64) throws(ScreenFileWriterError) -> Bool
    func finish(lastTick: Int64?) async throws(ScreenFileWriterError)
}

/// How a screen file ended, for the recording manifest: its entry with
/// its end, state and late frames, the writer's error, if any, and the
/// guide tracks that end before its video.
public struct ScreenFileEnd: Equatable, Sendable {
    public var file: RecordingManifest.ScreenFile
    public var error: ScreenFileWriterError?
    public var guideTracksCut: [GuideTrackCut] = []
}

/// A guide track that ends before its screen file's video, and why.
public struct GuideTrackCut: Equatable, Sendable {
    public enum Why: Equatable, Sendable {
        /// The samples of its last mix were no longer there.
        case samplesGone
        /// The writer did not take its last samples within the drain timeout.
        case writerTimedOut
    }

    public var guide: GuideTrack
    public var why: Why

    public init(guide: GuideTrack, why: Why) {
        self.guide = guide
        self.why = why
    }
}

/// A screen file's last mix: the hand-overs that reached it while it
/// ended, then a peek per guide track at the samples the feed has not
/// mixed yet, up to the end of its video.
public struct GuideLastMix: Sendable {
    public struct Chunk: Sendable {
        public var guide: GuideTrack
        public var channels: [[Float]]
        public var positionFromStart: Int64

        public init(guide: GuideTrack, channels: [[Float]], positionFromStart: Int64) {
            self.guide = guide
            self.channels = channels
            self.positionFromStart = positionFromStart
        }
    }

    public struct Peek: Sendable {
        public var start: Int64
        public var channels: [[Float]]

        public init(start: Int64, channels: [[Float]]) {
            self.start = start
            self.channels = channels
        }
    }

    public var pending: [Chunk]
    public var peeks: [GuideTrack: Peek]

    public init(pending: [Chunk], peeks: [GuideTrack: Peek]) {
        self.pending = pending
        self.peeks = peeks
    }
}

/// One screen file's ticks: frames that passed the screen check go in,
/// every tick writes the newest, and at the end the file is finalized. Not
/// thread-safe: the capture's queue uses it, and once the capture ends only
/// `finish` does.
public final class ScreenFileTicker {
    public typealias MakeWriter = (_ firstTick: Int64) throws(ScreenFileWriterError)
        -> (writer: any ScreenFileWriting, entry: RecordingManifest.ScreenFile)

    public enum Outcome: Equatable, Sendable {
        case none
        case fileStarted(RecordingManifest.ScreenFile)
        case ended(ScreenTracker.StreamEnd)
    }

    private let makeWriter: MakeWriter
    private let drainTimeout: Duration
    private var ticks: TickLoop<CVPixelBuffer>
    private var writer: (any ScreenFileWriting)?
    private var entry: RecordingManifest.ScreenFile?
    /// The writer's first error, for the manifest and the person.
    private var writerError: ScreenFileWriterError?
    /// Per guide track, the end of the samples received, from t0.
    private var guidesReceivedUpTo: [GuideTrack: Int64] = [:]
    /// Guide track samples waiting for the writer, by their position in the file.
    private var waitingGuides: [(guide: GuideTrack, position: Int64, channels: [[Float]])] = []
    /// At most this many hand-overs wait per guide track; older ones are dropped.
    private let guideWaitBound = Int(RecorderValues.audioWaitBoundSeconds * 1000 / Int(RecorderValues.guideTrackInterval.nanoseconds / 1_000_000))

    /// How long the end waits for the writer: as long as ticks may wait (D53).
    public static let defaultDrainTimeout = Duration.seconds(RecorderValues.screenFileLateTickSeconds)

    /// `captureStart` in nanoseconds from t0: the file's first tick is never before it.
    public init(
        captureStart: Int64, drainTimeout: Duration = defaultDrainTimeout,
        makeWriter: @escaping MakeWriter
    ) {
        self.makeWriter = makeWriter
        self.drainTimeout = drainTimeout
        ticks = TickLoop(notBefore: captureStart)
    }

    /// A frame that passed the screen check; the first starts the file.
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
    public func tick(now: Int64) -> ScreenTracker.StreamEnd? {
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
    public func receiveGuide(_ guide: GuideTrack, _ channels: [[Float]], positionFromStart: Int64) -> ScreenTracker.StreamEnd? {
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

    private func writeGuides(_ writer: any ScreenFileWriting) -> ScreenTracker.StreamEnd? {
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

    private func failed(_ error: any Error) -> ScreenTracker.StreamEnd {
        let error = error as? ScreenFileWriterError
            ?? ScreenFileWriterError(description: String(describing: error), isDiskFull: false)
        writerError = writerError ?? error
        return error.isDiskFull ? .diskFull : .writerFailed(error.description)
    }

    /// Ends the file: writes the ticks due by `now` and, with
    /// `writeWaitingTicks`, those still waiting, for at most the drain
    /// timeout on a clock that does not count sleep, and the guide tracks
    /// up to the video's end from `lastMix`, given that end (the capture's
    /// `lastMix` first waits up to `audioWaitBoundSeconds` for its sources'
    /// sound up to that end), each joined
    /// into one buffer that waits for the writer as long again; then always
    /// finalizes. A guide track whose last mix has a hole after what the
    /// file received is written up to the hole, never filled with silence,
    /// and one the writer does not take in time is not written further:
    /// both are `guideTracksCut`. A file ended by a failure gets no last
    /// mix. Nil when no file had started.
    public func finish(
        now: Int64, writeWaitingTicks: Bool,
        lastMix: (_ videoEnd: Int64) async -> GuideLastMix = { _ in GuideLastMix(pending: [], peeks: [:]) }
    ) async -> ScreenFileEnd? {
        guard let writer, var file = entry else { return nil }
        var cut: [GuideTrackCut] = []
        if writerError == nil, writeWaitingTicks {
            _ = tick(now: now)
            if writerError == nil { await drain(writer) }
            if writerError == nil, let lastTick = ticks.lastWrittenTick {
                let perTick = Int64(RecorderValues.audioSampleRate) / Int64(ticks.grid.framesPerSecond)
                let videoEnd = (lastTick + 1) * perTick
                let fileStart = writer.firstTick * perTick
                let last = await lastMix(videoEnd)
                for guide in [GuideTrack.audioInputs, .systemAudio] {
                    var parts = last.pending.filter { $0.guide == guide }.map { (start: $0.positionFromStart, channels: $0.channels) }
                    if let peek = last.peeks[guide] { parts.append((peek.start, peek.channels)) }
                    let from = guidesReceivedUpTo[guide] ?? fileStart
                    let joined = Self.joined(parts, from: from, upTo: videoEnd)
                    if joined.hasHole { cut.append(GuideTrackCut(guide: guide, why: .samplesGone)) }
                    guard let count = joined.channels.first?.count, count > 0 else { continue }
                    guidesReceivedUpTo[guide] = from + Int64(count)
                    // One buffer, so the bound on waiting hand-overs drops none of it.
                    waitingGuides.append((guide, from - fileStart, joined.channels))
                }
            }
            if writerError == nil {
                await drainGuides(writer)
                for guide in [GuideTrack.audioInputs, .systemAudio]
                where waitingGuides.contains(where: { $0.guide == guide }) && !cut.contains(where: { $0.guide == guide }) {
                    cut.append(GuideTrackCut(guide: guide, why: .writerTimedOut))
                }
            }
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
        return ScreenFileEnd(file: file, error: writerError, guideTracksCut: cut)
    }

    /// The parts of a last mix, in order, joined from the sample position
    /// `from` up to `end`; a part starting after what is joined so far is a
    /// hole, and joining stops there.
    static func joined(_ parts: [(start: Int64, channels: [[Float]])], from: Int64, upTo end: Int64)
        -> (channels: [[Float]], hasHole: Bool) {
        var joined: [[Float]] = []
        var position = from
        for part in parts where position < end {
            guard part.start <= position else { return (joined, true) }
            guard let count = part.channels.first?.count else { continue }
            let skip = Int(min(Int64(count), position - part.start))
            let take = Int(min(Int64(count - skip), end - position))
            guard take > 0 else { continue }
            if joined.isEmpty { joined = Array(repeating: [], count: part.channels.count) }
            for channel in joined.indices { joined[channel] += part.channels[channel][skip..<(skip + take)] }
            position += Int64(take)
        }
        return (joined, false)
    }

    private func drainGuides(_ writer: any ScreenFileWriting) async {
        let clock = SuspendingClock()
        let deadline = clock.now + drainTimeout
        while writeGuides(writer) == nil, !waitingGuides.isEmpty, writerError == nil, clock.now < deadline {
            try? await clock.sleep(for: .milliseconds(5))
        }
    }

    private func drain(_ writer: any ScreenFileWriting) async {
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
                writerError = ScreenFileWriterError(
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
