import AVFoundation
import CoreGraphics
import Foundation
import RecorderLogic
import ScreenCaptureKit

/// The probes of the ready check, so a test can stand in for this Mac.
/// Everything that touches a file runs off the main thread; reading the
/// displays needs the main one.
public struct ReadyCheckProbes: Sendable {
    public var screenRecording: @Sendable () async -> PermissionProbe
    public var microphonePermission: @Sendable () async -> Bool
    public var displays: @MainActor @Sendable () -> Result<[DisplayInfo], DeviceReadError>
    public var audioInputs: @Sendable () -> Result<[AudioInputInfo], DeviceReadError>
    public var outputFolder: @Sendable (URL) -> OutputFolderProbe

    public init(
        screenRecording: @escaping @Sendable () async -> PermissionProbe,
        microphonePermission: @escaping @Sendable () async -> Bool,
        displays: @escaping @MainActor @Sendable () -> Result<[DisplayInfo], DeviceReadError>,
        audioInputs: @escaping @Sendable () -> Result<[AudioInputInfo], DeviceReadError>,
        outputFolder: @escaping @Sendable (URL) -> OutputFolderProbe
    ) {
        self.screenRecording = screenRecording
        self.microphonePermission = microphonePermission
        self.displays = displays
        self.audioInputs = audioInputs
        self.outputFolder = outputFolder
    }

    /// This Mac. A permission that was never asked for is requested, so macOS
    /// shows its prompt; a missing output folder is created.
    public static let system = ReadyCheckProbes(
        screenRecording: probeScreenRecording,
        microphonePermission: probeMicrophonePermission,
        displays: { Result { () throws(DeviceReadError) in try currentDisplays() } },
        audioInputs: { Result { () throws(DeviceReadError) in try currentAudioInputs() } },
        outputFolder: probeOutputFolder)
}

/// Runs the ready check's probes. The microphone permission is asked only
/// when the recording records an audio input.
@concurrent
public func probeReadyCheckFacts(
    settings: Settings, homeFolder: URL, probes: ReadyCheckProbes = .system
) async -> ReadyCheckFacts {
    let screenRecording = await probes.screenRecording()
    let audioInputs = probes.audioInputs()
    let microphoneGranted = ReadyCheck.recordsAudioInput(audioInputs, settings: settings)
        ? await probes.microphonePermission() : nil
    let displays = await probes.displays()
    return ReadyCheckFacts(
        screenRecording: screenRecording,
        microphoneGranted: microphoneGranted,
        displays: displays,
        audioInputs: audioInputs,
        outputFolder: probes.outputFolder(settings.outputFolderURL(homeFolder: homeFolder)))
}

/// Whether the Screen & System Audio Recording permission is granted, without
/// asking for it.
public func screenRecordingIsGranted() -> Bool {
    CGPreflightScreenCaptureAccess()
}

/// Asks for the permission if needed, then proves the grant by fetching the
/// display list through ScreenCaptureKit.
public func probeScreenRecording() async -> PermissionProbe {
    if !CGPreflightScreenCaptureAccess() {
        _ = CGRequestScreenCaptureAccess()
    }
    do {
        _ = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        return .granted
    } catch {
        return CGPreflightScreenCaptureAccess() ? .failed(error.localizedDescription) : .notGranted
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

/// Creates the output folder with its parents if it is missing, then writes
/// and deletes a file in it; if that works, measures the free space there.
public func probeOutputFolder(_ folder: URL) -> OutputFolderProbe {
    let probeFile = folder.appending(path: ".msr-write-probe-\(UUID().uuidString)")
    do {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data().write(to: probeFile, options: .withoutOverwriting)
        try FileManager.default.removeItem(at: probeFile)
    } catch {
        return .unusable(error.localizedDescription)
    }
    return .usable(freeSpace(in: folder))
}

/// Free space for important use on the volume of the folder.
private func freeSpace(in folder: URL) -> FreeSpace {
    do {
        let values = try folder.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        guard let bytes = values.volumeAvailableCapacityForImportantUsage else {
            return .unreadable("the volume does not report its free space")
        }
        return .bytes(bytes)
    } catch {
        return .unreadable(error.localizedDescription)
    }
}
