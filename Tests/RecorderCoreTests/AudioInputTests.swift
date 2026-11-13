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
        defaultInput: () throws(DeviceReadError) -> AudioObjectID = { AudioObjectID(kAudioObjectUnknown) }
    ) throws -> [AudioInputInfo] {
        try audioInputs(
            devices: channels.indices.map { AudioObjectID($0 + 1) },
            inputChannels: { channels[Int($0) - 1] }, name: name, defaultInput: defaultInput)
    }

    @Test func onlyDevicesWithInputChannelsAreAudioInputsAndTheDefaultIsMarked() throws {
        #expect(try inputs([.count(0), .count(1), .count(2)], defaultInput: { 3 }) == [
            AudioInputInfo(name: "Device 2", channelCount: 1, isDefault: false),
            AudioInputInfo(name: "Device 3", channelCount: 2, isDefault: true),
        ])
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
    @Test func aListenerForChangesOfThisMacsAudioDevicesCanBeRegistered() throws {
        try watchAudioInputs {}
    }
}
