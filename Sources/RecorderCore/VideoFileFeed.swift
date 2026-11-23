import CoreVideo
import Foundation
import RecorderLogic

private let feedQueueKey = DispatchSpecificKey<Int>()

/// A capture's video file, on the capture's queue: its frames go to the
/// file's ticker, a timer writes a frame every tick, the guide tracks are
/// handed to it, and its end finalizes the file once, whether the capture
/// ends by itself or the recorder stops it. Its owner, a screen capture or a
/// camera capture (D74), holds the stream and calls in on its queue.
final class VideoFileFeed<File: VideoFileEntry>: @unchecked Sendable {
    private let queue: DispatchQueue
    private let context: RecordingContext
    private let guides: GuideTrackFeed
    private let grid = TickGrid.recording
    /// Stops the owner's stream and lets go of it, when the file ends; it
    /// holds the owner until then, and is let go of after.
    private var stopStream: (@Sendable () async -> Void)?
    /// The file started; reports its manifest entry.
    private let onFileStarted: @Sendable (File) -> Void
    /// The capture ended by itself, after its file was ended.
    private let onEnded: @Sendable (VideoStreamEnd, VideoFileEnd<File>?) -> Void

    // Confined to `queue`.
    private var ticker: VideoFileTicker<File>?
    private var timer: DispatchSourceTimer?
    /// No frame and no tick is taken any more.
    private(set) var isEnding = false
    /// Listens to the guide tracks until the file's last mix.
    private var guideListener: Int?
    /// The guide tracks handed over while ending, for the file's last mix.
    private var endingGuides: [GuideLastMix.Chunk] = []
    /// Finishing the file, by the capture itself or at the recorder's request; set once.
    private var finishTask: Task<VideoFileEnd<File>?, Never>?

    init(
        queue: DispatchQueue, context: RecordingContext, guides: GuideTrackFeed, ticker: VideoFileTicker<File>,
        stopStream: @escaping @Sendable () async -> Void,
        onFileStarted: @escaping @Sendable (File) -> Void,
        onEnded: @escaping @Sendable (VideoStreamEnd, VideoFileEnd<File>?) -> Void
    ) {
        self.queue = queue
        self.context = context
        self.guides = guides
        self.ticker = ticker
        self.stopStream = stopStream
        self.onFileStarted = onFileStarted
        self.onEnded = onEnded
        queue.setSpecific(key: feedQueueKey, value: ObjectIdentifier(self).hashValue)
    }

    /// A frame to write, captured at `capturedAt` on the shared clock; the
    /// first starts the file. On the queue.
    func receive(_ frame: CVPixelBuffer, capturedAt: Int64) {
        guard !isEnding, let ticker else { return }
        switch ticker.receive(frame, capturedAt: capturedAt, arrivedAt: context.now()) {
        case .none: break
        case .fileStarted(let entry):
            onFileStarted(entry)
            startTicking()
            guideListener = guides.listen { [weak self] guide, channels, position in
                guard let self else { return }
                queue.async {
                    guard !self.isEnding else {
                        self.endingGuides.append(GuideLastMix.Chunk(guide: guide, channels: channels, positionFromStart: position))
                        return
                    }
                    guard let reason = self.ticker?.receiveGuide(guide, channels, positionFromStart: position) else { return }
                    self.end(reason)
                }
            }
        case .ended(let reason): end(reason)
        }
    }

    private func startTicking() {
        let timer = DispatchSource.makeTimerSource(flags: .strict, queue: queue)
        let interval = DispatchTimeInterval.nanoseconds(Int(grid.time(ofTick: 1)))
        timer.schedule(deadline: .now(), repeating: interval, leeway: .milliseconds(1))
        timer.setEventHandler { [weak self] in self?.tick() }
        timer.resume()
        self.timer = timer
    }

    private func tick() {
        guard !isEnding, let ticker else { return }
        if let reason = ticker.tick(now: context.now()) { end(reason) }
    }

    /// The running file's frames repeated for lateness and placed late so far; nil without one.
    func lateness() -> (repeated: Int, placedLate: Int)? {
        queue.sync { ticker?.lateness }
    }

    /// Ends the capture by itself, then reports why; unless the recorder stopped it first. On the queue.
    func end(_ reason: VideoStreamEnd) {
        guard !isEnding else { return }
        guard let finishing = beginFinishing(writeWaitingTicks: reason != .writerFellBehind) else { return }
        Task { onEnded(reason, await finishing.value) }
    }

    /// Stops the capture at the recorder's request and finalizes its file;
    /// if the capture is already ending by itself, waits for that.
    func stop() async -> VideoFileEnd<File>? {
        let finishing = beginFinishing(writeWaitingTicks: true) ?? queue.sync { finishTask }
        return await finishing?.value
    }

    /// Starts finishing the file once; nil when that has begun already. The
    /// file ends at the tick at or before now, however long its stream then
    /// takes to stop.
    private func beginFinishing(writeWaitingTicks: Bool) -> Task<VideoFileEnd<File>?, Never>? {
        let begin = { () -> Task<VideoFileEnd<File>?, Never>? in
            guard self.finishTask == nil else { return nil }
            let askedAt = self.context.now()
            self.isEnding = true
            self.timer?.cancel()
            self.timer = nil
            let task = Task { await self.finish(writeWaitingTicks: writeWaitingTicks, endingAt: askedAt) }
            self.finishTask = task
            return task
        }
        return DispatchQueue.getSpecific(key: feedQueueKey) == ObjectIdentifier(self).hashValue ? begin() : queue.sync(execute: begin)
    }

    /// Stops the stream, finalizes the file up to `endingAt`, when finishing
    /// was asked, and lets go of the writer and the frames it held.
    private func finish(writeWaitingTicks: Bool, endingAt: Int64) async -> VideoFileEnd<File>? {
        let stop = queue.sync {
            defer { self.stopStream = nil }
            return self.stopStream
        }
        await stop?()
        let (ticker, listener) = queue.sync { (self.ticker, self.guideListener) }
        // The file listens until its last mix: once the sources have
        // delivered up to the video's end, or the wait ran out, stopping
        // hands it every hand-over before, queued here, and peeks at what
        // comes after.
        let file = await ticker?.finish(now: endingAt, writeWaitingTicks: writeWaitingTicks) { [guides, queue] videoEnd in
            _ = await guides.waitUntilReceived(upTo: videoEnd, bound: .seconds(RecorderValues.audioWaitBoundSeconds))
            let peeks = listener.map { guides.stopListening($0, peekingUpTo: videoEnd) } ?? [:]
            let pending = queue.sync {
                defer { self.endingGuides = [] }
                return self.endingGuides
            }
            return GuideLastMix(pending: pending, peeks: peeks)
        }
        if let listener { _ = guides.stopListening(listener, peekingUpTo: nil) }
        queue.sync {
            self.ticker = nil
            self.guideListener = nil
            self.endingGuides = []
        }
        return await file?.readingItsFile(in: context.folder)
    }
}
