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

/// The audio inputs, the default one marked. Listing needs no permission.
///
/// Read from Core Audio's device list: it creates no capture object, so
/// nothing of it is left behind when a device disappears. If the device list
/// itself cannot be read, the one entry returned carries the reason, so the
/// ready check and `msr list` report it.
public func currentAudioInputs() -> [AudioInputInfo] {
    do {
        let readings = try audioDeviceIDs().compactMap(readAudioDevice)
        return audioInputs(from: readings, defaultInput: try? defaultInputDeviceID())
    } catch {
        return [AudioInputInfo(name: "Audio inputs", channelCount: .failure(error), isDefault: true)]
    }
}

func audioInputs(from readings: [AudioDeviceReading], defaultInput: AudioObjectID?) -> [AudioInputInfo] {
    readings.compactMap { reading in
        guard let channelCount = reading.inputChannelCount else { return nil }
        return AudioInputInfo(name: reading.name, channelCount: channelCount, isDefault: reading.id == defaultInput)
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

private func defaultInputDeviceID() throws(DeviceReadError) -> AudioObjectID {
    var address = address(kAudioHardwarePropertyDefaultInputDevice)
    var id = AudioObjectID(kAudioObjectUnknown)
    var size = UInt32(MemoryLayout<AudioObjectID>.size)
    let status = AudioObjectGetPropertyData(systemObject, &address, 0, nil, &size, &id)
    guard status == noErr else { throw DeviceReadError("the default audio input cannot be read (Core Audio error \(status))") }
    return id
}

/// Nil for a device that disappeared since the list was read.
private func readAudioDevice(_ id: AudioObjectID) -> AudioDeviceReading? {
    let name = audioDeviceName(id) ?? "Audio device \(id)"
    var address = address(kAudioDevicePropertyStreamConfiguration, scope: kAudioObjectPropertyScopeInput)
    var size: UInt32 = 0
    var status = AudioObjectGetPropertyDataSize(id, &address, 0, nil, &size)
    if status == kAudioHardwareBadObjectError { return nil }
    guard status == noErr else {
        return AudioDeviceReading(id: id, name: name, inputChannelCount: .failure(
            DeviceReadError("the audio device \(name) does not report its channels (Core Audio error \(status))")))
    }
    let buffer = UnsafeMutableRawPointer.allocate(
        byteCount: max(Int(size), MemoryLayout<AudioBufferList>.size), alignment: MemoryLayout<AudioBufferList>.alignment)
    defer { buffer.deallocate() }
    status = AudioObjectGetPropertyData(id, &address, 0, nil, &size, buffer)
    if status == kAudioHardwareBadObjectError { return nil }
    guard status == noErr else {
        return AudioDeviceReading(id: id, name: name, inputChannelCount: .failure(
            DeviceReadError("the audio device \(name) does not report its channels (Core Audio error \(status))")))
    }
    let buffers = UnsafeMutableAudioBufferListPointer(buffer.assumingMemoryBound(to: AudioBufferList.self))
    let channels = buffers.reduce(0) { $0 + Int($1.mNumberChannels) }
    return AudioDeviceReading(id: id, name: name, inputChannelCount: channels > 0 ? .success(channels) : nil)
}

private func audioDeviceName(_ id: AudioObjectID) -> String? {
    var address = address(kAudioObjectPropertyName)
    var name: Unmanaged<CFString>?
    var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
    let status = withUnsafeMutablePointer(to: &name) { AudioObjectGetPropertyData(id, &address, 0, nil, &size, $0) }
    guard status == noErr, let name else { return nil }
    return name.takeRetainedValue() as String
}

/// Calls `changed` on the main queue whenever the set of audio devices or the
/// default audio input changes, until the returned watcher is released.
public final class AudioInputWatcher {
    private let listener: AudioObjectPropertyListenerBlock
    private var addresses = [address(kAudioHardwarePropertyDevices), address(kAudioHardwarePropertyDefaultInputDevice)]

    public init(changed: @escaping @MainActor @Sendable () -> Void) {
        listener = { _, _ in Task { @MainActor in changed() } }
        for index in addresses.indices {
            AudioObjectAddPropertyListenerBlock(systemObject, &addresses[index], .main, listener)
        }
    }

    deinit {
        for index in addresses.indices {
            AudioObjectRemovePropertyListenerBlock(systemObject, &addresses[index], .main, listener)
        }
    }
}
