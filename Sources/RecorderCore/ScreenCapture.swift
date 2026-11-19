import AVFoundation
import CoreMedia
import Foundation
import RecorderLogic
@preconcurrency import ScreenCaptureKit
import Synchronization

/// What every screen capture of a recording shares: the recording folder,
/// the clock, the timecode, and the screens' bounds as last read, which
/// the recorder updates whenever the screens change.
public final class RecordingContext: Sendable {
    public let folder: URL
    public let started: Date
    public let timeZone: TimeZone
    public let timecode: Timecode
    /// The app and its version, and the start as the recording manifest has them.
    public let app: String
    public let startedText: String
    private let state: Mutex<State>

    private struct State {
        var clock: SharedClock
        var bounds: [String: ScreenRect] = [:]
        var lastScreenChange: Int64?
        var takenNames: Set<String> = []
    }

    init(folder: URL, started: Date, timeZone: TimeZone, clock: SharedClock, app: String) {
        self.folder = folder
        self.started = started
        self.timeZone = timeZone
        self.app = app
        startedText = RecordingManifest.timestamp(started, timeZone: timeZone)
        timecode = Timecode(start: started, timeZone: timeZone)
        state = Mutex(State(clock: clock))
    }

    public var clock: SharedClock { state.withLock { $0.clock } }

    func rereadClocks() {
        state.withLock { $0.clock.reread(readClocks()) }
    }

    /// Nanoseconds from t0 now.
    func now() -> Int64 {
        clock.sinceStart(continuous: continuousNow())
    }

    func update(_ screens: [ConnectedScreen], lastScreenChange: Int64?) {
        state.withLock {
            for screen in screens { $0.bounds[screen.uuid] = screen.bounds }
            $0.lastScreenChange = lastScreenChange
        }
    }

    func bounds(of uuid: String) -> (ScreenRect?, Int64?) {
        state.withLock { ($0.bounds[uuid], $0.lastScreenChange) }
    }

    /// The screen file's name for a file starting at `tick`, never one already used.
    func claimFileName(tick: Int64, number: Int, screen: String) -> String {
        claimName(tick: tick) { start, taken in
            RecordingNames.screenFile(start: start, timeZone: timeZone, number: number, screen: screen, taken: taken)
        }
    }

    /// The audio file's name for a file starting at `tick`, never one already used.
    func claimAudioFileName(tick: Int64, source: AudioFileDescription.Source) -> String {
        claimName(tick: tick) { start, taken in
            RecordingNames.audioFile(start: start, timeZone: timeZone, source: source, taken: taken)
        }
    }

    private func claimName(tick: Int64, _ name: (Date, Set<String>) -> String) -> String {
        let start = started.addingTimeInterval(TickGrid.recording.seconds(ofTick: tick))
        return state.withLock { state in
            let existing = Set((try? FileManager.default.contentsOfDirectory(atPath: folder.path(percentEncoded: false))) ?? [])
            let claimed = name(start, state.takenNames.union(existing))
            state.takenNames.insert(claimed)
            return claimed
        }
    }
}

extension SCStream: CaptureStream {}

/// One screen's stream and its screen file: frames pass the screen
/// check and go to the screen file's ticker. A capture has at most one
/// screen file; a new file needs a new capture. Everything runs on its own
/// queue until the capture ends.
public final class ScreenCapture: NSObject, @unchecked Sendable, SCStreamOutput, SCStreamDelegate {
    public let uuid: String
    public let number: Int
    public let name: String
    public let frameSize: FrameSize
    private let displayID: CGDirectDisplayID
    private let context: RecordingContext
    private let queue: DispatchQueue
    private let grid = TickGrid.recording
    private let lifecycle = StreamLifecycle()
    private let guides: GuideTrackFeed

    /// The file started; reports its manifest entry.
    private let onFileStarted: @Sendable (RecordingManifest.ScreenFile) -> Void
    /// The capture ended by itself, after its file was ended.
    private let onEnded: @Sendable (ScreenTracker.StreamEnd, ScreenFileEnd?) -> Void

    // Confined to `queue`.
    private var stream: SCStream?
    private var check = ScreenCheck()
    /// The last frame's facts, for the detail line of a change.
    private var frameFacts: FrameFacts?
    private var ticker: ScreenFileTicker?
    private var timer: DispatchSourceTimer?
    /// No frame and no tick is taken any more.
    private var isEnding = false
    /// Listens to the guide tracks until the file's last mix.
    private var guideListener: Int?
    /// The guide tracks handed over while ending, for the file's last mix.
    private var endingGuides: [GuideLastMix.Chunk] = []
    /// Finishing the file, by the capture itself or at the recorder's request; set once.
    private var finishTask: Task<ScreenFileEnd?, Never>?
    private static let queueKey = DispatchSpecificKey<Int>()

    init(
        uuid: String, displayID: UInt32, number: Int, name: String, frameSize: FrameSize, context: RecordingContext,
        guides: GuideTrackFeed,
        onFileStarted: @escaping @Sendable (RecordingManifest.ScreenFile) -> Void,
        onEnded: @escaping @Sendable (ScreenTracker.StreamEnd, ScreenFileEnd?) -> Void
    ) {
        self.uuid = uuid
        self.displayID = displayID
        self.number = number
        self.name = name
        self.frameSize = frameSize
        self.context = context
        self.guides = guides
        self.onFileStarted = onFileStarted
        self.onEnded = onEnded
        queue = DispatchQueue(label: "msr.screen.\(number)", qos: .userInteractive)
        super.init()
        queue.setSpecific(key: Self.queueKey, value: ObjectIdentifier(self).hashValue)
        let started = context.now()
        ticker = ScreenFileTicker(captureStart: started) { [context, uuid, number, name, frameSize, guides] firstTick throws(ScreenFileWriterError) in
            let fileName = context.claimFileName(tick: firstTick, number: number, screen: name)
            let writer = try ScreenFileWriter(
                url: context.folder.appending(path: fileName), frameSize: frameSize, firstTick: firstTick,
                timecode: context.timecode,
                metadata: ScreenFileMetadata(
                    screenUUID: uuid, screenNumber: number, screenName: name, frameSize: frameSize,
                    recordingStarted: context.startedText, app: context.app),
                guideTracks: guides.tracks)
            return (writer, RecordingManifest.ScreenFile(
                name: fileName, screen: name, screenUUID: uuid, frameSize: frameSize,
                start: TickGrid.recording.seconds(ofTick: firstTick), timecode: context.timecode.text(ofTick: firstTick),
                guideTracks: guides.tracks.map(\.name)))
        }
    }

    /// Starts the stream; its failure ends the capture as a failing stream.
    func start() {
        Task {
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
                guard let screen = content.displays.first(where: { $0.displayID == displayID }) else {
                    throw CaptureError("ScreenCaptureKit does not list the screen")
                }
                let configuration = SCStreamConfiguration()
                configuration.width = frameSize.width
                configuration.height = frameSize.height
                configuration.pixelFormat = kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
                configuration.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(grid.framesPerSecond))
                configuration.queueDepth = 8
                // The mouse pointer is recorded.
                configuration.showsCursor = true
                configuration.scalesToFit = true
                let stream = SCStream(filter: SCContentFilter(display: screen, excludingWindows: []),
                                      configuration: configuration, delegate: self)
                let stillWanted = queue.sync { () -> Bool in
                    guard !isEnding else { return false }
                    self.stream = stream
                    return true
                }
                guard stillWanted else { return }
                try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)
                try await lifecycle.start(stream)
            } catch {
                queue.async { self.end(Self.streamEnd(for: error)) }
            }
        }
    }

    /// A stream's error as the end of its capture: ScreenCaptureKit's
    /// `noCaptureSource` (-3815), the screen gone, is no failure (F4).
    static func streamEnd(for error: any Error) -> ScreenTracker.StreamEnd {
        let nsError = error as NSError
        if nsError.domain == SCStreamErrorDomain, nsError.code == SCStreamError.Code.noCaptureSource.rawValue {
            return .captureSourceGone
        }
        return .streamFailed(ErrorDetail(error))
    }

    private struct CaptureError: Error, LocalizedError {
        let errorDescription: String?
        init(_ text: String) { errorDescription = text }
    }

    // MARK: Frames

    public func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, !isEnding, let ticker, sampleBuffer.isValid,
              let attachments = (CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false)
                as? [[SCStreamFrameInfo: Any]])?.first,
              let statusValue = attachments[.status] as? Int, SCFrameStatus(rawValue: statusValue) == .complete,
              let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer),
              let rectDictionary = attachments[.screenRect] as CFTypeRef?,
              CFGetTypeID(rectDictionary) == CFDictionaryGetTypeID(),
              let screenRect = CGRect(dictionaryRepresentation: rectDictionary as! CFDictionary),
              // When the frame was shown, in mach absolute time: the host clock.
              let displayTime = (attachments[.displayTime] as? NSNumber)?.uint64Value
        else { return }
        let capturedAt = context.clock.sinceStart(host: nanoseconds(machTicks: displayTime))
        let (bounds, lastChange) = context.bounds(of: uuid)
        let verdict = bounds.map {
            check.judge(frameRect: ScreenRect(screenRect), screenBounds: $0, capturedAt: capturedAt, lastScreenChange: lastChange)
        }
        // Told for every complete frame, before the verdict acts: a frame the check drops is no less a fact.
        tellFrameFacts(FrameFacts(pixelBuffer, info: attachments, screenCheck: verdict.map(Self.text) ?? "no screen bounds yet"))
        guard let verdict else { return }
        switch verdict {
        case .passes:
            switch ticker.receive(pixelBuffer, capturedAt: capturedAt) {
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
        case .fails:
            break
        case .showsAnotherScreen:
            end(.showsAnotherScreen)
        }
    }

    private static func text(_ verdict: ScreenCheck.Verdict) -> String {
        switch verdict {
        case .passes: "passes"
        case .fails: "fails"
        case .showsAnotherScreen: "shows another screen"
        }
    }

    /// The first frame's facts, then each change of them: one detail line each (D66).
    private func tellFrameFacts(_ facts: FrameFacts) {
        defer { frameFacts = facts }
        let label = "Screen \(number) \(name)"
        guard let before = frameFacts else {
            RecorderLog.detail("\(label): first frame \(facts.text)", category: ScreenFileWriter.detailCategory)
            return
        }
        guard let changes = facts.changes(from: before) else { return }
        RecorderLog.detail("\(label): frame changed: \(changes)", category: ScreenFileWriter.detailCategory)
    }

    public func stream(_ stream: SCStream, didStopWithError error: any Error) {
        queue.async { self.end(Self.streamEnd(for: error)) }
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

    // MARK: Ending

    /// Ends the capture by itself, then reports why; unless the recorder stopped it first.
    private func end(_ reason: ScreenTracker.StreamEnd) {
        guard !isEnding else { return }
        guard let finishing = beginFinishing(writeWaitingTicks: reason != .writerFellBehind) else { return }
        Task { onEnded(reason, await finishing.value) }
    }

    /// Stops the capture at the recorder's request and finalizes its file;
    /// if the capture is already ending by itself, waits for that.
    func stop() async -> ScreenFileEnd? {
        let finishing = beginFinishing(writeWaitingTicks: true) ?? queue.sync { finishTask }
        return await finishing?.value
    }

    /// Starts finishing the file once; nil when that has begun already.
    private func beginFinishing(writeWaitingTicks: Bool) -> Task<ScreenFileEnd?, Never>? {
        let begin = { () -> Task<ScreenFileEnd?, Never>? in
            guard self.finishTask == nil else { return nil }
            self.isEnding = true
            self.timer?.cancel()
            self.timer = nil
            let task = Task { await self.finish(writeWaitingTicks: writeWaitingTicks) }
            self.finishTask = task
            return task
        }
        return DispatchQueue.getSpecific(key: Self.queueKey) == ObjectIdentifier(self).hashValue ? begin() : queue.sync(execute: begin)
    }

    /// Stops the stream, finalizes the file and lets go of the stream, the
    /// writer and the frames it held.
    private func finish(writeWaitingTicks: Bool) async -> ScreenFileEnd? {
        await lifecycle.stop()
        let (stream, ticker, listener) = queue.sync { (self.stream, self.ticker, self.guideListener) }
        if let stream { try? stream.removeStreamOutput(self, type: .screen) }
        // The file listens until its last mix: once the sources have
        // delivered up to the video's end, or the wait ran out, stopping
        // hands it every hand-over before, queued here, and peeks at what
        // comes after.
        let file = await ticker?.finish(now: context.now(), writeWaitingTicks: writeWaitingTicks) { [guides, queue] videoEnd in
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
            self.stream = nil
            self.ticker = nil
            self.guideListener = nil
            self.endingGuides = []
        }
        return await file?.readingItsFile(in: context.folder)
    }
}
