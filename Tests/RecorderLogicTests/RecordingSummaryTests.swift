import Testing
@testable import RecorderLogic

@Suite struct RecordingSummaryTests {
    private func summary(
        _ edit: (inout Settings) -> Void = { _ in },
        displays: Result<[DisplayInfo], DeviceReadError> = .success(DesignExample.displays),
        defaultMicrophone: String? = "MacBook Pro Microphone"
    ) -> [String] {
        var settings = Settings.defaults
        edit(&settings)
        return RecordingSummary.lines(settings: settings, displays: displays, defaultMicrophone: defaultMicrophone)
    }

    @Test func theDefaultsWithTheDesignsDevices() {
        #expect(summary() == [
            "Records every display, each into its own file at up to 1080p: now Built-in Retina Display and LG HDR 4K.",
            "Audio: MacBook Pro Microphone (default) and system audio.",
            "Files go to ~/Movies/Multi Screen Recorder. Recording continues when displays or audio sources change.",
        ])
    }

    @Test func displaysFollowTheResolutionAndTheirNumbers() {
        let three = DesignExample.displays + [
            DisplayInfo(name: "Projector", pixelSize: FrameSize(width: 1920, height: 1080), isMain: false, originX: -1920, originY: 0),
        ]
        #expect(summary({ $0.resolution = .native }, displays: .success(three)).first
            == "Records every display, each into its own file at its native size: now Built-in Retina Display, Projector and LG HDR 4K.")
        #expect(summary({ $0.resolution = .uhd4k }, displays: .success([DesignExample.displays[1]])).first
            == "Records every display, each into its own file at up to 4K: now Built-in Retina Display.")
    }

    @Test func noDisplaysOrUnreadableOnesAreSaid() {
        #expect(summary(displays: .success([])).first
            == "Records every display, each into its own file at up to 1080p: none is connected now.")
        #expect(summary(displays: .failure(DeviceReadError("the display X does not report its display mode"))).first
            == "Records every display, each into its own file at up to 1080p: the displays cannot be read now.")
    }

    @Test func audioFollowsTheAudioModeAndSystemAudio() {
        #expect(summary({ $0.systemAudio = false })[1] == "Audio: MacBook Pro Microphone (default).")
        #expect(summary({ $0.audioMode = .none })[1] == "Audio: system audio.")
        #expect(summary({ $0.audioMode = .none; $0.systemAudio = false })[1] == "Audio: none.")
        #expect(summary(defaultMicrophone: nil)[1] == "Audio: no microphone and system audio.")
    }

    @Test func theOutputFolderIsAsSet() {
        #expect(summary({ $0.outputFolder = "/Volumes/Data/Recordings" })[2]
            == "Files go to /Volumes/Data/Recordings. Recording continues when displays or audio sources change.")
    }
}

@Suite struct ProductTextTests {
    @Test func thePurposeIsTheReadmesOpeningParagraph() throws {
        let readme = try repositoryFile("README.md")
        let opening = readme.components(separatedBy: "\n\n")[1].replacing("\n", with: " ")
        #expect(ProductText.purpose == opening)
    }

    @Test func resolutionLabels() {
        #expect(RecordingResolution.allCases.map(\.label) == ["Native", "4K", "1440p", "1200p", "1080p", "720p"])
    }
}
