import Testing
@testable import RecorderLogic

@Suite struct DiskEstimateTests {
    private let fullHD = FrameSize(width: 1920, height: 1080)

    private func settings(_ edit: (inout Settings) -> Void = { _ in }) -> Settings {
        var settings = Settings.manual
        edit(&settings)
        return settings
    }

    /// No microphone and no system audio: a screen file is its video alone.
    private var silent: Settings {
        settings {
            $0.audioMode = .none
            $0.systemAudio = false
        }
    }

    @Test func aScreenFileWithoutGuideTracksIsOneGigabytePerHourAt1080p() {
        #expect(DiskEstimate.screenFileBytesPerHour(frameSize: fullHD, settings: silent) == 1_000_000_000)
    }

    @Test func theVideoScalesByThePixelCount() {
        #expect(DiskEstimate.screenFileBytesPerHour(frameSize: FrameSize(width: 3840, height: 2160), settings: silent)
            == 4_000_000_000)
        #expect(DiskEstimate.screenFileBytesPerHour(frameSize: FrameSize(width: 960, height: 540), settings: silent)
            == 250_000_000)
    }

    @Test func theGuideTracksFollowTheSettingsAlone() {
        #expect(GuideTrack.tracks(for: settings()) == [.audioInputs, .systemAudio])
        #expect(GuideTrack.tracks(for: settings { $0.audioMode = .none }) == [.systemAudio])
        #expect(GuideTrack.tracks(for: settings { $0.systemAudio = false }) == [.audioInputs])
        #expect(GuideTrack.tracks(for: silent).isEmpty)
        #expect(GuideTrack.audioInputs.name == "Audio inputs")
        #expect(GuideTrack.systemAudio.name == "System audio")
    }

    @Test func theGuideTracksAdd64And96KilobitsPerSecond() {
        #expect(DiskEstimate.screenFileBytesPerHour(frameSize: fullHD, settings: settings())
            == 1_000_000_000 + 28_800_000 + 43_200_000)
        #expect(DiskEstimate.screenFileBytesPerHour(frameSize: fullHD, settings: settings { $0.audioMode = .none })
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
            settings: settings(), screens: DesignExample.screens, audioInputs: DesignExample.audioInputs))
        let retina = 1670.0 * 1080 / (1920 * 1080) * 1_000_000_000 + 72_000_000
        let lg = 1_000_000_000.0 + 72_000_000
        #expect(abs(total - (retina + lg + 57_600_000 + 86_400_000)) < 1)
    }

    @Test func theTotalLeavesOutWhatIsNotRecorded() {
        #expect(DiskEstimate.bytesPerHour(
            settings: silent, screens: DesignExample.screens, audioInputs: DesignExample.audioInputs)
            == DiskEstimate.bytesPerHour(settings: silent, screens: DesignExample.screens, audioInputs: []))
    }

    @Test func aRecordedInputWhoseChannelsCannotBeReadLeavesTheTotalUnknown() {
        let unreadable = AudioInputInfo(name: "X", channelCount: .failure(DeviceReadError("no format")), isDefault: true, uid: "X")
        #expect(DiskEstimate.bytesPerHour(settings: settings(), screens: DesignExample.screens, audioInputs: [unreadable]) == nil)
        #expect(DiskEstimate.bytesPerHour(settings: silent, screens: DesignExample.screens, audioInputs: [unreadable]) != nil)
    }

    @Test func noScreensNeedNoSpaceForVideo() {
        #expect(DiskEstimate.bytesPerHour(settings: silent, screens: [], audioInputs: []) == 0)
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

    /// The status window's sizes: below 1 GB in whole MB, from there as GB.
    @Test(arguments: [
        (0.0, "0 MB"),
        (40_000_000.0, "40 MB"),
        (350_400_000.0, "350 MB"),
        (999_499_999.0, "999 MB"),
        (999_500_000.0, "1.0 GB"),
        (1_260_000_000.0, "1.3 GB"),
    ])
    func sizesBelowOneGigabyteAreMegabytes(bytes: Double, text: String) {
        #expect(DiskEstimate.megabytesOrGigabytes(bytes) == text)
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
                        Encoding.audioInputsGuideTrackBitRate, Encoding.systemAudioGuideTrackBitRate] {
            #expect(design.contains("\(bitRate / 1000) kbit/s"), "\(bitRate)")
        }
    }
}

@Suite struct DiskEstimateMirroringTests {
    /// A screen that mirrors another is not recorded, so it needs no space.
    @Test func aMirroringScreenNeedsNoSpace() {
        var mirror = DesignExample.screens[1]
        mirror.isMirroring = true
        #expect(DiskEstimate.bytesPerHour(settings: .defaults, screens: [DesignExample.screens[0], mirror], audioInputs: [])
            == DiskEstimate.bytesPerHour(settings: .defaults, screens: [DesignExample.screens[0]], audioInputs: []))
    }
}
