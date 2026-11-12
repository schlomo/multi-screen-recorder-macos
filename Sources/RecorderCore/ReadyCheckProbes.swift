import AVFoundation
import CoreGraphics
import Foundation
import RecorderLogic
import ScreenCaptureKit

/// Runs the ready check's probes on this Mac. A permission that was never
/// asked for is requested, so macOS shows its prompt; a missing output folder
/// is created.
@MainActor
public func runReadyCheck(settings: Settings, homeFolder: URL) async -> ReadyCheckResult {
    let facts = ReadyCheckFacts(
        screenRecording: await probeScreenRecording(),
        microphone: settings.audioMode == .none ? nil : await probeMicrophone(),
        displays: Result { () throws(DeviceReadError) in try currentDisplays() },
        defaultMicrophone: defaultAudioInputName(),
        outputFolder: probeOutputFolder(settings.outputFolderURL(homeFolder: homeFolder)))
    return ReadyCheck.evaluate(facts, settings: settings)
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

/// Asks for the Microphone permission if never asked, then proves the grant
/// by opening the default microphone. Without a microphone there is nothing
/// to open, so the granted permission stands; the ready check's audio item
/// reports the missing microphone.
public func probeMicrophone() async -> PermissionProbe {
    switch AVCaptureDevice.authorizationStatus(for: .audio) {
    case .authorized:
        break
    case .notDetermined:
        guard await AVCaptureDevice.requestAccess(for: .audio) else { return .notGranted }
    case .denied, .restricted:
        return .notGranted
    @unknown default:
        return .notGranted
    }
    return openMicrophone(AVCaptureDevice.default(for: .audio))
}

func openMicrophone(_ device: AVCaptureDevice?) -> PermissionProbe {
    guard let device else { return .granted }
    let session = AVCaptureSession()
    do {
        let input = try AVCaptureDeviceInput(device: device)
        guard session.canAddInput(input) else { return .failed("the capture session refused it") }
        session.addInput(input)
        session.addOutput(AVCaptureAudioDataOutput())
        session.startRunning()
        defer { session.stopRunning() }
        return session.isRunning ? .granted : .failed("the capture session did not start")
    } catch {
        return .failed(error.localizedDescription)
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
