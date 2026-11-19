import CoreAudio
import Foundation
import RecorderLogic

/// What a device answers when asked for its input channels.
enum InputChannels: Equatable {
    /// The device disappeared since the list was read.
    case gone
    case count(Int)
    case unreadable(String)
}

/// The audio inputs in Core Audio's order, the default one marked. Listing
/// needs no permission and creates no capture object.
public func currentAudioInputs() throws(DeviceReadError) -> [AudioInputInfo] {
    try audioInputs(
        devices: try audioDeviceIDs(), inputChannels: inputChannels, name: audioDeviceName,
        transport: { audioTransport(coreAudioValue: audioDeviceTransportType($0)) },
        uid: audioDeviceUID, defaultInput: defaultInputDeviceID)
}

/// A device without input channels is asked nothing more, so it cannot fail
/// the listing; one whose channels cannot be read is listed with the reason,
/// as it may be an audio input. `name` gives nil for a device that
/// disappeared; `transport` says how an input is connected. Without an audio input the default is not asked for: what
/// Core Audio answers then has not been observed.
func audioInputs(
    devices: [AudioObjectID],
    inputChannels: (AudioObjectID) -> InputChannels,
    name: (AudioObjectID) throws(DeviceReadError) -> String?,
    transport: (AudioObjectID) -> AudioTransport,
    uid: (AudioObjectID) -> String?,
    defaultInput: () throws(DeviceReadError) -> AudioObjectID
) throws(DeviceReadError) -> [AudioInputInfo] {
    var inputs: [(id: AudioObjectID, name: String, channelCount: Result<Int, DeviceReadError>)] = []
    for id in devices {
        var count = 0
        var unreadableReason: String?
        switch inputChannels(id) {
        case .gone, .count(0): continue
        case .count(let channels): count = channels
        case .unreadable(let reason): unreadableReason = reason
        }
        guard let name = try name(id) else { continue }
        let channelCount: Result<Int, DeviceReadError> = unreadableReason.map {
            .failure(DeviceReadError("the audio device \(name) does not report its channels (\($0))"))
        } ?? .success(count)
        inputs.append((id, name, channelCount))
    }
    guard !inputs.isEmpty else { return [] }
    let defaultID = try defaultInput()
    return inputs.map {
        AudioInputInfo(
            name: $0.name, channelCount: $0.channelCount, isDefault: $0.id == defaultID, transport: transport($0.id),
            uid: uid($0.id))
    }
}

/// The transport type of a device, as Core Audio's four-character code;
/// nil when it cannot be read.
private func audioDeviceTransportType(_ id: AudioObjectID) -> UInt32? {
    var address = address(kAudioDevicePropertyTransportType)
    var value: UInt32 = 0
    var size = UInt32(MemoryLayout<UInt32>.size)
    let status = AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value)
    return status == noErr ? value : nil
}

/// Watches the audio devices and the default audio input: `changed` is
/// called on the main actor for every change, until `cancel`.
public final class AudioInputWatch {
    private var listeners: [(AudioObjectPropertyAddress, AudioObjectPropertyListenerBlock)] = []

    public init(changed: @escaping @MainActor @Sendable () -> Void) throws(DeviceReadError) {
        for selector in [kAudioHardwarePropertyDevices, kAudioHardwarePropertyDefaultInputDevice] {
            var address = address(selector)
            let block: AudioObjectPropertyListenerBlock = { _, _ in Task { @MainActor in changed() } }
            let status = AudioObjectAddPropertyListenerBlock(systemObject, &address, .main, block)
            guard status == noErr else {
                cancel()
                throw DeviceReadError("changes of the audio devices cannot be watched (Core Audio error \(ErrorDetail.codeText(Int(status))))")
            }
            listeners.append((address, block))
        }
    }

    public func cancel() {
        for (address, block) in listeners {
            var address = address
            AudioObjectRemovePropertyListenerBlock(systemObject, &address, .main, block)
        }
        listeners = []
    }
}

private let systemObject = AudioObjectID(kAudioObjectSystemObject)

private func address(
    _ selector: AudioObjectPropertySelector, scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal
) -> AudioObjectPropertyAddress {
    AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
}

private func audioDeviceIDs() throws(DeviceReadError) -> [AudioObjectID] {
    var address = address(kAudioHardwarePropertyDevices)
    var size: UInt32 = 0
    var status = AudioObjectGetPropertyDataSize(systemObject, &address, 0, nil, &size)
    guard status == noErr else { throw DeviceReadError("the list of audio devices cannot be read (Core Audio error \(ErrorDetail.codeText(Int(status))))") }
    var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
    status = AudioObjectGetPropertyData(systemObject, &address, 0, nil, &size, &ids)
    guard status == noErr else { throw DeviceReadError("the list of audio devices cannot be read (Core Audio error \(ErrorDetail.codeText(Int(status))))") }
    return Array(ids.prefix(Int(size) / MemoryLayout<AudioObjectID>.size))
}

private func defaultInputDeviceID() throws(DeviceReadError) -> AudioObjectID {
    var address = address(kAudioHardwarePropertyDefaultInputDevice)
    var id = AudioObjectID(kAudioObjectUnknown)
    var size = UInt32(MemoryLayout<AudioObjectID>.size)
    let status = AudioObjectGetPropertyData(systemObject, &address, 0, nil, &size, &id)
    guard status == noErr else { throw DeviceReadError("the default audio input cannot be read (Core Audio error \(ErrorDetail.codeText(Int(status))))") }
    return id
}

private func inputChannels(_ id: AudioObjectID) -> InputChannels {
    var address = address(kAudioDevicePropertyStreamConfiguration, scope: kAudioObjectPropertyScopeInput)
    var size: UInt32 = 0
    var status = AudioObjectGetPropertyDataSize(id, &address, 0, nil, &size)
    if status == kAudioHardwareBadObjectError { return .gone }
    guard status == noErr else { return .unreadable("Core Audio error \(ErrorDetail.codeText(Int(status)))") }

    let byteCount = max(Int(size), MemoryLayout<AudioBufferList>.size)
    let buffer = UnsafeMutableRawPointer.allocate(byteCount: byteCount, alignment: MemoryLayout<AudioBufferList>.alignment)
    defer { buffer.deallocate() }
    buffer.initializeMemory(as: UInt8.self, repeating: 0, count: byteCount)
    status = AudioObjectGetPropertyData(id, &address, 0, nil, &size, buffer)
    if status == kAudioHardwareBadObjectError { return .gone }
    guard status == noErr else { return .unreadable("Core Audio error \(ErrorDetail.codeText(Int(status)))") }

    let buffers = UnsafeMutableAudioBufferListPointer(buffer.assumingMemoryBound(to: AudioBufferList.self))
    let buffersOffset = MemoryLayout<AudioBufferList>.offset(of: \.mBuffers) ?? 0
    guard buffers.count <= (byteCount - buffersOffset) / MemoryLayout<AudioBuffer>.stride else {
        return .unreadable("it names \(buffers.count) streams and describes fewer")
    }
    return .count(buffers.reduce(0) { $0 + Int($1.mNumberChannels) })
}

/// The device's Core Audio UID, which `AVCaptureDevice` uses as its
/// `uniqueID`; nil when it cannot be read.
private func audioDeviceUID(_ id: AudioObjectID) -> String? {
    var address = address(kAudioDevicePropertyDeviceUID)
    var uid: Unmanaged<CFString>?
    var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
    let status = withUnsafeMutablePointer(to: &uid) { AudioObjectGetPropertyData(id, &address, 0, nil, &size, $0) }
    guard status == noErr, let uid else { return nil }
    return uid.takeRetainedValue() as String
}

/// Nil for a device that disappeared since the list was read.
private func audioDeviceName(_ id: AudioObjectID) throws(DeviceReadError) -> String? {
    var address = address(kAudioObjectPropertyName)
    var name: Unmanaged<CFString>?
    var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
    let status = withUnsafeMutablePointer(to: &name) { AudioObjectGetPropertyData(id, &address, 0, nil, &size, $0) }
    if status == kAudioHardwareBadObjectError { return nil }
    guard status == noErr, let name else {
        throw DeviceReadError("the audio device \(id) does not report its name (Core Audio error \(ErrorDetail.codeText(Int(status))))")
    }
    return name.takeRetainedValue() as String
}

/// The transport of a Core Audio transport type; nil, a type that could not
/// be read, is unreadable and any type not named here unknown.
func audioTransport(coreAudioValue value: UInt32?) -> AudioTransport {
    guard let value else { return .unreadable }
    return switch value {
    case kAudioDeviceTransportTypeBuiltIn: .builtIn
    case kAudioDeviceTransportTypeUSB: .usb
    case kAudioDeviceTransportTypeFireWire: .fireWire
    case kAudioDeviceTransportTypePCI: .pci
    case kAudioDeviceTransportTypeThunderbolt: .thunderbolt
    case kAudioDeviceTransportTypeHDMI: .hdmi
    case kAudioDeviceTransportTypeDisplayPort: .displayPort
    case kAudioDeviceTransportTypeBluetooth: .bluetooth
    case kAudioDeviceTransportTypeBluetoothLE: .bluetoothLE
    case kAudioDeviceTransportTypeVirtual: .virtual
    case kAudioDeviceTransportTypeAggregate, kAudioDeviceTransportTypeAutoAggregate: .aggregate
    case kAudioDeviceTransportTypeAirPlay: .airPlay
    case kAudioDeviceTransportTypeContinuityCaptureWired, kAudioDeviceTransportTypeContinuityCaptureWireless:
        .continuityCapture
    default: .unknown
    }
}
