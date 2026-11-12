import AVFoundation
import CoreGraphics
import Foundation
import RecorderLogic
import ScreenCaptureKit

/// Runs the ready check's probes on this Mac. A permission that was never
/// asked for is requested, so macOS shows its prompt.
@MainActor
public func runReadyCheck(settings: Settings, homeFolder: URL) async -> ReadyCheckResult {
    let facts = ReadyCheckFacts(
        screenRecording: await probeScreenRecording(),
        microphone: settings.audioMode == .none ? nil : await probeMicrophone(),
        displays: currentDisplays(),
        defaultMicrophone: defaultAudioInput(),
        freeSpace: freeSpace(in: settings.outputFolderURL(homeFolder: homeFolder)))
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
/// by opening the default microphone.
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
    return openDefaultMicrophone()
}

private func openDefaultMicrophone() -> PermissionProbe {
    guard let device = AVCaptureDevice.default(for: .audio) else {
        return .failed("there is no default microphone")
    }
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

/// Free space for important use on the volume of the folder, or of its
/// nearest existing parent folder when it does not exist yet.
public func freeSpace(in folder: URL) -> FreeSpace {
    var candidate = folder.standardizedFileURL
    while !FileManager.default.fileExists(atPath: candidate.path(percentEncoded: false)) {
        let parent = candidate.deletingLastPathComponent()
        if parent == candidate { break }
        candidate = parent
    }
    do {
        let values = try candidate.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        guard let bytes = values.volumeAvailableCapacityForImportantUsage else {
            return .unreadable("the volume does not report its free space")
        }
        return .bytes(bytes)
    } catch {
        return .unreadable(error.localizedDescription)
    }
}
