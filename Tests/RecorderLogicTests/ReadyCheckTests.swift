import Testing
@testable import RecorderLogic

@Suite struct ReadyCheckTests {
    private let fullHDDisplays = [
        DisplayInfo(name: "One", pixelSize: FrameSize(width: 1920, height: 1080), isMain: true, originX: 0, originY: 0),
        DisplayInfo(name: "Two", pixelSize: FrameSize(width: 3840, height: 2160), isMain: false, originX: 1920, originY: 0),
    ]
    private let microphone = AudioInputInfo(name: "MacBook Pro Microphone", channelCount: 1, isDefault: true)

    private func facts(
        screenRecording: PermissionProbe = .granted,
        microphonePermission: PermissionProbe? = .granted,
        displays: [DisplayInfo]? = nil,
        defaultMicrophone: AudioInputInfo?? = .none,
        freeSpace: FreeSpace = .bytes(100_000_000_000)
    ) -> ReadyCheckFacts {
        ReadyCheckFacts(
            screenRecording: screenRecording,
            microphone: microphonePermission,
            displays: displays ?? fullHDDisplays,
            defaultMicrophone: defaultMicrophone ?? microphone,
            freeSpace: freeSpace
        )
    }

    @Test func rendersExactlyAsTheDesign() {
        let result = ReadyCheck.evaluate(facts(freeSpace: .bytes(3_100_000_000)), settings: .defaults)
        let expected = """
            ok    Screen & System Audio Recording permission
            ok    Microphone permission
            ok    Displays: 2
            ok    Audio: MacBook Pro Microphone (default), system audio
            FAIL  Free disk space: 3.1 GB in ~/Movies/Multi Screen Recorder, 4.0 GB needed for 2 hours
                  Fix: free up space, or lower --ready-check-hours
            Not ready.

            """
        #expect(result.text == expected)
        #expect(!result.isReady)
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
        let result = ReadyCheck.evaluate(facts(displays: []), settings: .defaults)
        let item = try #require(result.items.first { $0.title.hasPrefix("Displays") })
        #expect(item == ReadyCheckItem(title: "Displays: 0", passed: false, fix: "connect a display"))
    }

    @Test func noDefaultMicrophoneFails() throws {
        let result = ReadyCheck.evaluate(facts(defaultMicrophone: .some(nil)), settings: .defaults)
        let item = try #require(result.items.first { $0.title.hasPrefix("Audio") })
        #expect(item.passed == false)
        #expect(item.title == "Audio: no default microphone, system audio")
        #expect(item.fix == "connect a microphone, or set the audio mode to none (--audio-mode none)")
    }

    @Test func diskEstimateUsesTheRecordingResolution() throws {
        var settings = Settings.defaults
        settings.resolution = .p720
        settings.readyCheckHours = 1
        let result = ReadyCheck.evaluate(facts(), settings: settings)
        let item = try #require(result.items.last)
        #expect(item.title == "Free disk space: 100.0 GB in ~/Movies/Multi Screen Recorder, 0.9 GB needed for 1 hour")
    }

    @Test func unreadableFreeSpaceFails() throws {
        let result = ReadyCheck.evaluate(facts(freeSpace: .unreadable("no such volume")), settings: .defaults)
        let item = try #require(result.items.last)
        #expect(item.passed == false)
        #expect(item.title == "Free disk space: unknown in ~/Movies/Multi Screen Recorder (no such volume)")
        #expect(item.fix == "choose an output folder on a disk that is connected (--output-folder)")
    }

    @Test(arguments: [(1.0, "1 hour"), (2.0, "2 hours"), (1.5, "1.5 hours"), (0.25, "0.25 hours")])
    func hoursReadNaturally(hours: Double, text: String) {
        #expect(ReadyCheck.hoursText(hours) == text)
    }
}
