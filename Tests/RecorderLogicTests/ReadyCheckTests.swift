import Testing
@testable import RecorderLogic

@Suite struct ReadyCheckTests {
    private let fullHDScreens = [
        ScreenInfo(name: "One", pixelSize: FrameSize(width: 1920, height: 1080), pointSize: FrameSize(width: 1920, height: 1080), isMain: true, originX: 0, originY: 0),
        ScreenInfo(name: "Two", pixelSize: FrameSize(width: 3840, height: 2160), pointSize: FrameSize(width: 3840, height: 2160), isMain: false, originX: 1920, originY: 0),
    ]

    private func facts(
        screenRecording: PermissionProbe = .granted,
        microphoneGranted: Bool? = true,
        screens: Result<[ScreenInfo], DeviceReadError>? = nil,
        audioInputs: [AudioInputInfo] = builtInMicrophoneOnly,
        audioInputsError: DeviceReadError? = nil,
        outputFolder: OutputFolderProbe = .usable(.bytes(100_000_000_000))
    ) -> ReadyCheckFacts {
        ReadyCheckFacts(
            screenRecording: screenRecording,
            microphoneGranted: microphoneGranted,
            screens: screens ?? .success(fullHDScreens),
            audioInputs: audioInputsError.map { .failure($0) } ?? .success(audioInputs),
            outputFolder: outputFolder
        )
    }

    private static let builtInMicrophoneOnly = [AudioInputInfo(name: "MacBook Pro Microphone", channelCount: 1, isDefault: true, uid: "BuiltIn")]

    /// The example in docs/design/recorder.md, from the screens of its `msr list` example.
    static let designExample = """
        ok    Screen & System Audio Recording permission
        ok    Microphone permission
        ok    Screens: 2
        ok    Audio: MacBook Pro Microphone (default), RØDE Wireless GO II RX, system audio
        ok    Output folder: ~/Movies/Multi Screen Recorder
        FAIL  Free disk space: 3.1 GB in ~/Movies/Multi Screen Recorder, 10.7 GB needed for 2 hours
              Fix: free up space, or lower --required-recording-hours
        Not ready.

        """

    @Test func rendersExactlyAsTheDesign() {
        let result = ReadyCheck.evaluate(
            facts(screens: .success(DesignExample.screens), audioInputs: DesignExample.audioInputs,
                  outputFolder: .usable(.bytes(3_100_000_000))),
            settings: .defaults)
        #expect(result.text == Self.designExample)
        #expect(!result.isReady)
    }

    @Test func theDesignShowsTheExample() throws {
        #expect(try repositoryFile("docs/design/recorder.md").contains("```\n\(Self.designExample)```\n"))
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
        #expect(audio?.title == "Audio: no microphone, system audio")
        let withBuiltIn = ReadyCheck.evaluate(facts(audioInputs: Self.builtInMicrophoneOnly + [noUID]), settings: .defaults)
        #expect(withBuiltIn.items.contains { $0.title == "Audio: MacBook Pro Microphone (default), system audio" })
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
            title: mode == .none ? "Audio: system audio" : "Audio: no microphone, system audio",
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
            title: "Audio: no microphone, no system audio", passed: true, fix: nil)))
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
        #expect(audioTitle(.defaultMicrophone, inputs) == "Audio: MacBook Pro Microphone (default), system audio")
        #expect(audioTitle(.wired, inputs)
            == "Audio: MacBook Pro Microphone (default), RØDE Wireless GO II RX, system audio")
        #expect(audioTitle(.allInputs, inputs)
            == "Audio: MacBook Pro Microphone (default), RØDE Wireless GO II RX, AirPods, system audio")
        #expect(audioTitle(.none, inputs) == "Audio: system audio")
    }

    @Test func autoModeChecksWhatWiredRecordsWhateverTheSlidersSay() {
        #expect(audioTitle(.none, DesignExample.audioInputs, auto: true)
            == "Audio: MacBook Pro Microphone (default), RØDE Wireless GO II RX, system audio")
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
        #expect(audioTitle(mode, [headset]) == "Audio: AirPods (default), system audio")
    }

    @Test func withoutAnyRecordedInputTheItemSaysNoMicrophoneAndPasses() {
        #expect(audioTitle(.wired, [Self.airPods]) == "Audio: no microphone, system audio")
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
}
