import AudioToolbox
import CoreAudio
import Foundation
import Synchronization
import Testing
@testable import RecorderCore

/// An audio input's input volume against a stand-in for Core Audio: no
/// test reads or sets a real device's volume (D48, D69).
@Suite struct InputVolumeTests {
    final class StandInDevice: @unchecked Sendable {
        struct State {
            var has = true
            var isSettable = true
            var volume: Float32 = 0.5
            var status: OSStatus = noErr
            var addresses: [AudioObjectPropertyAddress] = []
            var written: [Float32] = []
            var removed = 0
        }

        let state = Mutex(State())
        private let lock = NSLock()
        /// Guarded by `lock`: a listener block is not `Sendable`.
        private var listenerBlock: AudioObjectPropertyListenerBlock?
        var listener: AudioObjectPropertyListenerBlock? { lock.withLock { listenerBlock } }

        var property: CoreAudioProperty {
            CoreAudioProperty(
                has: { _, address in self.state.withLock { $0.addresses.append(address); return $0.has } },
                isSettable: { _, address in self.state.withLock { $0.addresses.append(address); return $0.isSettable } },
                read: { _, address in
                    self.state.withLock { state in
                        state.addresses.append(address)
                        return (state.status, state.volume)
                    }
                },
                write: { _, address, value in
                    self.state.withLock { state in
                        state.addresses.append(address)
                        guard state.status == noErr else { return state.status }
                        state.written.append(value)
                        state.volume = value
                        return noErr
                    }
                },
                addListener: { _, address, block in
                    self.lock.withLock { self.listenerBlock = block }
                    return self.state.withLock { state in
                        state.addresses.append(address)
                        return state.status
                    }
                },
                removeListener: { _, _, _ in self.state.withLock { $0.removed += 1; return noErr } })
        }
    }

    private let device = StandInDevice()

    private func volume() throws -> CoreAudioInputVolume {
        try #require(CoreAudioInputVolume(device: 42, name: "Razer Seiren V3 Mini", property: device.property))
    }

    @Test func itIsTheVirtualMainVolumeOfTheInputScope() throws {
        let volume = try volume()
        try volume.set(0.25)
        _ = volume.read()
        let addresses = device.state.withLock { $0.addresses }
        #expect(!addresses.isEmpty)
        for address in addresses {
            #expect(address.mSelector == kAudioHardwareServiceDeviceProperty_VirtualMainVolume)
            #expect(address.mScope == kAudioDevicePropertyScopeInput)
            #expect(address.mElement == kAudioObjectPropertyElementMain)
        }
    }

    @Test func anInputWithoutAnInputVolumeHasNone() {
        device.state.withLock { $0.has = false }
        #expect(CoreAudioInputVolume(device: 42, name: "HDMI", property: device.property) == nil)
    }

    @Test func oneThatCannotBeSetSaysSo() throws {
        device.state.withLock { $0.isSettable = false }
        #expect(try volume().isSettable == false)
    }

    @Test func setWritesTheVolumeFrom0To1() throws {
        let volume = try volume()
        try volume.set(0.75)
        try volume.set(1.5)
        try volume.set(-1)
        #expect(device.state.withLock { $0.written } == [0.75, 1, 0])
        #expect(volume.read() == 0)
    }

    @Test func aVolumeCoreAudioRefusesIsAnError() throws {
        let volume = try volume()
        device.state.withLock { $0.status = kAudioHardwareUnsupportedOperationError }
        #expect(throws: InputVolumeError.self) { try volume.set(0.5) }
        #expect(volume.read() == nil)
        do {
            try volume.set(0.5)
        } catch {
            #expect(error.description.contains("Razer Seiren V3 Mini"))
            #expect(error.description.contains("'unop'"))
        }
    }

    @Test func aWatchCallsBackForEveryChangeUntilItIsCancelled() throws {
        let volume = try volume()
        let calls = Mutex(0)
        try volume.watch { calls.withLock { $0 += 1 } }
        let listener = try #require(device.listener)
        var address = CoreAudioInputVolume.address
        listener(1, &address)
        #expect(calls.withLock { $0 } == 1)
        volume.cancel()
        volume.cancel()
        #expect(device.state.withLock { $0.removed } == 1)
    }

    @Test func aWatchCoreAudioRefusesIsAnError() throws {
        let volume = try volume()
        device.state.withLock { $0.status = kAudioHardwareIllegalOperationError }
        #expect(throws: InputVolumeError.self) { try volume.watch {} }
    }
}
