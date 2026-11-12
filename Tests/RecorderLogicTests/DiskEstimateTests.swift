import Testing
@testable import RecorderLogic

@Suite struct DiskEstimateTests {
    private let fullHD = FrameSize(width: 1920, height: 1080)

    private func settings(_ edit: (inout Settings) -> Void = { _ in }) -> Settings {
        var settings = Settings.defaults
        edit(&settings)
        return settings
    }

    /// No microphone and no system audio: a display file is its video alone.
    private var silent: Settings {
        settings {
            $0.audioMode = .none
            $0.systemAudio = false
        }
    }

    @Test func aDisplayFileWithoutGuideTracksIsOneGigabytePerHourAt1080p() {
        #expect(DiskEstimate.displayFileBytesPerHour(frameSize: fullHD, settings: silent) == 1_000_000_000)
    }

    @Test func theVideoScalesByThePixelCount() {
        #expect(DiskEstimate.displayFileBytesPerHour(frameSize: FrameSize(width: 3840, height: 2160), settings: silent)
            == 4_000_000_000)
        #expect(DiskEstimate.displayFileBytesPerHour(frameSize: FrameSize(width: 960, height: 540), settings: silent)
            == 250_000_000)
    }

    @Test func theGuideTracksFollowTheSettingsAlone() {
        #expect(GuideTrack.tracks(for: settings()) == [.microphones, .systemAudio])
        #expect(GuideTrack.tracks(for: settings { $0.audioMode = .none }) == [.systemAudio])
        #expect(GuideTrack.tracks(for: settings { $0.systemAudio = false }) == [.microphones])
        #expect(GuideTrack.tracks(for: silent).isEmpty)
        #expect(GuideTrack.microphones.name == "Microphones")
        #expect(GuideTrack.systemAudio.name == "System audio")
    }

    @Test func theGuideTracksAdd64And96KilobitsPerSecond() {
        #expect(DiskEstimate.displayFileBytesPerHour(frameSize: fullHD, settings: settings())
            == 1_000_000_000 + 28_800_000 + 43_200_000)
        #expect(DiskEstimate.displayFileBytesPerHour(frameSize: fullHD, settings: settings { $0.audioMode = .none })
            == 1_000_000_000 + 43_200_000)
    }

    @Test func anAudioInputsFileHas128KilobitsPerSecondPerChannel() {
        #expect(DiskEstimate.audioInputFileBytesPerHour(channelCount: 1) == 57_600_000)
        #expect(DiskEstimate.audioInputFileBytesPerHour(channelCount: 2) == 115_200_000)
    }

    @Test func theSystemAudioFileHas192KilobitsPerSecond() {
        #expect(DiskEstimate.systemAudioFileBytesPerHour == 86_400_000)
    }

    @Test func theTotalCountsEveryFileARecordingWrites() throws {
        let total = try #require(DiskEstimate.bytesPerHour(
            settings: settings(), displays: DesignExample.displays, audioInputs: DesignExample.audioInputs))
        let retina = 1670.0 * 1080 / (1920 * 1080) * 1_000_000_000 + 72_000_000
        let lg = 1_000_000_000.0 + 72_000_000
        #expect(abs(total - (retina + lg + 57_600_000 + 86_400_000)) < 1)
    }

    @Test func theTotalLeavesOutWhatIsNotRecorded() {
        #expect(DiskEstimate.bytesPerHour(
            settings: silent, displays: DesignExample.displays, audioInputs: DesignExample.audioInputs)
            == DiskEstimate.bytesPerHour(settings: silent, displays: DesignExample.displays, audioInputs: []))
    }

    @Test func aRecordedInputWhoseChannelsCannotBeReadLeavesTheTotalUnknown() {
        let unreadable = AudioInputInfo(name: "X", channelCount: .failure(DeviceReadError("no format")), isDefault: true)
        #expect(DiskEstimate.bytesPerHour(settings: settings(), displays: DesignExample.displays, audioInputs: [unreadable]) == nil)
        #expect(DiskEstimate.bytesPerHour(settings: silent, displays: DesignExample.displays, audioInputs: [unreadable]) != nil)
    }

    @Test func noDisplaysNeedNoSpaceForVideo() {
        #expect(DiskEstimate.bytesPerHour(settings: silent, displays: [], audioInputs: []) == 0)
    }

    @Test(arguments: [
        (3_100_000_000.0, "3.1 GB"),
        (4_000_000_000.0, "4.0 GB"),
        (3_739_500_000.0, "3.7 GB"),
        (512_000_000_000.0, "512.0 GB"),
        (0.0, "0.0 GB"),
    ])
    func gigabytesAreDecimalWithOneDigit(bytes: Double, text: String) {
        #expect(DiskEstimate.gigabytes(bytes) == text)
    }

    @Test(arguments: [
        (1_072_000_000.0, "1.1"),
        (57_600_000.0, "0.1"),
        (50_000_000.0, "0.1"),
        (49_999_999.0, "<0.1"),
        (28_800_000.0, "<0.1"),
    ])
    func gigabytesPerHourHaveOneDigitAndAFloor(bytesPerHour: Double, text: String) {
        #expect(DiskEstimate.gigabytesPerHour(bytesPerHour) == text)
    }

    @Test func theDesignStatesTheEncodingRates() throws {
        let design = try repositoryFile("docs/design/recorder.md")
        for bitRate in [Encoding.audioInputTrackBitRate, Encoding.systemAudioTrackBitRate,
                        Encoding.microphonesGuideTrackBitRate, Encoding.systemAudioGuideTrackBitRate] {
            #expect(design.contains("\(bitRate / 1000) kbit/s"), "\(bitRate)")
        }
    }
}
