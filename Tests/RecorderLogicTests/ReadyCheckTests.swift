import Testing
@testable import RecorderLogic

@Suite struct ReadyCheckTests {
    private let fullHDDisplays = [
        DisplayInfo(name: "One", pixelSize: FrameSize(width: 1920, height: 1080), pointSize: FrameSize(width: 1920, height: 1080), isMain: true, originX: 0, originY: 0),
        DisplayInfo(name: "Two", pixelSize: FrameSize(width: 3840, height: 2160), pointSize: FrameSize(width: 3840, height: 2160), isMain: false, originX: 1920, originY: 0),
    ]

    private func facts(
        screenRecording: PermissionProbe = .granted,
        microphonePermission: PermissionProbe? = .granted,
        displays: Result<[DisplayInfo], DeviceReadError>? = nil,
        defaultMicrophone: String?? = .none,
        outputFolder: OutputFolderProbe = .usable(.bytes(100_000_000_000))
    ) -> ReadyCheckFacts {
        ReadyCheckFacts(
            screenRecording: screenRecording,
            microphone: microphonePermission,
            displays: displays ?? .success(fullHDDisplays),
            defaultMicrophone: defaultMicrophone ?? "MacBook Pro Microphone",
            outputFolder: outputFolder
        )
    }

    /// The example in docs/design/recorder.md, from the displays of its `msr list` example.
    static let designExample = """
        ok    Screen & System Audio Recording permission
        ok    Microphone permission
        ok    Displays: 2
        ok    Audio: MacBook Pro Microphone (default), system audio
        ok    Output folder: ~/Movies/Multi Screen Recorder
        FAIL  Free disk space: 3.1 GB in ~/Movies/Multi Screen Recorder, 3.7 GB needed for 2 hours
              Fix: free up space, or lower --required-recording-hours
        Not ready.

        """

    @Test func rendersExactlyAsTheDesign() {
        let result = ReadyCheck.evaluate(
            facts(displays: .success(DesignExample.displays), outputFolder: .usable(.bytes(3_100_000_000))),
            settings: .defaults)
        #expect(result.text == Self.designExample)
        #expect(!result.isReady)
    }

    @Test func theDesignShowsTheExample() throws {
        #expect(try repositoryFile("docs/design/recorder.md").contains("```\n\(Self.designExample)```\n"))
    }

    @Test func allGoodIsReady() {
        let result = ReadyCheck.evaluate(facts(), settings: .defaults)
        #expect(result.isReady)
        #expect(result.items.allSatisfy { $0.passed })
        #expect(result.text.hasSuffix("\nReady.\n"))
    }

    @Test func audioModeNoneSkipsTheMicrophone() {
        var settings = Settings.defaults
        settings.audioMode = .none
        let result = ReadyCheck.evaluate(
            facts(microphonePermission: nil, defaultMicrophone: .some(nil)), settings: settings)
        #expect(result.isReady)
        #expect(result.items.map(\.title) == [
            "Screen & System Audio Recording permission",
            "Displays: 2",
            "Audio: system audio",
            "Output folder: ~/Movies/Multi Screen Recorder",
            "Free disk space: 100.0 GB in ~/Movies/Multi Screen Recorder, 4.0 GB needed for 2 hours",
        ])
    }

    @Test func noAudioAtAllSaysNone() {
        var settings = Settings.defaults
        settings.audioMode = .none
        settings.systemAudio = false
        let result = ReadyCheck.evaluate(facts(microphonePermission: nil), settings: settings)
        #expect(result.items.contains(ReadyCheckItem(title: "Audio: none", passed: true, fix: nil)))
    }

    @Test func aMissingScreenPermissionNamesTheSettingsPath() throws {
        let result = ReadyCheck.evaluate(facts(screenRecording: .notGranted), settings: .defaults)
        let item = try #require(result.items.first)
        #expect(item.passed == false)
        #expect(item.fix?.contains("System Settings › Privacy & Security › Screen & System Audio Recording") == true)
        #expect(!result.isReady)
    }

    @Test func aMissingMicrophonePermissionNamesTheSettingsPath() throws {
        let result = ReadyCheck.evaluate(facts(microphonePermission: .notGranted), settings: .defaults)
        let item = try #require(result.items.first { $0.title == "Microphone permission" })
        #expect(item.passed == false)
        #expect(item.fix?.contains("System Settings › Privacy & Security › Microphone") == true)
    }

    @Test func aMicrophoneThatCannotBeOpenedFailsWithTheReason() throws {
        let result = ReadyCheck.evaluate(facts(microphonePermission: .failed("device busy")), settings: .defaults)
        let item = try #require(result.items.first { $0.title.hasPrefix("Microphone permission") })
        #expect(item.passed == false)
        #expect(item.title.contains("device busy"))
    }

    @Test func noDisplayFails() throws {
        let result = ReadyCheck.evaluate(facts(displays: .success([])), settings: .defaults)
        let item = try #require(result.items.first { $0.title.hasPrefix("Displays") })
        #expect(item == ReadyCheckItem(title: "Displays: 0", passed: false, fix: "connect a display"))
    }

    @Test func unreadableDisplaysFailOnceWithTheReason() {
        let result = ReadyCheck.evaluate(
            facts(displays: .failure(DeviceReadError("the display DELL U2720Q does not report its display mode"))),
            settings: .defaults)
        #expect(result.items.filter { !$0.passed } == [
            ReadyCheckItem(
                title: "Displays: cannot be read (the display DELL U2720Q does not report its display mode)",
                passed: false,
                fix: "reconnect the displays, then check again"),
        ])
        #expect(!result.items.contains { $0.title.hasPrefix("Free disk space") })
    }

    @Test func noMicrophoneFailsOnlyTheAudioItem() throws {
        let result = ReadyCheck.evaluate(facts(defaultMicrophone: .some(nil)), settings: .defaults)
        #expect(result.items.filter { !$0.passed } == [
            ReadyCheckItem(
                title: "Audio: no microphone, system audio",
                passed: false,
                fix: "connect a microphone, or set the audio mode to none (--audio-mode none)"),
        ])
    }

    @Test func diskEstimateUsesTheRecordingResolution() throws {
        var settings = Settings.defaults
        settings.resolution = .p720
        settings.requiredRecordingHours = 1
        let result = ReadyCheck.evaluate(facts(), settings: settings)
        let item = try #require(result.items.last)
        #expect(item.title == "Free disk space: 100.0 GB in ~/Movies/Multi Screen Recorder, 0.9 GB needed for 1 hour")
    }

    @Test func theOutputFolderComesBeforeTheFreeDiskSpace() {
        let titles = ReadyCheck.evaluate(facts(), settings: .defaults).items.map(\.title)
        #expect(titles.suffix(2) == [
            "Output folder: ~/Movies/Multi Screen Recorder",
            "Free disk space: 100.0 GB in ~/Movies/Multi Screen Recorder, 4.0 GB needed for 2 hours",
        ])
    }

    @Test func anUnusableOutputFolderFailsOnceWithItsPathAndReason() {
        var settings = Settings.defaults
        settings.outputFolder = "/Volumes/Gone/Recordings"
        let result = ReadyCheck.evaluate(
            facts(outputFolder: .unusable("You don’t have permission to save the file “Recordings” in the folder “Gone”.")),
            settings: settings)
        #expect(result.items.filter { !$0.passed } == [
            ReadyCheckItem(
                title: "Output folder: /Volumes/Gone/Recordings cannot be used"
                    + " (You don’t have permission to save the file “Recordings” in the folder “Gone”.)",
                passed: false,
                fix: "choose another output folder (--output-folder)"),
        ])
        #expect(!result.items.contains { $0.title.hasPrefix("Free disk space") })
        #expect(!result.isReady)
    }

    @Test func unreadableFreeSpaceFails() throws {
        let result = ReadyCheck.evaluate(facts(outputFolder: .usable(.unreadable("no such volume"))), settings: .defaults)
        let item = try #require(result.items.last)
        #expect(item.passed == false)
        #expect(item.title == "Free disk space: unknown in ~/Movies/Multi Screen Recorder (no such volume)")
        #expect(item.fix == "choose an output folder on another disk (--output-folder)")
    }

    @Test(arguments: [(1.0, "1 hour"), (2.0, "2 hours"), (1.5, "1.5 hours"), (0.25, "0.25 hours")])
    func hoursReadNaturally(hours: Double, text: String) {
        #expect(ReadyCheck.hoursText(hours) == text)
    }
}
