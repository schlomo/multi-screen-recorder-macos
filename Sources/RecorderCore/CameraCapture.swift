import AVFoundation
import CoreMedia
import Foundation
import RecorderLogic

/// Where a camera capture's frames come from: the camera's
/// `AVCaptureSession` (`CameraSource`) in a recording, a stand-in in tests.
protocol CameraFrameSource: AnyObject, Sendable {
    /// Starts delivering frames to `deliver` on `queue`; `ended` when it ends by itself.
    func start(
        queue: DispatchQueue, deliver: @escaping @Sendable (CMSampleBuffer) -> Void,
        ended: @escaping @Sendable (VideoStreamEnd) -> Void)
    func stop() async
}

/// One camera's stream and its camera file (D74): the camera's frames go
/// to the camera file's feed as a screen's do, with no screen check. A
/// camera that delivers no frames is failing (`CameraFrameWatch`). A
/// capture has at most one camera file; a new file needs a new capture.
/// Everything runs on its own queue until the capture ends.
final class CameraCapture: @unchecked Sendable {
    let uniqueID: String
    let number: Int
    let name: String
    let frameSize: FrameSize
    private let context: RecordingContext
    private let queue: DispatchQueue
    private let source: any CameraFrameSource
    private var feed: VideoFileFeed<RecordingManifest.CameraFile>!
    private let frameWatch: CameraFrameWatch
    // Confined to `queue`.
    private var startedAt: Int64 = 0
    /// When the last frame came, on the shared clock; nil before the first.
    private var lastFrameAt: Int64?
    private var watchTimer: DispatchSourceTimer?

    /// The error of a frame without a picture, which the writer cannot take.
    static let frameWithoutPicture: ErrorDetail = "the camera delivered a frame without a decoded picture"

    init(
        uniqueID: String, number: Int, name: String, frameSize: FrameSize, source: any CameraFrameSource,
        context: RecordingContext, guides: GuideTrackFeed, frameWatch: CameraFrameWatch,
        onFileStarted: @escaping @Sendable (RecordingManifest.CameraFile) -> Void,
        onEnded: @escaping @Sendable (VideoStreamEnd, VideoFileEnd<RecordingManifest.CameraFile>?) -> Void
    ) {
        self.uniqueID = uniqueID
        self.number = number
        self.name = name
        self.frameSize = frameSize
        self.source = source
        self.context = context
        self.frameWatch = frameWatch
        queue = DispatchQueue(label: "msr.camera.\(number)", qos: .userInteractive)
        let ticker = VideoFileTicker<RecordingManifest.CameraFile>(captureStart: context.now()) {
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
            })
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
        lastFrameAt = context.now()
        let pts = CMTimeConvertScale(CMSampleBufferGetPresentationTimeStamp(buffer), timescale: 1_000_000_000, method: .roundHalfAwayFromZero)
        feed.receive(pixelBuffer, capturedAt: context.clock.sinceStart(host: UInt64(max(0, pts.value))))
    }

    /// On the queue: a camera that delivers no frames ends the capture.
    private func watchFrames() {
        guard !feed.isEnding else { return stopWatching() }
        guard let failure = frameWatch.failure(startedAt: startedAt, lastFrameAt: lastFrameAt, now: context.now()) else { return }
        stopWatching()
        feed.end(.streamFailed(failure))
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
/// `startRunning` and `stopRunning` block.
final class CameraSource: NSObject, CameraFrameSource, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    let uniqueID: String
    let format: CameraFormat
    let frameSize: FrameSize
    private let sessionQueue: DispatchQueue
    private let lock = NSLock()
    /// Guarded by `lock`.
    private var state = State()

    private struct State {
        var session: AVCaptureSession?
        var deliver: (@Sendable (CMSampleBuffer) -> Void)?
        var ended: (@Sendable (VideoStreamEnd) -> Void)?
        var observers: [any NSObjectProtocol] = []
        var isStopped = false
    }

    init(uniqueID: String, format: CameraFormat, frameSize: FrameSize) {
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
        ended: @escaping @Sendable (VideoStreamEnd) -> Void
    ) {
        withState {
            $0.deliver = deliver
            $0.ended = ended
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
        guard let deviceFormat = device.formats.first(where: { cameraFormat(of: $0) == format }) else {
            throw SourceError(errorDescription: "the camera no longer offers the format \(format)")
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
        // After the input is added, so the session keeps the format; it runs at the format's default rate.
        try device.lockForConfiguration()
        device.activeFormat = deviceFormat
        device.unlockForConfiguration()
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
        let proceed = withState { state -> Bool in
            guard !state.isStopped else { return false }
            state.observers = observers
            state.session = session
            return true
        }
        guard proceed else {
            observers.forEach(center.removeObserver)
            return
        }
        session.startRunning()
        // A stop that came while it started has run already, on this queue after this.
        if withState({ $0.isStopped }) { session.stopRunning() }
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        withState { $0.deliver }?(sampleBuffer)
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
        let (session, observers) = withState { state in
            state.isStopped = true
            state.deliver = nil
            state.ended = nil
            defer {
                state.session = nil
                state.observers = []
            }
            return (state.session, state.observers)
        }
        observers.forEach(NotificationCenter.default.removeObserver)
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
