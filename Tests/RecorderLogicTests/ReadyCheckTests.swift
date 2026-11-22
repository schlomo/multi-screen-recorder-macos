import Testing
@testable import RecorderLogic

@Suite struct ReadyCheckTests {
    private let fullHDScreens = [
        ScreenInfo(name: "One", pixelSize: FrameSize(width: 1920, height: 1080), pointSize: FrameSize(width: 1920, height: 1080), isMain: true, originX: 0, originY: 0),
        ScreenInfo(name: "Two", pixelSize: FrameSize(width: 3840, height: 2160), pointSize: FrameSize(width: 3840, height: 2160), isMain: false, originX: 1920, originY: 0),
    ]

    private func facts(
        screenRecording: PermissionProbe? = .granted,
        microphoneGranted: Bool? = true,
        screens: Result<[ScreenInfo], DeviceReadError>? = nil,
        audioInputs: [AudioInputInfo] = builtInMicrophoneOnly,
        audioInputsError: DeviceReadError? = nil,
        outputFolder: OutputFolderProbe = .usable(.bytes(100_000_000_000)),
        cameras: [CameraInfo] = []
    ) -> ReadyCheckFacts {
        ReadyCheckFacts(
            screenRecording: screenRecording,
            microphoneGranted: microphoneGranted,
            screens: screens ?? .success(fullHDScreens),
            audioInputs: audioInputsError.map { .failure($0) } ?? .success(audioInputs),
            outputFolder: outputFolder,
            cameraGranted: cameras.isEmpty ? nil : true,
            cameras: cameras
        )
    }

    private static let builtInMicrophoneOnly = [AudioInputInfo(name: "MacBook Pro Microphone", channelCount: 1, isDefault: true, uid: "BuiltIn")]

    /// The example in docs/design/recorder.md, from the screens of its `msr list` example.
    static let designExample = """
        ok    Screen & System Audio Recording permission
        ok    Microphone permission
        ok    Camera permission
        ok    Screens: 2
        ok    Audio: system audio, MacBook Pro Microphone (default), RØDE Wireless GO II RX
        ok    Output folder: ~/Movies/Multi Screen Recorder
        FAIL  Free disk space: 3.1 GB in ~/Movies/Multi Screen Recorder, 12.8 GB needed for 2 hours
              Fix: free up space, or lower --required-recording-hours
        Not ready.

        """

    @Test func rendersExactlyAsTheDesign() {
        let result = ReadyCheck.evaluate(
            facts(screens: .success(DesignExample.screens), audioInputs: DesignExample.audioInputs,
                  outputFolder: .usable(.bytes(3_100_000_000)), cameras: DesignExample.cameras),
            settings: .defaults)
        #expect(result.text == Self.designExample)
        #expect(!result.isReady)
    }

    @Test func theDesignShowsTheExample() throws {
        #expect(try repositoryFile("docs/design/recorder.md").contains("```\n\(Self.designExample)```\n"))
    }

    /// A long fix wraps at 80 columns and keeps its indent, under the text after "Fix: ".
    @Test func aLongFixWrapsWithItsIndent() throws {
        let result = ReadyCheck.evaluate(facts(screenRecording: .notGranted), settings: .manual)
        let lines = result.text.split(separator: "\n").map(String.init)
        let start = try #require(lines.firstIndex { $0.hasPrefix("      Fix: ") })
        let fix = lines[start...].prefix { $0.hasPrefix("      Fix: ") || $0.hasPrefix("           ") }
        #expect(fix.count > 2)
        #expect(fix.allSatisfy { $0.count <= 80 })
        #expect(fix.dropFirst().allSatisfy { $0.hasPrefix("           ") && !$0.hasPrefix("            ") })
        #expect(fix.map { $0.dropFirst(11) }.joined(separator: " ")
            == "allow it in System Settings › Privacy & Security › Screen & System Audio Recording. "
            + "If it is still missing after that, " + ReadyCheck.restartNote + ReadyCheck.terminalNote)
    }

    @Test func allGoodIsReady() {
        let result = ReadyCheck.evaluate(facts(), settings: .manual)
        #expect(result.isReady)
        #expect(result.items.allSatisfy { $0.passed })
        #expect(result.text.hasSuffix("\nReady.\n"))
    }

    @Test func audioModeNoneSkipsTheMicrophone() {
        var settings = Settings.manual
        settings.audioMode = .none
        let result = ReadyCheck.evaluate(
            facts(microphoneGranted: nil, audioInputs: []), settings: settings)
        #expect(result.isReady)
        #expect(result.items.map(\.title) == [
            "Screen & System Audio Recording permission",
            "Screens: 2",
            "Audio: system audio",
            "Output folder: ~/Movies/Multi Screen Recorder",
            "Free disk space: 100.0 GB in ~/Movies/Multi Screen Recorder, 4.3 GB needed for 2 hours",
        ])
    }

    @Test func audioModeNoneNeedsNoReadableAudioInputs() {
        var settings = Settings.manual
        settings.audioMode = .none
        let result = ReadyCheck.evaluate(
            facts(microphoneGranted: nil, audioInputs: [Self.unreadable(isDefault: true)]), settings: settings)
        #expect(result.isReady)
        #expect(result.items.contains { $0.title.hasPrefix("Free disk space") })
    }

    @Test func noAudioAtAllSaysNone() {
        var settings = Settings.manual
        settings.audioMode = .none
        settings.systemAudio = false
        let result = ReadyCheck.evaluate(facts(microphoneGranted: nil), settings: settings)
        #expect(result.items.contains(ReadyCheckItem(title: "Audio: none", passed: true, fix: nil)))
    }

    @Test func aMissingScreenPermissionNamesTheSettingsPath() throws {
        let result = ReadyCheck.evaluate(facts(screenRecording: .notGranted), settings: .manual)
        let item = try #require(result.items.first)
        #expect(item.passed == false)
        #expect(item.fix == "allow it in System Settings › Privacy & Security › Screen & System Audio Recording. "
            + "If it is still missing after that, quit Multi Screen Recorder and start it again. "
            + "If it was started from a terminal, then the terminal app needs the permission.")
        #expect(!result.isReady)
    }

    /// D55: a recording opens an input by its Core Audio UID; one without
    /// is not recorded, so it is not listed and needs no permission.
    @Test func anInputWithoutAUIDIsNotListedAndNeedsNoMicrophonePermission() {
        let noUID = AudioInputInfo(name: "Mystery", channelCount: 1, isDefault: true, transport: .usb)
        let result = ReadyCheck.evaluate(facts(microphoneGranted: false, audioInputs: [noUID]), settings: .defaults)
        #expect(!result.items.contains { $0.title == "Microphone permission" })
        let audio = result.items.first { $0.title.hasPrefix("Audio:") }
        #expect(audio?.title == "Audio: system audio, no microphone recorded")
        let withBuiltIn = ReadyCheck.evaluate(facts(audioInputs: Self.builtInMicrophoneOnly + [noUID]), settings: .defaults)
        #expect(withBuiltIn.items.contains { $0.title == "Audio: system audio, MacBook Pro Microphone (default)" })
    }

    @Test func aMissingMicrophonePermissionNamesTheSettingsPath() throws {
        let result = ReadyCheck.evaluate(facts(microphoneGranted: false), settings: .manual)
        let item = try #require(result.items.first { $0.title == "Microphone permission" })
        #expect(item.passed == false)
        #expect(item.fix == "allow it in System Settings › Privacy & Security › Microphone, "
            + "then quit Multi Screen Recorder and start it again. "
            + "If it was started from a terminal, then the terminal app needs the permission.")
    }

    @Test func noScreenFails() throws {
        let result = ReadyCheck.evaluate(facts(screens: .success([])), settings: .manual)
        let item = try #require(result.items.first { $0.title.hasPrefix("Screens") })
        #expect(item == ReadyCheckItem(title: "Screens: 0", passed: false, fix: "connect a screen"))
    }

    @Test func unreadableScreensFailOnceWithTheReason() {
        let result = ReadyCheck.evaluate(
            facts(screens: .failure(DeviceReadError("the screen DELL U2720Q does not report its screen mode"))),
            settings: .manual)
        #expect(result.items.filter { !$0.passed } == [
            ReadyCheckItem(
                title: "Screens: cannot be read (the screen DELL U2720Q does not report its screen mode)",
                passed: false,
                fix: "reconnect the screens, then check again"),
        ])
        #expect(!result.items.contains { $0.title.hasPrefix("Free disk space") })
    }

    /// The owner, 2026-11-15: "no mic should just work of course, in any mode.
    /// and system audio is still a thing."
    @Test(arguments: AudioMode.allCases)
    func aMacWithoutAnyAudioInputIsReadyInEveryAudioMode(mode: AudioMode) {
        var settings = Settings.manual
        settings.audioMode = mode
        let result = ReadyCheck.evaluate(facts(audioInputs: []), settings: settings)
        #expect(result.isReady)
        let audio = result.items.first { $0.title.hasPrefix("Audio:") }
        #expect(audio == ReadyCheckItem(
            title: mode == .none ? "Audio: system audio" : "Audio: system audio, no microphone recorded",
            passed: true, fix: nil))
        #expect(result.items.contains { $0.title.hasPrefix("Free disk space") })
    }

    /// No input recorded: the Microphone permission is no part of the check.
    @Test(arguments: AudioMode.allCases)
    func withoutAnyAudioInputThereIsNoMicrophonePermissionItem(mode: AudioMode) {
        var settings = Settings.manual
        settings.audioMode = mode
        let result = ReadyCheck.evaluate(facts(microphoneGranted: nil, audioInputs: []), settings: settings)
        #expect(result.isReady)
        #expect(!result.items.contains { $0.title == "Microphone permission" })
    }

    @Test func aRecordedInputWithoutThePermissionFails() {
        let result = ReadyCheck.evaluate(facts(microphoneGranted: false), settings: .manual)
        #expect(result.items.contains { $0.title == "Microphone permission" && !$0.passed })
        #expect(!result.isReady)
    }

    @Test func aPresentButNotRecordedInputNeedsNoPermission() {
        let notDefault = [AudioInputInfo(name: "USB", channelCount: 1, isDefault: false, transport: .usb, uid: "USB")]
        let result = ReadyCheck.evaluate(facts(microphoneGranted: nil, audioInputs: notDefault), settings: .manual)
        #expect(result.isReady)
        #expect(!result.items.contains { $0.title == "Microphone permission" })
    }

    @Test func withoutAnyAudioInputAndWithoutSystemAudioTheItemSaysSo() {
        var settings = Settings.manual
        settings.systemAudio = false
        let result = ReadyCheck.evaluate(facts(audioInputs: []), settings: settings)
        #expect(result.isReady)
        #expect(result.items.contains(ReadyCheckItem(
            title: "Audio: no microphone recorded, no system audio", passed: true, fix: nil)))
    }

    @Test func autoModeWithoutAnyAudioInputIsReady() {
        var settings = Settings.defaults
        settings.audioMode = .none
        #expect(ReadyCheck.evaluate(facts(audioInputs: []), settings: settings).isReady)
    }

    private static func unreadable(isDefault: Bool) -> AudioInputInfo {
        AudioInputInfo(name: "X", channelCount: .failure(DeviceReadError("the audio input X does not report its format")),
                       isDefault: isDefault, uid: "X")
    }

    @Test func anUnreadableInputThatIsNotRecordedPasses() {
        let result = ReadyCheck.evaluate(
            facts(audioInputs: Self.builtInMicrophoneOnly + [Self.unreadable(isDefault: false)]), settings: .manual)
        #expect(result.isReady)
        #expect(result.items.contains { $0.title.hasPrefix("Free disk space") })
    }

    @Test func anUnreadableRecordedInputFailsOnceWithTheReason() {
        let result = ReadyCheck.evaluate(facts(audioInputs: [Self.unreadable(isDefault: true)]), settings: .manual)
        #expect(result.items.filter { !$0.passed } == [
            ReadyCheckItem(
                title: "Audio: cannot be read (the audio input X does not report its format)",
                passed: false,
                fix: "reconnect the audio inputs, then check again"),
        ])
        #expect(!result.items.contains { $0.title.hasPrefix("Free disk space") })
    }

    private static let unreadableList = DeviceReadError("the list of audio devices cannot be read (Core Audio error 560947818)")

    @Test func anUnreadableListOfAudioInputsFailsOnceWithTheReason() {
        let result = ReadyCheck.evaluate(facts(audioInputsError: Self.unreadableList), settings: .manual)
        #expect(result.items.filter { !$0.passed } == [
            ReadyCheckItem(
                title: "Audio: cannot be read (the list of audio devices cannot be read (Core Audio error 560947818))",
                passed: false,
                fix: "reconnect the audio inputs, then check again"),
        ])
        #expect(!result.items.contains { $0.title.hasPrefix("Free disk space") })
    }

    @Test func audioModeNoneNeedsNoReadableListOfAudioInputs() {
        var settings = Settings.manual
        settings.audioMode = .none
        let result = ReadyCheck.evaluate(
            facts(microphoneGranted: nil, audioInputsError: Self.unreadableList), settings: settings)
        #expect(result.isReady)
        #expect(result.items.contains { $0.title.hasPrefix("Free disk space") })
    }

    @Test func theDiskEstimateCountsTheAudioFilesAndGuideTracks() throws {
        var settings = Settings.manual
        settings.requiredRecordingHours = 1
        let twoChannels = [AudioInputInfo(name: "RØDE Wireless GO II RX", channelCount: 2, isDefault: true, uid: "RODE")]
        let result = ReadyCheck.evaluate(facts(audioInputs: twoChannels), settings: settings)
        let item = try #require(result.items.last)
        // two screens at 1080p: 2 × (1 GB video + 72 MB guide tracks), 115.2 MB microphone, 86.4 MB system audio
        #expect(item.title == "Free disk space: 100.0 GB in ~/Movies/Multi Screen Recorder, 2.3 GB needed for 1 hour")
    }

    @Test func diskEstimateUsesTheRecordingResolution() throws {
        var settings = Settings.manual
        settings.resolution = .p720
        settings.requiredRecordingHours = 1
        let result = ReadyCheck.evaluate(facts(), settings: settings)
        let item = try #require(result.items.last)
        #expect(item.title == "Free disk space: 100.0 GB in ~/Movies/Multi Screen Recorder, 1.2 GB needed for 1 hour")
    }

    @Test func theOutputFolderComesBeforeTheFreeDiskSpace() {
        let titles = ReadyCheck.evaluate(facts(), settings: .manual).items.map(\.title)
        #expect(titles.suffix(2) == [
            "Output folder: ~/Movies/Multi Screen Recorder",
            "Free disk space: 100.0 GB in ~/Movies/Multi Screen Recorder, 4.6 GB needed for 2 hours",
        ])
    }

    @Test func anUnusableOutputFolderFailsOnceWithItsPathAndReason() {
        var settings = Settings.manual
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
        let result = ReadyCheck.evaluate(facts(outputFolder: .usable(.unreadable("no such volume"))), settings: .manual)
        let item = try #require(result.items.last)
        #expect(item.passed == false)
        #expect(item.title == "Free disk space: unknown in ~/Movies/Multi Screen Recorder (no such volume)")
        #expect(item.fix == "choose an output folder on another disk (--output-folder)")
    }

    @Test(arguments: [(1.0, "1 hour"), (2.0, "2 hours"), (1.5, "1.5 hours"), (0.25, "0.25 hours"), (1e20, "1e+20 hours")])
    func hoursReadNaturally(hours: Double, text: String) {
        #expect(ReadyCheck.hoursText(hours) == text)
    }

    @Test func aHugeRequiredRecordingTimeIsNamedWithoutCrashing() throws {
        var settings = Settings.manual
        settings.requiredRecordingHours = 1e20
        let result = ReadyCheck.evaluate(facts(), settings: settings)
        let item = try #require(result.items.last)
        #expect(item.title.contains("1e+20 hours"))
    }

    private func audioTitle(_ mode: AudioMode, _ inputs: [AudioInputInfo], auto: Bool = false) -> String? {
        var settings = Settings.manual
        settings.audioMode = mode
        settings.auto = auto
        return ReadyCheck.evaluate(facts(audioInputs: inputs), settings: settings).items
            .first { $0.title.hasPrefix("Audio:") }?.title
    }

    private static let airPods = AudioInputInfo(name: "AirPods", channelCount: 1, isDefault: false, transport: .bluetooth, uid: "AirPods")

    @Test func theAudioItemNamesEveryRecordedInputOfTheAudioMode() {
        let inputs = DesignExample.audioInputs + [Self.airPods]
        #expect(audioTitle(.defaultMicrophone, inputs) == "Audio: system audio, MacBook Pro Microphone (default)")
        #expect(audioTitle(.wired, inputs)
            == "Audio: system audio, MacBook Pro Microphone (default), RØDE Wireless GO II RX")
        #expect(audioTitle(.allInputs, inputs)
            == "Audio: system audio, MacBook Pro Microphone (default), RØDE Wireless GO II RX, AirPods")
        #expect(audioTitle(.none, inputs) == "Audio: system audio")
    }

    @Test func autoModeChecksWhatWiredRecordsWhateverTheSlidersSay() {
        #expect(audioTitle(.none, DesignExample.audioInputs, auto: true)
            == "Audio: system audio, MacBook Pro Microphone (default), RØDE Wireless GO II RX")
    }

    @Test func autoModeNeedsTheMicrophonePermission() {
        var settings = Settings.manual
        settings.audioMode = .none
        settings.auto = true
        let result = ReadyCheck.evaluate(facts(microphoneGranted: false), settings: settings)
        #expect(result.items.contains { $0.title == "Microphone permission" && !$0.passed })
    }

    @Test(arguments: [AudioMode.defaultMicrophone, .wired, .allInputs])
    func aBluetoothDefaultMicrophoneIsEnoughInEveryModeBut(none mode: AudioMode) {
        let headset = AudioInputInfo(name: "AirPods", channelCount: 1, isDefault: true, transport: .bluetooth, uid: "AirPods")
        #expect(audioTitle(mode, [headset]) == "Audio: system audio, AirPods (default)")
    }

    @Test func withoutAnyRecordedInputTheItemSaysNoMicrophoneRecordedAndPasses() {
        #expect(audioTitle(.wired, [Self.airPods]) == "Audio: system audio, no microphone recorded")
    }

    @Test func inputsToJudgeAreNoneWithTheAudioModeNoneWhetherTheyCanBeReadOrNot() {
        var none = Settings.manual
        none.audioMode = .none
        #expect(audioInputsToJudge(.success(DesignExample.audioInputs), settings: none) == .success([]))
        #expect(audioInputsToJudge(.failure(DeviceReadError("no list")), settings: none) == .success([]))
    }

    @Test(arguments: [AudioMode.defaultMicrophone, .wired, .allInputs])
    func otherAudioModesJudgeTheInputsAsTheyAre(mode: AudioMode) {
        var settings = Settings.manual
        settings.audioMode = mode
        #expect(audioInputsToJudge(.success(DesignExample.audioInputs), settings: settings)
            == .success(DesignExample.audioInputs))
        #expect(audioInputsToJudge(.failure(DeviceReadError("no list")), settings: settings)
            == .failure(DeviceReadError("no list")))
    }

    // Audio only: the recording resolution None.

    private func audioOnly(_ edit: (inout Settings) -> Void = { _ in }) -> Settings {
        var settings = Settings.manual
        settings.resolution = .none
        edit(&settings)
        return settings
    }

    /// The system audio still needs the Screen & System Audio Recording permission and a main screen to
    /// capture through (the owner, 2026-11-18); no screen is recorded.
    @Test func atTheResolutionNoneTheSystemAudioNeedsTheScreenPermissionAndAMainScreen() {
        let result = ReadyCheck.evaluate(facts(), settings: audioOnly())
        #expect(result.items.map(\.title) == [
            "Screen & System Audio Recording permission",
            "Microphone permission",
            "Screens: 2, none recorded (the system audio needs the main screen)",
            "Audio: system audio, MacBook Pro Microphone (default)",
            "Output folder: ~/Movies/Multi Screen Recorder",
            "Free disk space: 100.0 GB in ~/Movies/Multi Screen Recorder, 0.3 GB needed for 2 hours",
        ])
        #expect(result.isReady)
        #expect(!ReadyCheck.evaluate(facts(screenRecording: .notGranted), settings: audioOnly()).isReady)
    }

    /// Without a main screen, or with screens that cannot be read, the system audio cannot be recorded:
    /// one red item with its fix, also when the system audio is the only source.
    @Test(arguments: [true, false])
    func atTheResolutionNoneTheSystemAudioWithoutAMainScreenIsNotReady(withMicrophone: Bool) {
        let settings = audioOnly { if !withMicrophone { $0.audioMode = .none } }
        let microphone: Bool? = withMicrophone ? true : nil
        let notMain = ScreenInfo(name: "One", pixelSize: FrameSize(width: 1920, height: 1080),
                                 pointSize: FrameSize(width: 1920, height: 1080), isMain: false, originX: 0, originY: 0)
        let fix = "connect a screen, or turn off the system audio (--system-audio off)"
        for (screens, item) in [
            (Result<[ScreenInfo], DeviceReadError>.success([]),
             ReadyCheckItem(title: "Screens: 0, none recorded (the system audio needs the main screen)", passed: false, fix: fix)),
            (.success([notMain]),
             ReadyCheckItem(title: "Screens: 1, none recorded (the system audio needs the main screen)", passed: false, fix: fix)),
            (.failure(DeviceReadError("no list")),
             ReadyCheckItem(title: "Screens: cannot be read (no list), none recorded (the system audio needs the main screen)",
                            passed: false, fix: "reconnect the screens, then check again, or turn off the system audio (--system-audio off)")),
        ] {
            let result = ReadyCheck.evaluate(facts(microphoneGranted: microphone, screens: screens), settings: settings)
            #expect(!result.isReady)
            #expect(result.items.filter { !$0.passed } == [item])
        }
    }

    /// The microphone alone needs no Screen & System Audio Recording permission, which is then not asked.
    @Test func atTheResolutionNoneTheMicrophoneAloneNeedsNoScreenPermission() {
        let settings = audioOnly { $0.systemAudio = false }
        #expect(!ReadyCheck.needsScreenRecording(settings))
        let result = ReadyCheck.evaluate(facts(screenRecording: nil), settings: settings)
        #expect(!result.items.contains { $0.title.hasPrefix("Screen") })
        #expect(result.isReady)
        #expect(ReadyCheck.needsScreenRecording(audioOnly()))
        #expect(ReadyCheck.needsScreenRecording(.manual))
        var withoutAudio = Settings.manual
        withoutAudio.systemAudio = false
        #expect(ReadyCheck.needsScreenRecording(withoutAudio))
    }

    /// The microphone alone does not depend on the screens: screens that cannot be read, or none, fail
    /// nothing and leave the free disk space in.
    @Test func atTheResolutionNoneWithoutTheSystemAudioNoScreenIsChecked() {
        let settings = audioOnly { $0.systemAudio = false }
        for screens in [Result<[ScreenInfo], DeviceReadError>.failure(DeviceReadError("no list")), .success([])] {
            let result = ReadyCheck.evaluate(facts(screenRecording: nil, screens: screens), settings: settings)
            #expect(result.isReady)
            #expect(!result.items.contains { $0.title.hasPrefix("Screens") })
            #expect(result.items.contains { $0.title.hasPrefix("Free disk space:") })
        }
    }

    /// A recording with neither screens nor audio refuses to start (the owner, 2026-11-16).
    @Test(arguments: [AudioMode.none, .defaultMicrophone])
    func aRecordingWithNeitherScreensNorAudioIsNotReady(mode: AudioMode) {
        let settings = audioOnly {
            $0.audioMode = mode
            $0.systemAudio = false
        }
        let result = ReadyCheck.evaluate(facts(microphoneGranted: nil, audioInputs: []), settings: settings)
        #expect(!result.isReady)
        #expect(result.items.filter { !$0.passed } == [ReadyCheck.nothingToRecordItem])
        #expect(result.text.contains("FAIL  Nothing to record: the recording resolution None records no screen, and no audio source is recorded\n"))
    }

    @Test func aRecordingWithAudioAloneOrScreensAloneHasSomethingToRecord() {
        #expect(ReadyCheck.evaluate(facts(screenRecording: nil), settings: audioOnly { $0.systemAudio = false }).isReady)
        #expect(ReadyCheck.evaluate(facts(microphoneGranted: nil), settings: audioOnly { $0.audioMode = .none }).isReady)
        var screensAlone = Settings.manual
        screensAlone.audioMode = .none
        screensAlone.systemAudio = false
        #expect(ReadyCheck.evaluate(facts(microphoneGranted: nil), settings: screensAlone).isReady)
    }
}
