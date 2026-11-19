import CoreAudio
import EndToEndLogic
import Foundation

/// Core Audio's devices, read and set through its public interface.
enum CoreAudioDevices {
    static func address(_ selector: AudioObjectPropertySelector, _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
                        _ element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: element)
    }

    static func all() -> [AudioObjectID] {
        var address = address(kAudioHardwarePropertyDevices)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size) == noErr else { return [] }
        var devices = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &devices) == noErr else { return [] }
        return devices
    }

    static func uid(_ device: AudioObjectID) -> String? { string(device, kAudioDevicePropertyDeviceUID) }

    static func string(_ device: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String? {
        var address = address(selector)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr, let value else { return nil }
        return value.takeRetainedValue() as String
    }

    static func device(uid: String) -> AudioObjectID? { all().first { self.uid($0) == uid } }

    static func defaultDevice(input: Bool) -> AudioObjectID? {
        var address = address(input ? kAudioHardwarePropertyDefaultInputDevice : kAudioHardwarePropertyDefaultOutputDevice)
        var device = AudioObjectID(0)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device) == noErr,
              device != kAudioObjectUnknown else { return nil }
        return device
    }

    static func setDefaultDevice(input: Bool, uid: String) throws {
        guard var device = device(uid: uid) else { throw DriverError("the audio device \(uid) is gone") }
        var address = address(input ? kAudioHardwarePropertyDefaultInputDevice : kAudioHardwarePropertyDefaultOutputDevice)
        try check(AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil,
                                             UInt32(MemoryLayout<AudioObjectID>.size), &device), "set the default device to \(uid)")
    }

    static func inputChannels(_ device: AudioObjectID) -> Int {
        var address = address(kAudioDevicePropertyStreamConfiguration, kAudioObjectPropertyScopeInput)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(device, &address, 0, nil, &size) == noErr, size > 0 else { return 0 }
        let list = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { list.deallocate() }
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, list) == noErr else { return 0 }
        let buffers = UnsafeMutableAudioBufferListPointer(list.assumingMemoryBound(to: AudioBufferList.self))
        return buffers.reduce(0) { $0 + Int($1.mNumberChannels) }
    }

    static func sampleRate(_ device: AudioObjectID) -> Double? {
        var address = address(kAudioDevicePropertyNominalSampleRate)
        var rate = Float64(0)
        var size = UInt32(MemoryLayout<Float64>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &rate) == noErr else { return nil }
        return rate
    }

    static func setSampleRate(_ device: AudioObjectID, _ rate: Double) throws {
        var address = address(kAudioDevicePropertyNominalSampleRate)
        var value = Float64(rate)
        try check(AudioObjectSetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout<Float64>.size), &value),
                  "set the sample rate to \(rate)")
    }

    /// The input volume of the main element and each channel; nil where there is none.
    static func inputVolumes(_ device: AudioObjectID) -> [Float?] {
        (0...inputChannels(device)).map { element in
            var address = address(kAudioDevicePropertyVolumeScalar, kAudioObjectPropertyScopeInput, AudioObjectPropertyElement(element))
            guard AudioObjectHasProperty(device, &address) else { return nil }
            var volume = Float32(0)
            var size = UInt32(MemoryLayout<Float32>.size)
            return AudioObjectGetPropertyData(device, &address, 0, nil, &size, &volume) == noErr ? volume : nil
        }
    }

    static func setInputVolume(_ device: AudioObjectID, element: Int, _ volume: Float) throws {
        var address = address(kAudioDevicePropertyVolumeScalar, kAudioObjectPropertyScopeInput, AudioObjectPropertyElement(element))
        var value = Float32(volume)
        try check(AudioObjectSetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout<Float32>.size), &value),
                  "set the input volume of element \(element)")
    }

    static func isAggregate(_ device: AudioObjectID) -> Bool {
        var address = address(kAudioDevicePropertyTransportType)
        var transport = UInt32(0)
        var size = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectGetPropertyData(device, &address, 0, nil, &size, &transport) == noErr
            && transport == kAudioDeviceTransportTypeAggregate
    }

    static func check(_ status: OSStatus, _ what: String) throws {
        if status != noErr { throw DriverError("Core Audio could not \(what): OSStatus \(status)") }
    }
}

struct DriverError: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}
