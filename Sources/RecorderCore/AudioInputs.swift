import CoreAudio
import Foundation
import RecorderLogic

/// One audio device as Core Audio reports it, before it becomes an `AudioInputInfo`.
struct AudioDeviceReading: Equatable {
    var id: AudioObjectID
    var name: String
    /// The input channels, or why they cannot be read; nil for a device without input.
    var inputChannelCount: Result<Int, DeviceReadError>?
}

/// The audio inputs in Core Audio's order, the default one marked. Listing
/// needs no permission and creates no capture object.
public func currentAudioInputs() throws(DeviceReadError) -> [AudioInputInfo] {
    var readings: [AudioDeviceReading] = []
    for id in try audioDeviceIDs() {
        if let reading = try readAudioDevice(id) { readings.append(reading) }
    }
    return audioInputs(from: readings, defaultInput: try defaultInputDeviceID())
}

func audioInputs(from readings: [AudioDeviceReading], defaultInput: AudioObjectID) -> [AudioInputInfo] {
    readings.compactMap { reading in
        guard let channelCount = reading.inputChannelCount else { return nil }
        return AudioInputInfo(name: reading.name, channelCount: channelCount, isDefault: reading.id == defaultInput)
    }
}

/// Calls `changed` on the main actor whenever an audio device comes or goes
/// or the default audio input changes, for the rest of the process's life.
public func watchAudioInputs(changed: @escaping @MainActor @Sendable () -> Void) throws(DeviceReadError) {
    for selector in [kAudioHardwarePropertyDevices, kAudioHardwarePropertyDefaultInputDevice] {
        var address = address(selector)
        let status = AudioObjectAddPropertyListenerBlock(systemObject, &address, .main) { _, _ in
            Task { @MainActor in changed() }
        }
        guard status == noErr else {
            throw DeviceReadError("changes of the audio devices cannot be watched (Core Audio error \(status))")
        }
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
    guard status == noErr else { throw DeviceReadError("the list of audio devices cannot be read (Core Audio error \(status))") }
    var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
    status = AudioObjectGetPropertyData(systemObject, &address, 0, nil, &size, &ids)
    guard status == noErr else { throw DeviceReadError("the list of audio devices cannot be read (Core Audio error \(status))") }
    return Array(ids.prefix(Int(size) / MemoryLayout<AudioObjectID>.size))
}

/// `kAudioObjectUnknown`, which no device has, when there is no audio input.
private func defaultInputDeviceID() throws(DeviceReadError) -> AudioObjectID {
    var address = address(kAudioHardwarePropertyDefaultInputDevice)
    var id = AudioObjectID(kAudioObjectUnknown)
    var size = UInt32(MemoryLayout<AudioObjectID>.size)
    let status = AudioObjectGetPropertyData(systemObject, &address, 0, nil, &size, &id)
    guard status == noErr else { throw DeviceReadError("the default audio input cannot be read (Core Audio error \(status))") }
    return id
}

/// Nil for a device that disappeared since the list was read.
private func readAudioDevice(_ id: AudioObjectID) throws(DeviceReadError) -> AudioDeviceReading? {
    guard let name = try audioDeviceName(id) else { return nil }
    let unreadable = { (reason: String) in
        AudioDeviceReading(id: id, name: name, inputChannelCount: .failure(
            DeviceReadError("the audio device \(name) does not report its channels (\(reason))")))
    }
    var address = address(kAudioDevicePropertyStreamConfiguration, scope: kAudioObjectPropertyScopeInput)
    var size: UInt32 = 0
    var status = AudioObjectGetPropertyDataSize(id, &address, 0, nil, &size)
    if status == kAudioHardwareBadObjectError { return nil }
    guard status == noErr else { return unreadable("Core Audio error \(status)") }

    let byteCount = max(Int(size), MemoryLayout<AudioBufferList>.size)
    let buffer = UnsafeMutableRawPointer.allocate(byteCount: byteCount, alignment: MemoryLayout<AudioBufferList>.alignment)
    defer { buffer.deallocate() }
    buffer.initializeMemory(as: UInt8.self, repeating: 0, count: byteCount)
    status = AudioObjectGetPropertyData(id, &address, 0, nil, &size, buffer)
    if status == kAudioHardwareBadObjectError { return nil }
    guard status == noErr else { return unreadable("Core Audio error \(status)") }

    let buffers = UnsafeMutableAudioBufferListPointer(buffer.assumingMemoryBound(to: AudioBufferList.self))
    let buffersOffset = MemoryLayout<AudioBufferList>.offset(of: \.mBuffers) ?? 0
    guard buffers.count <= (byteCount - buffersOffset) / MemoryLayout<AudioBuffer>.stride else {
        return unreadable("it names \(buffers.count) streams and describes fewer")
    }
    let channels = buffers.reduce(0) { $0 + Int($1.mNumberChannels) }
    return AudioDeviceReading(id: id, name: name, inputChannelCount: channels > 0 ? .success(channels) : nil)
}

/// Nil for a device that disappeared since the list was read.
private func audioDeviceName(_ id: AudioObjectID) throws(DeviceReadError) -> String? {
    var address = address(kAudioObjectPropertyName)
    var name: Unmanaged<CFString>?
    var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
    let status = withUnsafeMutablePointer(to: &name) { AudioObjectGetPropertyData(id, &address, 0, nil, &size, $0) }
    if status == kAudioHardwareBadObjectError { return nil }
    guard status == noErr, let name else {
        throw DeviceReadError("the audio device \(id) does not report its name (Core Audio error \(status))")
    }
    return name.takeRetainedValue() as String
}
