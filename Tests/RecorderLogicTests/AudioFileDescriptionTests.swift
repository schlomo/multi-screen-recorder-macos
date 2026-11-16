import Foundation
import Testing
@testable import RecorderLogic

@Suite struct AudioFileDescriptionTests {

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

    private let started = "2026-11-12T14:03:05.120+01:00"
    private let app = "Multi Screen Recorder 0.20261115.3 (a1b2c3d)"

    @Test func anAudioInputHasAMonoTrackPerChannelItsReelNameAndMetadata() {
        let description = AudioFileDescription(
            source: .audioInput(name: "Razer Seiren V3 Mini", coreAudioUID: "AppleUSBAudioEngine:Razer:1", channelCount: 2),
            recordingStarted: started, app: app)
        #expect(description.channelsPerTrack == 1)
        #expect(description.bitRatePerTrack == 128_000)
        #expect(description.channels == .mono(2))
        #expect(description.trackNames == ["Microphone: Razer Seiren V3 Mini, channel 1", "Microphone: Razer Seiren V3 Mini, channel 2"])
        #expect(description.reelName == "Microphone - Razer Seiren V3 Mini")
        let prefix = "org.schapiro.multiscreenrecorder."
        #expect(description.items.map { "\($0.key)=\($0.value)" } == [
            prefix + "audioSource=Razer Seiren V3 Mini",
            prefix + "audioSourceUID=AppleUSBAudioEngine:Razer:1",
            prefix + "channels=2",
            prefix + "recordingStarted=\(started)",
            prefix + "app=\(app)",
            "com.apple.quicktime.software=\(app)",
            "com.apple.proapps.reel=Microphone - Razer Seiren V3 Mini",
            "com.apple.proapps.cameraName=Microphone - Razer Seiren V3 Mini",
        ])
    }

    @Test func theSystemAudioHasOneStereoTrack() {
        let description = AudioFileDescription(source: .systemAudio, recordingStarted: started, app: app)
        #expect(description.channelsPerTrack == 2)
        #expect(description.channelCount == 2)
        #expect(description.channels == .stereo)
        #expect(description.bitRatePerTrack == 192_000)
        #expect(description.trackNames == ["System audio"])
        #expect(description.reelName == "System audio")
        #expect(!description.items.contains { $0.key.hasSuffix("audioSourceUID") })
        #expect(description.items.contains { $0.key.hasSuffix(".channels") && $0.value == "stereo" })
    }
}
