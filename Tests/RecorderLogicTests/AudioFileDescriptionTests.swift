import Foundation
import Testing
@testable import RecorderLogic

@Suite struct AudioFileDescriptionTests {
    private let berlin = TimeZone(identifier: "Europe/Berlin")!
    private let start = Date(timeIntervalSince1970: 1_794_488_585.12) // 2026-11-12 14:03:05.120 in Berlin

    @Test func slashesAndColonsInADeviceNameBecomeDashes() {
        var names = AudioInputNames()
        #expect(names.name(coreAudioUID: "a", deviceName: "Mic 1/2: Studio") == "Mic 1-2- Studio")
    }

    @Test func twoAudioInputsWithTheSameNameAreNumberedInOrderOfAppearance() {
        var names = AudioInputNames()
        #expect(names.name(coreAudioUID: "a", deviceName: "USB Audio") == "USB Audio")
        #expect(names.name(coreAudioUID: "b", deviceName: "USB Audio") == "USB Audio (2)")
        #expect(names.name(coreAudioUID: "c", deviceName: "USB Audio") == "USB Audio (3)")
        #expect(names.name(coreAudioUID: "a", deviceName: "USB Audio") == "USB Audio")
        // Names that differ only in `/` and `:` are the same in a file name.
        #expect(names.name(coreAudioUID: "d", deviceName: "A/B") == "A-B")
        #expect(names.name(coreAudioUID: "e", deviceName: "A:B") == "A-B (2)")
    }

    @Test func anAudioInputHasAMonoTrackPerChannelItsReelNameAndMetadata() {
        let description = AudioFileDescription(
            source: .audioInput(name: "Razer Seiren V3 Mini", coreAudioUID: "AppleUSBAudioEngine:Razer:1", channelCount: 2),
            recordingStart: start, timeZone: berlin, appVersion: "0.20261115.3")
        #expect(description.channelsPerTrack == 1)
        #expect(description.bitRatePerTrack == 128_000)
        #expect(description.trackNames == ["Microphone: Razer Seiren V3 Mini, channel 1", "Microphone: Razer Seiren V3 Mini, channel 2"])
        #expect(description.reelName == "Microphone - Razer Seiren V3 Mini")
        let prefix = "org.schapiro.multiscreenrecorder."
        #expect(description.metadata == [
            .init(key: prefix + "sourceName", value: "Razer Seiren V3 Mini"),
            .init(key: prefix + "coreAudioUID", value: "AppleUSBAudioEngine:Razer:1"),
            .init(key: prefix + "channelCount", value: "2"),
            .init(key: prefix + "recordingStart", value: "2026-11-12T14:03:05.120+01:00"),
            .init(key: prefix + "appVersion", value: "0.20261115.3"),
        ])
    }

    @Test func theSystemAudioHasOneStereoTrack() {
        let description = AudioFileDescription(source: .systemAudio, recordingStart: start, timeZone: berlin, appVersion: "0.20261115.3")
        #expect(description.channelsPerTrack == 2)
        #expect(description.channelCount == 2)
        #expect(description.bitRatePerTrack == 192_000)
        #expect(description.trackNames == ["System audio"])
        #expect(description.reelName == "System audio")
        #expect(!description.metadata.contains { $0.key.hasSuffix("coreAudioUID") })
    }
}
