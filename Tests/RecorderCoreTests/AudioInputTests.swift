import CoreAudio
import RecorderLogic
import Testing
@testable import RecorderCore

@Suite struct AudioInputTests {
    @Test func theDefaultInputIsMarked() {
        let readings = [
            AudioInputReading(id: 42, name: "Desk Microphone", channelCount: .success(1)),
            AudioInputReading(id: 43, name: "Interface", channelCount: .success(2)),
        ]
        #expect(audioInputs(from: readings, defaultInput: 43) == [
            AudioInputInfo(name: "Desk Microphone", channelCount: 1, isDefault: false),
            AudioInputInfo(name: "Interface", channelCount: 2, isDefault: true),
        ])
    }

    @Test func anInputWhoseChannelsCannotBeReadKeepsItsReason() {
        let error = DeviceReadError("no channels")
        let readings = [AudioInputReading(id: 7, name: "Broken", channelCount: .failure(error))]
        #expect(audioInputs(from: readings, defaultInput: 7) == [
            AudioInputInfo(name: "Broken", channelCount: .failure(error), isDefault: true),
        ])
    }

    @Test func withoutADefaultInputNoneIsMarked() {
        let readings = [AudioInputReading(id: 42, name: "Desk Microphone", channelCount: .success(1))]
        #expect(audioInputs(from: readings, defaultInput: AudioObjectID(kAudioObjectUnknown)) == [
            AudioInputInfo(name: "Desk Microphone", channelCount: 1, isDefault: false),
        ])
    }

    /// Reads this Mac's audio devices, which needs no permission and shows
    /// no prompt. What the Mac has connected decides the inputs, so only
    /// what holds for any set is asserted.
    @Test func thisMacsAudioInputsAreListedWithAtMostOneDefault() throws {
        let inputs = try currentAudioInputs()
        #expect(inputs.filter(\.isDefault).count <= 1)
    }

    /// Registers the listener; that a change calls it is seen only on a Mac
    /// where a device is plugged in or out.
    @Test func aListenerForChangesOfThisMacsAudioDevicesCanBeRegistered() throws {
        try watchAudioInputs {}
    }
}
