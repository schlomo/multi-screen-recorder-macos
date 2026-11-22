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
        ended: @escaping @Sendable (ScreenTracker.StreamEnd) -> Void)
    func stop() async
}

/// One camera's stream and its camera file (D74): the camera's frames go
/// to the camera file's feed as a screen's do, with no screen check. A
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
    /// The first frame was told in a detail line. Confined to `queue`.
    private var firstFrameTold = false

    /// The error of a frame without a picture, which the writer cannot take.
    static let frameWithoutPicture: ErrorDetail = "the camera delivered a frame without a decoded picture"

    init(
        uniqueID: String, number: Int, name: String, frameSize: FrameSize, source: any CameraFrameSource,
        context: RecordingContext, guides: GuideTrackFeed,
        onFileStarted: @escaping @Sendable (RecordingManifest.CameraFile) -> Void,
        onEnded: @escaping @Sendable (ScreenTracker.StreamEnd, CameraFileEnd?) -> Void
    ) {
        self.uniqueID = uniqueID
        self.number = number
        self.name = name
        self.frameSize = frameSize
        self.source = source
        self.context = context
        queue = DispatchQueue(label: "msr.camera.\(number)", qos: .userInteractive)
        let ticker = VideoFileTicker<RecordingManifest.CameraFile>(captureStart: context.now()) {
            [context, uniqueID, number, name, frameSize, guides] firstTick throws(ScreenFileWriterError) in
            let fileName = context.claimCameraFileName(tick: firstTick, number: number, camera: name)
            let writer = try ScreenFileWriter(
                url: context.folder.appending(path: fileName), frameSize: frameSize, firstTick: firstTick,
                timecode: context.timecode,
                metadata: ScreenFileMetadata(
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

    /// Starts the camera's stream; its failure ends the capture as a failing stream.
    func start() {
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
        if !firstFrameTold {
            firstFrameTold = true
            RecorderLog.detail(
                "Camera \(number) \(name): first frame \(CVPixelBufferGetWidth(pixelBuffer))×\(CVPixelBufferGetHeight(pixelBuffer)) "
                    + FrameFacts.fourCharacterCode(CVPixelBufferGetPixelFormatType(pixelBuffer)),
                category: ScreenFileWriter.detailCategory)
        }
        let pts = CMTimeConvertScale(CMSampleBufferGetPresentationTimeStamp(buffer), timescale: 1_000_000_000, method: .roundHalfAwayFromZero)
        feed.receive(pixelBuffer, capturedAt: context.clock.sinceStart(host: UInt64(max(0, pts.value))))
    }

    /// Stops the capture at the recorder's request and finalizes its file;
    /// if the capture is already ending by itself, waits for that.
    func stop() async -> CameraFileEnd? {
        await feed.stop()
    }
}

/// A camera's frames: one `AVCaptureSession` per recorded camera, opened in
/// the chosen format, its frames decoded and scaled to the file's frame
/// size in the pixel format the screens deliver. An unplug ends it with
/// `AVCaptureDevice.wasDisconnectedNotification` or the session's runtime
/// error `deviceWasDisconnected`, as an audio input's (`MicrophoneSource`).
final class CameraSource: NSObject, CameraFrameSource, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    let uniqueID: String
    let format: CameraFormat
    let frameSize: FrameSize
    private let lock = NSLock()
    /// Guarded by `lock`.
    private var state = State()

    private struct State {
        var session: AVCaptureSession?
        var deliver: (@Sendable (CMSampleBuffer) -> Void)?
        var ended: (@Sendable (ScreenTracker.StreamEnd) -> Void)?
        var observers: [any NSObjectProtocol] = []
        var isStopped = false
    }

    init(uniqueID: String, format: CameraFormat, frameSize: FrameSize) {
        self.uniqueID = uniqueID
        self.format = format
        self.frameSize = frameSize
    }

    private func withState<Result>(_ body: (inout State) -> Result) -> Result {
        lock.withLock { body(&state) }
    }

    func start(
        queue: DispatchQueue, deliver: @escaping @Sendable (CMSampleBuffer) -> Void,
        ended: @escaping @Sendable (ScreenTracker.StreamEnd) -> Void
    ) {
        withState {
            $0.deliver = deliver
            $0.ended = ended
        }
        DispatchQueue.global(qos: .userInitiated).async { [self] in
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
        guard let deviceFormat = device.formats.first(where: { Self.cameraFormat(of: $0) == format }) else {
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
            state.observers = observers
            guard !state.isStopped else { return false }
            state.session = session
            return true
        }
        guard proceed else {
            observers.forEach(center.removeObserver)
            return
        }
        session.startRunning()
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        withState { $0.deliver }?(sampleBuffer)
    }

    private func endOnce(_ end: ScreenTracker.StreamEnd) {
        let ended = withState { state -> (@Sendable (ScreenTracker.StreamEnd) -> Void)? in
            defer { state.ended = nil }
            return state.isStopped ? nil : state.ended
        }
        ended?(end)
    }

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
        session?.stopRunning()
    }

    /// A device format as the recording knows it: its size and its highest frame rate.
    static func cameraFormat(of format: AVCaptureDevice.Format) -> CameraFormat {
        let dimensions = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
        return CameraFormat(
            size: FrameSize(width: Int(dimensions.width), height: Int(dimensions.height)),
            maxFramesPerSecond: format.videoSupportedFrameRateRanges.map(\.maxFrameRate).max() ?? 0)
    }
}

// MARK: The cameras

/// The kinds of camera device AVFoundation lists on a Mac.
private let cameraDeviceTypes: [AVCaptureDevice.DeviceType] = [.builtInWideAngleCamera, .continuityCamera, .deskViewCamera, .external]

/// The cameras AVFoundation lists now, with their formats; listing them asks
/// for no permission and opens none. The default camera is
/// `AVCaptureDevice.default(for: .video)`.
public func currentCameras() -> [CameraInfo] {
    let devices = AVCaptureDevice.DiscoverySession(deviceTypes: cameraDeviceTypes, mediaType: .video, position: .unspecified).devices
    let defaultID = AVCaptureDevice.default(for: .video)?.uniqueID
    return devices.map { device in
        var largestRate: [FrameSize: CameraFormat] = [:]
        for format in device.formats.map(CameraSource.cameraFormat) where format.maxFramesPerSecond > (largestRate[format.size]?.maxFramesPerSecond ?? 0) {
            largestRate[format.size] = format
        }
        return CameraInfo(
            uniqueID: device.uniqueID, name: device.localizedName, isDefault: device.uniqueID == defaultID,
            isVirtual: cameraIsVirtual(deviceType: device.deviceType, transportType: device.transportType),
            formats: largestRate.values.sorted { ($0.size.pixelCount, $0.maxFramesPerSecond) < ($1.size.pixelCount, $1.maxFramesPerSecond) })
    }
}

/// Whether a camera is virtual, made by software such as OBS Virtual Camera
/// (a CoreMediaIO extension): a camera is real when AVFoundation lists it
/// as built in, as a Continuity Camera or Desk View, or connected by
/// built-in, USB, FireWire, PCI, Thunderbolt or Continuity Capture, as Core
/// Audio's transport types say it (`AVCaptureDevice.transportType`); every
/// other transport, virtual and unknown ones included, is virtual (D74).
func cameraIsVirtual(deviceType: AVCaptureDevice.DeviceType, transportType: Int32) -> Bool {
    if [.builtInWideAngleCamera, .continuityCamera, .deskViewCamera].contains(deviceType) { return false }
    return switch audioTransport(coreAudioValue: UInt32(bitPattern: transportType)) {
    case .builtIn, .usb, .fireWire, .pci, .thunderbolt, .continuityCapture: false
    case .hdmi, .displayPort, .bluetooth, .bluetoothLE, .virtual, .aggregate, .airPlay, .unknown, .unreadable: true
    }
}

/// The Camera permission as macOS has it, read without asking.
enum CameraPermission: Equatable, Sendable {
    case granted
    case denied
    case notAsked
}

func readCameraPermission() -> CameraPermission {
    switch AVCaptureDevice.authorizationStatus(for: .video) {
    case .authorized: .granted
    case .notDetermined: .notAsked
    case .denied, .restricted: .denied
    @unknown default: .denied
    }
}

/// Asks for the Camera permission if never asked, so macOS shows its
/// prompt, and says whether it is granted.
func askForCameraPermission() async -> Bool {
    switch readCameraPermission() {
    case .granted: true
    case .notAsked: await AVCaptureDevice.requestAccess(for: .video)
    case .denied: false
    }
}
