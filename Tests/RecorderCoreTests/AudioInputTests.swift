import CoreAudio
import RecorderLogic
import Testing
@testable import RecorderCore

@Suite struct AudioInputTests {
    private static let cannotBeAsked = DeviceReadError("asked although it must not be")

    /// Lists devices 1, 2, … with the given input channels, named "Device 1", "Device 2", …
    private func inputs(
        _ channels: [InputChannels],
        name: (AudioObjectID) throws(DeviceReadError) -> String? = { "Device \($0)" },
        transport: (AudioObjectID) -> AudioTransport = { _ in .builtIn },
        defaultInput: () throws(DeviceReadError) -> AudioObjectID = { AudioObjectID(kAudioObjectUnknown) }
    ) throws -> [AudioInputInfo] {
        try audioInputs(
            devices: channels.indices.map { AudioObjectID($0 + 1) },
            inputChannels: { channels[Int($0) - 1] }, name: name, transport: transport, uid: { _ in nil },
            defaultInput: defaultInput)
    }

    @Test func onlyDevicesWithInputChannelsAreAudioInputsAndTheDefaultIsMarked() throws {
        #expect(try inputs([.count(0), .count(1), .count(2)], defaultInput: { 3 }) == [
            AudioInputInfo(name: "Device 2", channelCount: 1, isDefault: false),
            AudioInputInfo(name: "Device 3", channelCount: 2, isDefault: true),
        ])
    }

    @Test func eachInputCarriesItsCoreAudioUID() throws {
        let listed = try audioInputs(
            devices: [1, 2], inputChannels: { _ in .count(1) }, name: { "Device \($0)" }, transport: { _ in .usb },
            uid: { $0 == 1 ? "AppleUSBAudioEngine:1" : nil }, defaultInput: { 1 })
        #expect(listed.map(\.uid) == ["AppleUSBAudioEngine:1", nil])
    }

    @Test func eachInputKeepsItsTransport() throws {
        let listed = try inputs([.count(1), .count(0), .count(2)], transport: { $0 == 1 ? .usb : .bluetooth })
        #expect(listed.map(\.transport) == [.usb, .bluetooth])
    }

    @Test func aDeviceWithoutInputChannelsIsNotAskedForItsTransport() throws {
        let listed = try inputs([.count(0), .count(1)], transport: { id in
            #expect(id == 2, "asked for the transport of a device without input channels")
            return .usb
        })
        #expect(listed.count == 1)
    }

    @Test func withoutADefaultInputNoneIsMarked() throws {
        #expect(try inputs([.count(1)]) == [AudioInputInfo(name: "Device 1", channelCount: 1, isDefault: false)])
    }

    @Test func aDeviceWithoutInputChannelsIsNotAskedForItsName() throws {
        let listed = try inputs([.count(0), .count(1)], name: { id throws(DeviceReadError) in
            guard id == 2 else { throw Self.cannotBeAsked }
            return "Desk Microphone"
        })
        #expect(listed.map(\.name) == ["Desk Microphone"])
    }

    @Test func withoutAnAudioInputTheDefaultIsNotAskedFor() throws {
        #expect(try inputs([.count(0), .gone], defaultInput: { () throws(DeviceReadError) in throw Self.cannotBeAsked }) == [])
    }

    @Test func aDeviceThatDisappearedIsLeftOut() throws {
        let listed = try inputs([.gone, .count(1), .count(1)], name: { $0 == 2 ? nil : "Device \($0)" })
        #expect(listed.map(\.name) == ["Device 3"])
    }

    @Test func anInputWhoseChannelsCannotBeReadKeepsItsReason() throws {
        #expect(try inputs([.unreadable("Core Audio error 7")], defaultInput: { 1 }) == [
            AudioInputInfo(
                name: "Device 1",
                channelCount: .failure(DeviceReadError("the audio device Device 1 does not report its channels (Core Audio error 7)")),
                isDefault: true),
        ])
    }

    @Test func anAudioInputWithoutANameStopsTheListing() {
        #expect(throws: Self.cannotBeAsked) {
            try inputs([.count(1)], name: { _ throws(DeviceReadError) in throw Self.cannotBeAsked })
        }
    }

    @Test func aDefaultInputThatCannotBeReadStopsTheListing() {
        #expect(throws: Self.cannotBeAsked) {
            try inputs([.count(1)], defaultInput: { () throws(DeviceReadError) in throw Self.cannotBeAsked })
        }
    }

    @Test(arguments: [
        (kAudioDeviceTransportTypeBuiltIn, AudioTransport.builtIn),
        (kAudioDeviceTransportTypeUSB, .usb),
        (kAudioDeviceTransportTypeFireWire, .fireWire),
        (kAudioDeviceTransportTypePCI, .pci),
        (kAudioDeviceTransportTypeThunderbolt, .thunderbolt),
        (kAudioDeviceTransportTypeHDMI, .hdmi),
        (kAudioDeviceTransportTypeDisplayPort, .displayPort),
        (kAudioDeviceTransportTypeBluetooth, .bluetooth),
        (kAudioDeviceTransportTypeBluetoothLE, .bluetoothLE),
        (kAudioDeviceTransportTypeVirtual, .virtual),
        (kAudioDeviceTransportTypeAggregate, .aggregate),
        (kAudioDeviceTransportTypeAutoAggregate, .aggregate),
        (kAudioDeviceTransportTypeAirPlay, .airPlay),
        (kAudioDeviceTransportTypeContinuityCaptureWired, .continuityCapture),
        (kAudioDeviceTransportTypeContinuityCaptureWireless, .continuityCapture),
        (kAudioDeviceTransportTypeAVB, .unknown),
        (kAudioDeviceTransportTypeUnknown, .unknown),
        (0x1234_5678, .unknown),
    ])
    func coreAudioTransportTypesAreClassified(value: UInt32, transport: AudioTransport) {
        #expect(audioTransport(coreAudioValue: value) == transport)
    }

    @Test func aTransportThatCannotBeReadIsUnreadableAndNotWired() {
        #expect(audioTransport(coreAudioValue: nil) == .unreadable)
        #expect(!audioTransport(coreAudioValue: nil).isWired)
    }

    @Test(arguments: [
        (kAudioDeviceTransportTypeBuiltIn, true), (kAudioDeviceTransportTypeUSB, true),
        (kAudioDeviceTransportTypeFireWire, true), (kAudioDeviceTransportTypePCI, true),
        (kAudioDeviceTransportTypeThunderbolt, true), (kAudioDeviceTransportTypeHDMI, true),
        (kAudioDeviceTransportTypeDisplayPort, true),
        (kAudioDeviceTransportTypeBluetooth, false), (kAudioDeviceTransportTypeBluetoothLE, false),
        (kAudioDeviceTransportTypeVirtual, false), (kAudioDeviceTransportTypeAggregate, false),
        (kAudioDeviceTransportTypeAirPlay, false), (kAudioDeviceTransportTypeContinuityCaptureWired, false),
        (kAudioDeviceTransportTypeContinuityCaptureWireless, false), (kAudioDeviceTransportTypeUnknown, false),
    ])
    func wiredIsClassifiedPerCoreAudioTransportType(value: UInt32, isWired: Bool) {
        #expect(audioTransport(coreAudioValue: value).isWired == isWired)
    }

    /// Reads this Mac's audio devices, which needs no permission and shows
    /// no prompt. What is connected decides the inputs, so only what holds
    /// for any Mac whose audio devices can be read is asserted.
    @Test func thisMacsAudioInputsAreListed() throws {
        let inputs = try currentAudioInputs()
        #expect(inputs.filter(\.isDefault).count <= 1)
        for input in inputs {
            #expect(!input.name.isEmpty)
            if case .success(let count) = input.channelCount { #expect(count > 0) }
        }
    }

    /// Registers the listener; that a change calls it is seen only on a Mac
    /// where a device is plugged in or out.
    @Test func aListenerForChangesOfThisMacsAudioDevicesCanBeRegisteredAndCancelled() throws {
        let watch = try AudioInputWatch {}
        watch.cancel()
    }
}
