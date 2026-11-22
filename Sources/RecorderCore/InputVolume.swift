import AudioToolbox
import CoreAudio
import Foundation
import RecorderLogic

/// Why an input volume cannot be set or followed.
public struct InputVolumeError: Error, Equatable, Sendable, CustomStringConvertible {
    public let description: String

    init(_ description: String) {
        self.description = description
    }
}

/// An audio input's own input volume (D69), the one macOS's Sound settings,
/// another app or the device's knob change: setting it changes it for
/// every app on the Mac, and it is not reset at Stop.
protocol InputVolumeControl: AnyObject, Sendable {
    /// Whether the recorder may set it: the status window shows a slider only then.
    var isSettable: Bool { get }
    /// 0 to 1; nil when it cannot be read.
    func read() -> Double?
    func set(_ volume: Double) throws(InputVolumeError)
    /// Calls `changed` on the main queue for every change Core Audio reports, until `cancel`.
    func watch(_ changed: @escaping @Sendable () -> Void) throws(InputVolumeError)
    func cancel()
}

/// The Core Audio calls of an input volume, by the device and the property's
/// address; a test stands in for them, so no test sets a real device's volume.
struct CoreAudioProperty: Sendable {
    var has: @Sendable (AudioObjectID, AudioObjectPropertyAddress) -> Bool
    var isSettable: @Sendable (AudioObjectID, AudioObjectPropertyAddress) -> Bool
    var read: @Sendable (AudioObjectID, AudioObjectPropertyAddress) -> (status: OSStatus, value: Float32)
    var write: @Sendable (AudioObjectID, AudioObjectPropertyAddress, Float32) -> OSStatus
    var addListener: @Sendable (AudioObjectID, AudioObjectPropertyAddress, @escaping AudioObjectPropertyListenerBlock) -> OSStatus
    var removeListener: @Sendable (AudioObjectID, AudioObjectPropertyAddress, @escaping AudioObjectPropertyListenerBlock) -> OSStatus

    static let system = CoreAudioProperty(
        has: { device, address in
            var address = address
            return AudioObjectHasProperty(device, &address)
        },
        isSettable: { device, address in
            var address = address
            var settable: DarwinBoolean = false
            return AudioObjectIsPropertySettable(device, &address, &settable) == noErr && settable.boolValue
        },
        read: { device, address in
            var address = address
            var value: Float32 = 0
            var size = UInt32(MemoryLayout<Float32>.size)
            let status = AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value)
            return (status, value)
        },
        write: { device, address, value in
            var address = address
            var value = value
            return AudioObjectSetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout<Float32>.size), &value)
        },
        addListener: { device, address, block in
            var address = address
            return AudioObjectAddPropertyListenerBlock(device, &address, .main, block)
        },
        removeListener: { device, address, block in
            var address = address
            return AudioObjectRemovePropertyListenerBlock(device, &address, .main, block)
        })
}

/// An audio input's input volume through Core Audio's virtual main volume
/// of its input scope (`kAudioHardwareServiceDeviceProperty_VirtualMainVolume`),
/// which moves the device's own volume controls together.
final class CoreAudioInputVolume: InputVolumeControl, @unchecked Sendable {
    static let address = AudioObjectPropertyAddress(
        mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume, mScope: kAudioDevicePropertyScopeInput,
        mElement: kAudioObjectPropertyElementMain)

    let device: AudioObjectID
    let name: String
    let isSettable: Bool
    private let property: CoreAudioProperty
    private let lock = NSLock()
    /// Guarded by `lock`.
    private var listener: AudioObjectPropertyListenerBlock?

    /// Nil when the device has no input volume.
    init?(device: AudioObjectID, name: String, property: CoreAudioProperty = .system) {
        guard property.has(device, Self.address) else { return nil }
        self.device = device
        self.name = name
        self.property = property
        isSettable = property.isSettable(device, Self.address)
    }

    /// The input volume of the audio input with this Core Audio UID; nil
    /// when the input is gone or has none.
    convenience init?(uid: String, name: String) {
        guard let device = audioDevice(uid: uid) else { return nil }
        self.init(device: device, name: name)
    }

    func read() -> Double? {
        let (status, value) = property.read(device, Self.address)
        return status == noErr ? Double(value) : nil
    }

    func set(_ volume: Double) throws(InputVolumeError) {
        let status = property.write(device, Self.address, Float32(min(1, max(0, volume))))
        guard status == noErr else {
            throw InputVolumeError("Core Audio refused the input volume of \(name) (error \(ErrorDetail.codeText(Int(status))))")
        }
    }

    func watch(_ changed: @escaping @Sendable () -> Void) throws(InputVolumeError) {
        let block: AudioObjectPropertyListenerBlock = { _, _ in changed() }
        let status = property.addListener(device, Self.address, block)
        guard status == noErr else {
            throw InputVolumeError("changes of the input volume of \(name) cannot be followed (Core Audio error \(ErrorDetail.codeText(Int(status))))")
        }
        lock.withLock { listener = block }
    }

    func cancel() {
        guard let block = lock.withLock({ () -> AudioObjectPropertyListenerBlock? in
            defer { listener = nil }
            return listener
        }) else { return }
        _ = property.removeListener(device, Self.address, block)
    }
}

/// The device with this Core Audio UID, nil when there is none.
private func audioDevice(uid: String) -> AudioObjectID? {
    var address = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyTranslateUIDToDevice, mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain)
    var device = AudioObjectID(kAudioObjectUnknown)
    var size = UInt32(MemoryLayout<AudioObjectID>.size)
    let status = withUnsafePointer(to: uid as CFString) { qualifier in
        AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, UInt32(MemoryLayout<CFString>.size), qualifier, &size, &device)
    }
    return status == noErr && device != kAudioObjectUnknown ? device : nil
}
