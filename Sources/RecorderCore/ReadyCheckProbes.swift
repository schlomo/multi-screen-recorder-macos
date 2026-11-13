import AVFoundation
import CoreGraphics
import Foundation
import RecorderLogic
import ScreenCaptureKit

/// Runs the ready check's probes on this Mac. A permission that was never
/// asked for is requested, so macOS shows its prompt; a missing output folder
/// is created.
@MainActor
public func probeReadyCheckFacts(settings: Settings, homeFolder: URL) async -> ReadyCheckFacts {
    ReadyCheckFacts(
        screenRecording: await probeScreenRecording(),
        microphoneGranted: settings.audioMode == .none ? nil : await microphoneIsGranted(),
        displays: Result { () throws(DeviceReadError) in try currentDisplays() },
        audioInputs: currentAudioInputs(),
        outputFolder: probeOutputFolder(settings.outputFolderURL(homeFolder: homeFolder)))
}

/// Probes this Mac, as `probeReadyCheckFacts`, and judges what it found.
@MainActor
public func runReadyCheck(settings: Settings, homeFolder: URL) async -> ReadyCheckResult {
    ReadyCheck.evaluate(await probeReadyCheckFacts(settings: settings, homeFolder: homeFolder), settings: settings)
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
/// granted. It opens no microphone: a capture session opened for a moment on
/// every check left something behind in macOS that crashed the app when the
/// microphone was unplugged.
public func microphoneIsGranted() async -> Bool {
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
