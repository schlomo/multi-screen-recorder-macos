import Foundation
import Testing
@testable import RecorderLogic

@Suite struct AudioFileDescriptionTests {

    @Test func eachKindHasItsLabel() {
        #expect(SourceLabel.screen(2, name: "LG HDR 4K") == "Screen 2 - LG HDR 4K")
        #expect(SourceLabel.audioInput(3, name: "USB Audio") == "Audio 3 - USB Audio")
        #expect(SourceLabel.systemAudio == "Audio 0 - System")
    }

    @Test func aSourceCellShowsTheLabelOrWithoutANumberTheNameAlone() {
        #expect(SourceCell.screen(1, name: "DELL P3421W").text == "Screen 1 - DELL P3421W")
        #expect(SourceCell.screen(nil, name: "LG").text == "LG")
        #expect(SourceCell.audioInput(2, name: "AirPods").text == "Audio 2 - AirPods")
        #expect(SourceCell.audioInput(nil, name: "AirPods").text == "AirPods")
        #expect(SourceCell.systemAudio(isRecorded: true).text == "Audio 0 - System")
        #expect(SourceCell.systemAudio(isRecorded: true).name == "System")
        #expect(SourceCell.systemAudio(isRecorded: false).text == "System audio")
        #expect(SourceCell.systemAudio(isRecorded: false).number == nil)
    }

    private let started = "2026-11-12T14:03:05.120+01:00"
    private let app = "Multi Screen Recorder 0.20261115.3 (a1b2c3d)"

    @Test func anAudioInputHasAMonoTrackPerChannelItsReelNameAndMetadata() {
        let description = AudioFileDescription(
            source: .audioInput(number: 2, name: "Razer Seiren V3 Mini", coreAudioUID: "AppleUSBAudioEngine:Razer:1", channelCount: 2),
            recordingStarted: started, app: app)
        #expect(description.channelsPerTrack == 1)
        #expect(description.bitRatePerTrack == 128_000)
        #expect(description.channels == .mono(2))
        #expect(description.trackNames == ["Audio 2 - Razer Seiren V3 Mini, channel 1", "Audio 2 - Razer Seiren V3 Mini, channel 2"])
        #expect(description.reelName == "Audio 2 - Razer Seiren V3 Mini")
        let prefix = "org.schapiro.multiscreenrecorder."
        #expect(description.items.map { "\($0.key)=\($0.value)" } == [
            prefix + "audioSource=Razer Seiren V3 Mini",
            prefix + "audioSourceUID=AppleUSBAudioEngine:Razer:1",
            prefix + "channels=2",
            prefix + "recordingStarted=\(started)",
            prefix + "app=\(app)",
            "com.apple.quicktime.software=\(app)",
            "com.apple.proapps.reel=Audio 2 - Razer Seiren V3 Mini",
            "com.apple.proapps.cameraName=Audio 2 - Razer Seiren V3 Mini",
        ])
    }

    @Test func theSystemAudioHasOneStereoTrack() {
        let description = AudioFileDescription(source: .systemAudio, recordingStarted: started, app: app)
        #expect(description.channelsPerTrack == 2)
        #expect(description.channelCount == 2)
        #expect(description.channels == .stereo)
        #expect(description.bitRatePerTrack == 192_000)
        #expect(description.trackNames == ["Audio 0 - System"])
        #expect(description.reelName == "Audio 0 - System")
        #expect(!description.items.contains { $0.key.hasSuffix("audioSourceUID") })
        #expect(description.items.contains { $0.key.hasSuffix(".channels") && $0.value == "stereo" })
    }
}
