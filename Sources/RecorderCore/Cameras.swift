import AVFoundation
import Foundation
import RecorderLogic

/// The kinds of camera device AVFoundation lists on a Mac.
private let cameraDeviceTypes: [AVCaptureDevice.DeviceType] = [.builtInWideAngleCamera, .continuityCamera, .deskViewCamera, .external]

private func cameraDevices() -> [AVCaptureDevice] {
    AVCaptureDevice.DiscoverySession(deviceTypes: cameraDeviceTypes, mediaType: .video, position: .unspecified).devices
}

/// The cameras AVFoundation lists now, with their formats; listing them asks
/// for no permission and opens none. The default camera is
/// `AVCaptureDevice.default(for: .video)`.
public func currentCameras() -> [CameraInfo] {
    let defaultID = AVCaptureDevice.default(for: .video)?.uniqueID
    return cameraDevices().map { device in
        CameraInfo(
            uniqueID: device.uniqueID, name: device.localizedName, isDefault: device.uniqueID == defaultID,
            isVirtual: cameraIsVirtual(deviceType: device.deviceType, transportType: device.transportType),
            isContinuity: cameraIsContinuity(deviceType: device.deviceType, transportType: device.transportType),
            formats: CameraFormat.preferred(device.formats.map(cameraFormat)),
            isSuspended: device.isSuspended)
    }
}

/// A device format as the recording knows it: its size and its highest frame rate.
func cameraFormat(of format: AVCaptureDevice.Format) -> CameraFormat {
    let dimensions = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
    return CameraFormat(
        size: FrameSize(width: Int(dimensions.width), height: Int(dimensions.height)),
        maxFramesPerSecond: format.videoSupportedFrameRateRanges.map(\.maxFrameRate).max() ?? 0)
}

/// Whether a camera is virtual, made by software such as OBS Virtual Camera
/// (a CoreMediaIO extension): a camera is a device, not virtual, when
/// AVFoundation lists it as built in, as a Continuity Camera or Desk View,
/// or connected by
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

/// Whether a camera is an iPhone's: a Continuity Camera or Desk View, or
/// connected by Continuity Capture. Recorded only under All, as a virtual
/// one (D74).
func cameraIsContinuity(deviceType: AVCaptureDevice.DeviceType, transportType: Int32) -> Bool {
    [.continuityCamera, .deskViewCamera].contains(deviceType)
        || audioTransport(coreAudioValue: UInt32(bitPattern: transportType)) == .continuityCapture
}

/// Follows the cameras: one connected or disconnected (video devices only)
/// or suspended or resumed (`isSuspended`, observed on every camera listed)
/// calls `changed` on the main thread.
@MainActor
public final class CameraWatch {
    private let changed: @MainActor () -> Void
    private var tokens: [any NSObjectProtocol] = []
    private var suspensions: [NSKeyValueObservation] = []

    public init(changed: @escaping @MainActor () -> Void) {
        self.changed = changed
        tokens = [AVCaptureDevice.wasConnectedNotification, AVCaptureDevice.wasDisconnectedNotification].map { name in
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                guard (note.object as? AVCaptureDevice)?.hasMediaType(.video) == true else { return }
                MainActor.assumeIsolated { self?.devicesChanged() }
            }
        }
        observeSuspensions()
    }

    private func devicesChanged() {
        observeSuspensions()
        changed()
    }

    private func observeSuspensions() {
        suspensions = cameraDevices().map { device in
            device.observe(\.isSuspended) { [weak self] _, _ in
                DispatchQueue.main.async { MainActor.assumeIsolated { self?.changed() } }
            }
        }
    }

    public func cancel() {
        for token in tokens { NotificationCenter.default.removeObserver(token) }
        tokens = []
        suspensions = []
    }
}
