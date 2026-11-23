import AVFoundation
import CoreMedia
import Foundation
import RecorderLogic

/// Where a camera capture's frames come from: the camera's
/// `AVCaptureSession` (`CameraSource`) in a recording, a stand-in in tests.
protocol CameraFrameSource: AnyObject, Sendable {
    /// Starts delivering frames to `deliver` on `queue`; `ended` when it ends
    /// by itself; `formatTakenOver` when another app changes the camera's format.
    func start(
        queue: DispatchQueue, deliver: @escaping @Sendable (CMSampleBuffer) -> Void,
        ended: @escaping @Sendable (VideoStreamEnd) -> Void, formatTakenOver: @escaping @Sendable () -> Void)
    func stop() async
}

/// One camera's stream and its camera file (D74): the camera's frames go
/// to the camera file's feed as a screen's do, with no screen check. A
/// camera that pauses is stalled, and one that delivers no frames is
/// failing (`CameraFrameWatch`). A capture has at most one camera file; a
/// new file needs a new capture. Everything runs on its own queue until
/// the capture ends.
final class CameraCapture: @unchecked Sendable {
    let uniqueID: String
    let number: Int
    let name: String
    let frameSize: FrameSize
    private let isContinuity: Bool
    private let context: RecordingContext
    private let queue: DispatchQueue
    private let source: any CameraFrameSource
    private var feed: VideoFileFeed<RecordingManifest.CameraFile>!
    private let frameWatch: CameraFrameWatch
    private let onStalled: @Sendable () -> Void
    private let onStallEnded: @Sendable (_ length: Int64) -> Void
    private let onFormatTakenOver: @Sendable () -> Void
    // Confined to `queue`.
    private var startedAt: Int64 = 0
    /// When the last frame came, on the shared clock; nil before the first.
    private var lastFrameAt: Int64?
    private var isStalled = false
    private var watchTimer: DispatchSourceTimer?

    /// The error of a frame without a picture, which the writer cannot take.
    static let frameWithoutPicture: ErrorDetail = "the camera delivered a frame without a decoded picture"

    init(
        uniqueID: String, number: Int, name: String, frameSize: FrameSize, isContinuity: Bool, source: any CameraFrameSource,
        context: RecordingContext, guides: GuideTrackFeed, frameWatch: CameraFrameWatch,
        onFileStarted: @escaping @Sendable (RecordingManifest.CameraFile) -> Void,
        onStalled: @escaping @Sendable () -> Void,
        onStallEnded: @escaping @Sendable (_ length: Int64) -> Void,
        onFormatTakenOver: @escaping @Sendable () -> Void,
        onEnded: @escaping @Sendable (VideoStreamEnd, VideoFileEnd<RecordingManifest.CameraFile>?) -> Void
    ) {
        self.uniqueID = uniqueID
        self.number = number
        self.name = name
        self.frameSize = frameSize
        self.isContinuity = isContinuity
        self.source = source
        self.context = context
        self.frameWatch = frameWatch
        self.onStalled = onStalled
        self.onStallEnded = onStallEnded
        self.onFormatTakenOver = onFormatTakenOver
        queue = DispatchQueue(label: "msr.camera.\(number)", qos: .userInteractive)
        let ticker = VideoFileTicker<RecordingManifest.CameraFile>(
            captureStart: context.now(), decisionDelay: RecorderValues.cameraDecisionDelay
        ) {
            [context, uniqueID, number, name, frameSize, guides] firstTick throws(VideoFileWriterError) in
            let fileName = context.claimCameraFileName(tick: firstTick, number: number, camera: name)
            let writer = try VideoFileWriter(
                url: context.folder.appending(path: fileName), frameSize: frameSize, firstTick: firstTick,
                timecode: context.timecode,
                metadata: VideoFileMetadata(
                    source: .camera(uniqueID: uniqueID, number: number, name: name), frameSize: frameSize,
                    recordingStarted: context.startedText, app: context.app),
                guideTracks: guides.tracks)
            return (writer, RecordingManifest.CameraFile(
                name: fileName, camera: name, cameraUniqueID: uniqueID, frameSize: frameSize,
                start: TickGrid.recording.seconds(ofTick: firstTick), timecode: context.timecode.text(ofTick: firstTick),
                guideTracks: guides.tracks.map(\.name)))
        }
        feed = VideoFileFeed(
            queue: queue, context: context, guides: guides, ticker: ticker,
            stopStream: { [source] in await source.stop() },
            onFileStarted: onFileStarted, onEnded: onEnded)
    }

    /// Starts the camera's stream and watches that it delivers; its failure ends the capture as a failing stream.
    func start() {
        queue.sync {
            startedAt = context.now()
            let timer = DispatchSource.makeTimerSource(queue: queue)
            let interval = DispatchTimeInterval.nanoseconds(Int(frameWatch.checkInterval.nanoseconds))
            timer.schedule(deadline: .now() + interval, repeating: interval)
            timer.setEventHandler { [weak self] in self?.watchFrames() }
            timer.resume()
            watchTimer = timer
        }
        source.start(
            queue: queue,
            deliver: { [weak self] buffer in self?.take(buffer) },
            ended: { [weak self] end in
                guard let self else { return }
                queue.async { self.feed.end(end) }
            },
            formatTakenOver: onFormatTakenOver)
    }

    /// A frame of the camera, on the queue: captured at its presentation
    /// time, which AVFoundation gives on the host clock. A frame without a
    /// decoded picture ends the capture as a failing stream: the writer
    /// takes only pictures, never a camera's compressed stream.
    private func take(_ buffer: CMSampleBuffer) {
        guard !feed.isEnding, buffer.isValid else { return }
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(buffer) else {
            feed.end(.streamFailed(Self.frameWithoutPicture))
            return
        }
        if lastFrameAt == nil {
            RecorderLog.detail(
                "Camera \(number) \(name): first frame \(CVPixelBufferGetWidth(pixelBuffer))×\(CVPixelBufferGetHeight(pixelBuffer)) "
                    + FrameFacts.fourCharacterCode(CVPixelBufferGetPixelFormatType(pixelBuffer)),
                category: VideoFileWriter.detailCategory)
        }
        let now = context.now()
        if isStalled, let lastFrameAt {
            isStalled = false
            onStallEnded(now - lastFrameAt)
        }
        lastFrameAt = now
        let pts = CMTimeConvertScale(CMSampleBufferGetPresentationTimeStamp(buffer), timescale: 1_000_000_000, method: .roundHalfAwayFromZero)
        feed.receive(pixelBuffer, capturedAt: context.clock.sinceStart(host: UInt64(max(0, pts.value))))
    }

    /// On the queue: a camera that pauses is stalled once per pause, its
    /// file going on; one that delivers no frames ends the capture.
    private func watchFrames() {
        guard !feed.isEnding else { return stopWatching() }
        switch frameWatch.verdict(startedAt: startedAt, lastFrameAt: lastFrameAt, now: context.now(), isContinuity: isContinuity) {
        case .delivering: break
        case .stalled:
            guard !isStalled else { return }
            isStalled = true
            onStalled()
        case .failed(let failure):
            stopWatching()
            feed.end(.streamFailed(failure))
        }
    }

    private func stopWatching() {
        watchTimer?.cancel()
        watchTimer = nil
    }

    /// Stops the capture at the recorder's request and finalizes its file;
    /// if the capture is already ending by itself, waits for that.
    func stop() async -> VideoFileEnd<RecordingManifest.CameraFile>? {
        queue.sync { stopWatching() }
        return await feed.stop()
    }
}

/// A camera's frames: one `AVCaptureSession` per recorded camera, opened in
/// the chosen format, its frames decoded and scaled to the file's frame
/// size in the pixel format the screens deliver. An unplug ends it with
/// `AVCaptureDevice.wasDisconnectedNotification` or the session's runtime
/// error `deviceWasDisconnected`, as an audio input's (`MicrophoneSource`).
/// The session is opened, started and stopped on a queue of its own, as
/// `startRunning` and `stopRunning` block. Dropped frames, another app
/// using the camera at the start and a change of its active format are
/// detail lines.
final class CameraSource: NSObject, CameraFrameSource, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    let uniqueID: String
    /// Nil: another app uses the camera, so its format stays as it is.
    let format: CameraFormat?
    let frameSize: FrameSize
    private let sessionQueue: DispatchQueue
    private let lock = NSLock()
    /// Guarded by `lock`.
    private var state = State()

    private struct State {
        var session: AVCaptureSession?
        var deliver: (@Sendable (CMSampleBuffer) -> Void)?
        var ended: (@Sendable (VideoStreamEnd) -> Void)?
        var formatTakenOver: (@Sendable () -> Void)?
        var formatWatch = ForeignFormatWatch()
        var observers: [any NSObjectProtocol] = []
        var formatObservation: NSKeyValueObservation?
        var drops = DroppedFrames()
        var isStopped = false
    }

    init(uniqueID: String, format: CameraFormat?, frameSize: FrameSize) {
        self.uniqueID = uniqueID
        self.format = format
        self.frameSize = frameSize
        sessionQueue = DispatchQueue(label: "msr.camera.session", qos: .userInitiated)
    }

    private func withState<Result>(_ body: (inout State) -> Result) -> Result {
        lock.withLock { body(&state) }
    }

    func start(
        queue: DispatchQueue, deliver: @escaping @Sendable (CMSampleBuffer) -> Void,
        ended: @escaping @Sendable (VideoStreamEnd) -> Void, formatTakenOver: @escaping @Sendable () -> Void
    ) {
        withState {
            $0.deliver = deliver
            $0.ended = ended
            $0.formatTakenOver = formatTakenOver
        }
        sessionQueue.async { [self] in
            do {
                try open(queue: queue)
            } catch {
                endOnce(.streamFailed(ErrorDetail(error)))
            }
        }
    }

    private struct SourceError: LocalizedError {
        let errorDescription: String?
    }

    private func open(queue: DispatchQueue) throws {
        guard let device = AVCaptureDevice(uniqueID: uniqueID) else {
            endOnce(.captureSourceGone)
            return
        }
        var deviceFormat: AVCaptureDevice.Format?
        if let format {
            let matching = device.formats.filter { cameraFormat(of: $0) == format }
            deviceFormat = matching.first(where: { !Self.isMJPEG($0) }) ?? matching.first
            guard let deviceFormat else {
                throw SourceError(errorDescription: "the camera no longer offers the format \(format)")
            }
            if matching.count > 1 {
                RecorderLog.detail(
                    "camera \(uniqueID): \(matching.count) formats are \(format) ("
                        + matching.map { FrameFacts.fourCharacterCode(CMFormatDescriptionGetMediaSubType($0.formatDescription)) }
                            .joined(separator: ", ")
                        + "), opened in \(FrameFacts.fourCharacterCode(CMFormatDescriptionGetMediaSubType(deviceFormat.formatDescription)))",
                    category: VideoFileWriter.detailCategory)
            }
        }
        let input = try AVCaptureDeviceInput(device: device)
        let session = AVCaptureSession()
        let output = AVCaptureVideoDataOutput()
        output.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
            kCVPixelBufferWidthKey as String: frameSize.width,
            kCVPixelBufferHeightKey as String: frameSize.height,
        ]
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(self, queue: queue)
        session.beginConfiguration()
        guard session.canAddInput(input), session.canAddOutput(output) else {
            throw SourceError(errorDescription: "the capture session does not take the camera")
        }
        session.addInput(input)
        session.addOutput(output)
        // After the input is added, so the session keeps the format and the frame rate.
        let wanted = Double(TickGrid.recording.framesPerSecond)
        let frameDuration = deviceFormat.flatMap { Self.frameDuration(closestTo: TickGrid.recording.framesPerSecond, of: $0) }
        if let deviceFormat {
            try device.lockForConfiguration()
            device.activeFormat = deviceFormat
            if let frameDuration {
                device.activeVideoMinFrameDuration = frameDuration
                device.activeVideoMaxFrameDuration = frameDuration
            }
            device.unlockForConfiguration()
        }
        session.commitConfiguration()
        let center = NotificationCenter.default
        let observers = [
            center.addObserver(forName: AVCaptureSession.runtimeErrorNotification, object: session, queue: nil) { [weak self] note in
                let error = note.userInfo?[AVCaptureSessionErrorKey] as? NSError
                let disconnected = error?.domain == AVFoundationErrorDomain && error?.code == AVError.Code.deviceWasDisconnected.rawValue
                self?.endOnce(disconnected ? .captureSourceGone : .streamFailed(
                    error.map(ErrorDetail.init) ?? "the capture session stopped"))
            },
            center.addObserver(forName: AVCaptureDevice.wasDisconnectedNotification, object: device, queue: nil) { [weak self] _ in
                self?.endOnce(.captureSourceGone)
            },
        ]
        let formatObservation = device.observe(\.activeFormat) { [weak self, uniqueID] device, _ in
            let foreign: (@Sendable () -> Void)? = self?.withState { state in
                state.formatWatch.isForeign(cameraFormat(of: device.activeFormat)) ? state.formatTakenOver : nil
            }
            RecorderLog.detail(
                "camera \(uniqueID): active format changed to \(Self.formatText(device))" + (foreign == nil ? "" : ", by another app"),
                category: VideoFileWriter.detailCategory)
            foreign?()
        }
        let proceed = withState { state -> Bool in
            guard !state.isStopped else { return false }
            state.observers = observers
            state.formatObservation = formatObservation
            state.session = session
            return true
        }
        guard proceed else {
            observers.forEach(center.removeObserver)
            formatObservation.invalidate()
            return
        }
        if format == nil {
            RecorderLog.detail("camera \(uniqueID): in use by another app at the start, its format kept", category: VideoFileWriter.detailCategory)
        }
        // A stop that comes from here on stops the session on this queue, after this.
        session.startRunning()
        // From here on a change of the format the recording did not make is another app's.
        withState { $0.formatWatch.opened(in: cameraFormat(of: device.activeFormat)) }
        let rate = frameDuration.map { 1 / $0.seconds }
        RecorderLog.detail(
            "camera \(uniqueID): active format \(Self.formatText(device))"
                + (deviceFormat == nil ? "" : rate.map { abs($0 - wanted) < 0.001 ? "" : ", the format allows no \(Int(wanted)) fps, set to \(String(format: "%.3g", $0)) fps" }
                    ?? ", the format lists no frame rate"),
            category: VideoFileWriter.detailCategory)
    }

    /// A format the camera sends as JPEG pictures, which AVFoundation must decode.
    private static func isMJPEG(_ format: AVCaptureDevice.Format) -> Bool {
        let subtype = CMFormatDescriptionGetMediaSubType(format.formatDescription)
        return subtype == kCMVideoCodecType_JPEG || subtype == kCMVideoCodecType_JPEG_OpenDML
    }

    /// "1920×1080 420v, frame duration 1/30 s to 1/30 s".
    private static func formatText(_ device: AVCaptureDevice) -> String {
        let active = device.activeFormat
        return "\(cameraFormat(of: active).size) " + FrameFacts.fourCharacterCode(CMFormatDescriptionGetMediaSubType(active.formatDescription))
            + ", frame duration \(text(device.activeVideoMinFrameDuration)) to \(text(device.activeVideoMaxFrameDuration))"
    }

    /// The frame duration for `wanted` frames per second where one of the
    /// format's ranges allows it, otherwise the range's bound closest to it,
    /// as the format gives it, so the device takes it.
    private static func frameDuration(closestTo wanted: Int, of format: AVCaptureDevice.Format) -> CMTime? {
        let ranges = format.videoSupportedFrameRateRanges
        return switch CameraFormat.frameDuration(closestTo: wanted, in: ranges.map { $0.minFrameRate...$0.maxFrameRate }) {
        case .shortestOf(let range): ranges[range].minFrameDuration
        case .longestOf(let range): ranges[range].maxFrameDuration
        case .oneOver(let rate): CMTime(value: 1, timescale: CMTimeScale(rate))
        case nil: nil
        }
    }

    /// "1/30 s".
    private static func text(_ time: CMTime) -> String { "\(time.value)/\(time.timescale) s" }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        withState { $0.deliver }?(sampleBuffer)
    }

    func captureOutput(_ output: AVCaptureOutput, didDrop sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        let reason = CMGetAttachment(sampleBuffer, key: kCMSampleBufferAttachmentKey_DroppedFrameReason, attachmentModeOut: nil)
            .map { "\($0)" } ?? "no reason given"
        let now = Int64(clamping: DispatchTime.now().uptimeNanoseconds)
        guard let line = withState({ $0.drops.dropped(reason: reason, at: now) }) else { return }
        RecorderLog.detail("camera \(uniqueID): \(line)", category: VideoFileWriter.detailCategory)
    }

    private func endOnce(_ end: VideoStreamEnd) {
        let ended = withState { state -> (@Sendable (VideoStreamEnd) -> Void)? in
            defer { state.ended = nil }
            return state.isStopped ? nil : state.ended
        }
        ended?(end)
    }

    /// Stops the session on its own queue, never blocking a task's thread.
    func stop() async {
        let (session, observers, drops) = withState { state in
            state.isStopped = true
            state.deliver = nil
            state.ended = nil
            state.formatTakenOver = nil
            state.formatObservation?.invalidate()
            defer {
                state.session = nil
                state.observers = []
                state.formatObservation = nil
            }
            return (state.session, state.observers, state.drops.remaining())
        }
        observers.forEach(NotificationCenter.default.removeObserver)
        if let drops { RecorderLog.detail("camera \(uniqueID): \(drops)", category: VideoFileWriter.detailCategory) }
        // Handed to the session's queue, which alone uses it from here on.
        nonisolated(unsafe) let running = session
        guard running != nil else { return }
        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
            sessionQueue.async {
                running?.stopRunning()
                done.resume()
            }
        }
    }
}
