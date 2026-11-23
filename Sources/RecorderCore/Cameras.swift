import AVFoundation
import CoreMediaIO
import Foundation
import IOKit
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
    let running = camerasRunningSomewhere()
    let devices = cameraDevices()
    let speeds = devices.contains { $0.transportType == Int32(bitPattern: kAudioDeviceTransportTypeUSB) } ? usbSpeeds() : [:]
    return devices.map { device in
        let transport = audioTransport(coreAudioValue: UInt32(bitPattern: device.transportType))
        return CameraInfo(
            uniqueID: device.uniqueID, name: device.localizedName, isDefault: device.uniqueID == defaultID,
            isVirtual: cameraIsVirtual(deviceType: device.deviceType, transportType: device.transportType),
            isContinuity: cameraIsContinuity(deviceType: device.deviceType, transportType: device.transportType),
            formats: CameraFormat.preferred(device.formats.map(cameraFormat)),
            isSuspended: device.isSuspended, activeFormat: cameraFormat(of: device.activeFormat),
            isRunningElsewhere: running.contains(device.uniqueID), transport: transport,
            offeredFormats: CameraFormat.offered(device.formats.map(cameraFormat)), activeFrameRates: activeFrameRates(of: device),
            usbSpeed: transport == .usb ? USBSpeed.locationID(ofUniqueID: device.uniqueID).flatMap { speeds[$0] } : nil)
    }
}

/// The frame rates a camera runs at now, from its active frame durations; nil where they cannot be read.
private func activeFrameRates(of device: AVCaptureDevice) -> ClosedRange<Double>? {
    let slowest = device.activeVideoMaxFrameDuration.seconds, fastest = device.activeVideoMinFrameDuration.seconds
    guard slowest.isFinite, fastest.isFinite, slowest > 0, fastest > 0, fastest <= slowest else { return nil }
    return (1 / slowest)...(1 / fastest)
}

/// The link speed of every USB device by its location ID, as IOKit's
/// registry says it (`USBSpeed`, which Apple marks as subject to change);
/// empty where the registry cannot be read.
func usbSpeeds() -> [UInt32: USBSpeed] {
    var iterator: io_iterator_t = 0
    guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOUSBHostDevice"), &iterator) == KERN_SUCCESS else {
        return [:]
    }
    defer { IOObjectRelease(iterator) }
    var speeds: [UInt32: USBSpeed] = [:]
    while case let service = IOIteratorNext(iterator), service != 0 {
        defer { IOObjectRelease(service) }
        let number = { (key: String) in
            IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? NSNumber
        }
        if let location = number("locationID"), let speed = number("USBSpeed").flatMap({ USBSpeed(rawValue: $0.intValue) }) {
            speeds[location.uint32Value] = speed
        }
    }
    return speeds
}

/// The unique IDs of the cameras CoreMediaIO says run in any process
/// (`kCMIODevicePropertyDeviceIsRunningSomewhere`), matched by the CMIO
/// device's UID, which is the AVFoundation device's unique ID. A device
/// whose properties cannot be read counts as not running.
func camerasRunningSomewhere() -> Set<String> {
    var devices = address(kCMIOHardwarePropertyDevices)
    var size: UInt32 = 0
    guard CMIOObjectGetPropertyDataSize(CMIOObjectID(kCMIOObjectSystemObject), &devices, 0, nil, &size) == noErr else { return [] }
    var ids = [CMIOObjectID](repeating: 0, count: Int(size) / MemoryLayout<CMIOObjectID>.size)
    var used: UInt32 = 0
    guard CMIOObjectGetPropertyData(CMIOObjectID(kCMIOObjectSystemObject), &devices, 0, nil, size, &used, &ids) == noErr else { return [] }
    return Set(ids.compactMap { id -> String? in
        var running = address(kCMIODevicePropertyDeviceIsRunningSomewhere)
        var isRunning: UInt32 = 0
        var runningSize = UInt32(MemoryLayout<UInt32>.size)
        guard CMIOObjectGetPropertyData(id, &running, 0, nil, runningSize, &runningSize, &isRunning) == noErr, isRunning != 0 else {
            return nil
        }
        var uidAddress = address(kCMIODevicePropertyDeviceUID)
        var uid: Unmanaged<CFString>?
        var uidSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard CMIOObjectGetPropertyData(id, &uidAddress, 0, nil, uidSize, &uidSize, &uid) == noErr else { return nil }
        return uid?.takeRetainedValue() as String?
    })
}

private func address(_ selector: Int) -> CMIOObjectPropertyAddress {
    CMIOObjectPropertyAddress(
        mSelector: CMIOObjectPropertySelector(selector), mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
        mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain))
}

/// A device format as the recording knows it: its size and its lowest and highest frame rate.
func cameraFormat(of format: AVCaptureDevice.Format) -> CameraFormat {
    let dimensions = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
    let ranges = format.videoSupportedFrameRateRanges
    return CameraFormat(
        size: FrameSize(width: Int(dimensions.width), height: Int(dimensions.height)),
        maxFramesPerSecond: ranges.map(\.maxFrameRate).max() ?? 0, minFramesPerSecond: ranges.map(\.minFrameRate).min())
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
/// calls `changed` on the main thread, as does another app starting or
/// ending its use of a camera (`isInUseByAnotherApplication`, also a
/// detail line) or a change of a camera's active format.
@MainActor
public final class CameraWatch {
    private let changed: @MainActor () -> Void
    private var tokens: [any NSObjectProtocol] = []
    private var observations: [NSKeyValueObservation] = []

    public init(changed: @escaping @MainActor () -> Void) {
        self.changed = changed
        tokens = [AVCaptureDevice.wasConnectedNotification, AVCaptureDevice.wasDisconnectedNotification].map { name in
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                guard (note.object as? AVCaptureDevice)?.hasMediaType(.video) == true else { return }
                MainActor.assumeIsolated { self?.devicesChanged() }
            }
        }
        observeDevices()
    }

    private func devicesChanged() {
        observeDevices()
        changed()
    }

    private func observeDevices() {
        let changed: @Sendable () -> Void = { [weak self] in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.changed() } }
        }
        observations = cameraDevices().flatMap { device in [
            device.observe(\.isSuspended) { _, _ in changed() },
            device.observe(\.activeFormat) { _, _ in changed() },
            device.observe(\.isInUseByAnotherApplication) { device, _ in
                RecorderLog.detail(
                    "camera \(device.localizedName) (\(device.uniqueID)): "
                        + (device.isInUseByAnotherApplication ? "now in use by another app" : "no longer in use by another app"),
                    category: "recorder")
                changed()
            },
        ] }
    }

    public func cancel() {
        for token in tokens { NotificationCenter.default.removeObserver(token) }
        tokens = []
        observations = []
    }
}
