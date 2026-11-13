import CoreAudio
import RecorderLogic
import Testing
@testable import RecorderCore

@Suite struct AudioInputTests {
    @Test func onlyDevicesWithInputChannelsAreAudioInputsAndTheDefaultIsMarked() {
        let readings = [
            AudioDeviceReading(id: 41, name: "Speakers", inputChannelCount: nil),
            AudioDeviceReading(id: 42, name: "Desk Microphone", inputChannelCount: .success(1)),
            AudioDeviceReading(id: 43, name: "Interface", inputChannelCount: .success(2)),
        ]
        #expect(audioInputs(from: readings, defaultInput: 43) == [
            AudioInputInfo(name: "Desk Microphone", channelCount: 1, isDefault: false),
            AudioInputInfo(name: "Interface", channelCount: 2, isDefault: true),
        ])
    }

    @Test func anInputWhoseChannelsCannotBeReadKeepsItsReason() {
        let error = DeviceReadError("no channels")
        let readings = [AudioDeviceReading(id: 7, name: "Broken", inputChannelCount: .failure(error))]
        #expect(audioInputs(from: readings, defaultInput: 7) == [
            AudioInputInfo(name: "Broken", channelCount: .failure(error), isDefault: true),
        ])
    }

    @Test func withoutADefaultInputNoneIsMarked() {
        let readings = [AudioDeviceReading(id: 42, name: "Desk Microphone", inputChannelCount: .success(1))]
        #expect(audioInputs(from: readings, defaultInput: AudioObjectID(kAudioObjectUnknown)) == [
            AudioInputInfo(name: "Desk Microphone", channelCount: 1, isDefault: false),
        ])
    }

    /// Reads this Mac's audio devices, which needs no permission and shows
    /// no prompt: with or without an audio input, the read succeeds and
    /// every input has a name and channels.
    @Test func thisMacsAudioInputsCanBeRead() throws {
        let inputs = try currentAudioInputs()
        #expect(inputs.filter(\.isDefault).count <= 1)
        for input in inputs {
            #expect(!input.name.isEmpty)
            #expect(try input.channelCount.get() > 0)
        }
    }

    @Test func changesOfThisMacsAudioDevicesCanBeWatched() throws {
        try watchAudioInputs {}
    }
}
