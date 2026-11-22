import AVFoundation
import CoreGraphics
import Foundation
import RecorderLogic
import ScreenCaptureKit

/// The probes of the ready check, so a test can stand in for this Mac.
/// Everything that touches a file runs off the main thread; reading the
/// screens needs the main one.
public struct ReadyCheckProbes: Sendable {
    public var screenRecording: @Sendable (ScreenRecordingProof) async -> PermissionProbe
    public var microphonePermission: @Sendable () async -> Bool
    public var screens: @MainActor @Sendable () -> Result<[ScreenInfo], DeviceReadError>
    public var audioInputs: @Sendable () -> Result<[AudioInputInfo], DeviceReadError>
    public var outputFolder: @Sendable (URL) -> OutputFolderProbe
    public var cameras: @Sendable () -> [CameraInfo]
    public var cameraPermission: @Sendable () async -> Bool

    public init(
        screenRecording: @escaping @Sendable (ScreenRecordingProof) async -> PermissionProbe,
        microphonePermission: @escaping @Sendable () async -> Bool,
        screens: @escaping @MainActor @Sendable () -> Result<[ScreenInfo], DeviceReadError>,
        audioInputs: @escaping @Sendable () -> Result<[AudioInputInfo], DeviceReadError>,
        outputFolder: @escaping @Sendable (URL) -> OutputFolderProbe,
        cameras: @escaping @Sendable () -> [CameraInfo],
        cameraPermission: @escaping @Sendable () async -> Bool
    ) {
        self.screenRecording = screenRecording
        self.microphonePermission = microphonePermission
        self.screens = screens
        self.audioInputs = audioInputs
        self.outputFolder = outputFolder
        self.cameras = cameras
        self.cameraPermission = cameraPermission
    }

    /// This Mac. A permission that was never asked for is requested, so macOS
    /// shows its prompt; a missing output folder is created.
    public static let system = ReadyCheckProbes(
        screenRecording: probeScreenRecording,
        microphonePermission: probeMicrophonePermission,
        screens: { Result { () throws(DeviceReadError) in try currentScreens() } },
        audioInputs: { Result { () throws(DeviceReadError) in try currentAudioInputs() } },
        outputFolder: probeOutputFolder,
        cameras: currentCameras,
        cameraPermission: askForCameraPermission)
}

/// Runs the ready check's probes. The microphone permission is asked only
/// when the recording records an audio input, the Screen & System Audio
/// Recording permission only when it records a screen or the system audio,
/// the Camera permission only when it records a connected camera (D74).
@concurrent
public func probeReadyCheckFacts(
    proof: ScreenRecordingProof, settings: Settings, homeFolder: URL, probes: ReadyCheckProbes = .system
) async -> ReadyCheckFacts {
    let screenRecording = ReadyCheck.needsScreenRecording(settings) ? await probes.screenRecording(proof) : nil
    let audioInputs = probes.audioInputs()
    let microphoneGranted = ReadyCheck.recordsAudioInput(audioInputs, settings: settings)
        ? await probes.microphonePermission() : nil
    let cameras = probes.cameras()
    let cameraGranted = ReadyCheck.recordsCamera(cameras, settings: settings) ? await probes.cameraPermission() : nil
    let screens = await probes.screens()
    let facts = ReadyCheckFacts(
        screenRecording: screenRecording,
        microphoneGranted: microphoneGranted,
        screens: screens,
        audioInputs: audioInputs,
        outputFolder: probes.outputFolder(settings.outputFolderURL(homeFolder: homeFolder)),
        cameraGranted: cameraGranted,
        cameras: cameras)
    RecorderLog.detail(DetailLine.facts(facts), category: "ready check")
    return facts
}

/// Whether the Screen & System Audio Recording permission is granted, without
/// asking for it.
public func screenRecordingIsGranted() -> Bool {
    CGPreflightScreenCaptureAccess()
}

/// How the ready check proves the screen recording permission (D46).
public enum ScreenRecordingProof: Sendable, Equatable {
    /// Captures one small frame of one screen, so macOS shows every prompt
    /// of a capture now and not at Start: at the app's start, "Check
    /// again", `msr check` and `msr record`'s own check.
    case captureOneFrame
    /// Fetches the screen list: the checks after a change, which show no prompt again.
    case listScreens
}

/// Asks for the permission if needed, then proves the grant through
/// ScreenCaptureKit as `proof` says.
public func probeScreenRecording(_ proof: ScreenRecordingProof) async -> PermissionProbe {
    if !CGPreflightScreenCaptureAccess() {
        _ = CGRequestScreenCaptureAccess()
    }
    do {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        if proof == .captureOneFrame {
            guard let screen = content.displays.first else { return .failed("ScreenCaptureKit lists no screen") }
            let configuration = SCStreamConfiguration()
            configuration.width = 64
            configuration.height = 36
            configuration.showsCursor = false
            _ = try await SCScreenshotManager.captureSampleBuffer(
                contentFilter: SCContentFilter(display: screen, excludingWindows: []), configuration: configuration)
        }
        return .granted
    } catch {
        return CGPreflightScreenCaptureAccess() ? .failed(ErrorDetail(error).text) : .notGranted
    }
}

/// Asks for the Microphone permission if never asked, and says whether it is
/// granted. It opens no microphone, so the grant is read, not proven: the app
/// crashed in macOS's audio code after a microphone was unplugged, and the
/// capture session an earlier ready check opened for a moment on every run is
/// the cause [ASSUMED].
public func probeMicrophonePermission() async -> Bool {
    switch AVCaptureDevice.authorizationStatus(for: .audio) {
    case .authorized: true
    case .notDetermined: await AVCaptureDevice.requestAccess(for: .audio)
    case .denied, .restricted: false
    @unknown default: false
    }
}

/// The Camera permission as macOS has it, read without asking (D74).
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

/// Whether the Camera permission is denied, read without asking: `msr list` shows the cameras as not recorded then.
public func cameraPermissionIsDenied() -> Bool {
    readCameraPermission() == .denied
}

/// Asks for the Camera permission if never asked, so macOS shows its
/// prompt, and says whether it is granted. Like the Microphone permission
/// it is read, and no camera is opened.
func askForCameraPermission() async -> Bool {
    switch readCameraPermission() {
    case .granted: true
    case .notAsked: await AVCaptureDevice.requestAccess(for: .video)
    case .denied: false
    }
}

/// Creates the output folder with its parents if it is missing, then writes
/// and deletes a file in it; if that works, measures the free space there.
public func probeOutputFolder(_ folder: URL) -> OutputFolderProbe {
    let probeFile = folder.appending(path: ".msr-write-probe-\(UUID().uuidString)")
    do {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data().write(to: probeFile, options: .withoutOverwriting)
        try FileManager.default.removeItem(at: probeFile)
    } catch {
        return .unusable(ErrorDetail(error).text)
    }
    return .usable(freeSpace(in: folder))
}

/// The free space on the volume of the folder: its plain available capacity,
/// as the important-usage reading is 0 off the boot volume (D71). Nil when the
/// volume does not report it.
func volumeFreeBytes(of folder: URL) throws -> Int64? {
    try folder.resourceValues(forKeys: [.volumeAvailableCapacityKey]).volumeAvailableCapacity.map(Int64.init)
}

private func freeSpace(in folder: URL) -> FreeSpace {
    do {
        guard let bytes = try volumeFreeBytes(of: folder) else {
            return .unreadable("the volume does not report its free space")
        }
        return .bytes(bytes)
    } catch {
        return .unreadable(ErrorDetail(error).text)
    }
}
