import Foundation
import Testing
@testable import RecorderLogic

@Suite struct SettingsDefaultsTests {
    @Test func defaultsMatchTheDesign() {
        let defaults = Settings.defaults
        #expect(defaults.auto == true)
        #expect(defaults.resolution == .native)
        #expect(defaults.audioMode == .wired)
        #expect(defaults.systemAudio == true)
        #expect(defaults.outputFolder == "~/Movies/Multi Screen Recorder")
        #expect(defaults.requiredRecordingHours == 2)
        #expect(defaults.lowDiskWarningMinutes == 20)
    }

    static let documentedFile = """
        {
          "audioMode" : "wired",
          "auto" : true,
          "lowDiskWarningMinutes" : 20,
          "outputFolder" : "~/Movies/Multi Screen Recorder",
          "requiredRecordingHours" : 2,
          "resolution" : "native",
          "systemAudio" : true
        }

        """

    @Test func defaultsRenderExactlyAsTheDocumentedFile() throws {
        #expect(String(decoding: try Settings.defaults.jsonData(), as: UTF8.self) == Self.documentedFile)
    }

    @Test func theDesignDocumentsTheDefaults() throws {
        #expect(try repositoryFile("docs/design/recorder.md").contains("```json\n\(Self.documentedFile)```\n"))
    }

    @Test func flagNamesAreTheKeysInKebabCase() {
        #expect(SettingKey.allCases.map(\.flagName) == [
            "--auto", "--resolution", "--audio-mode", "--system-audio", "--output-folder",
            "--required-recording-hours", "--low-disk-warning-minutes",
        ])
    }

    @Test func theFileHasExactlyTheKeysOfSettingKey() throws {
        let object = try #require(JSONSerialization.jsonObject(with: try Settings.defaults.jsonData()) as? [String: Any])
        #expect(Set(object.keys) == Set(SettingKey.allCases.map(\.rawValue)))
    }

    @Test func autoModesChoicesAreTheDefaultsOfTheTwoSliders() {
        #expect(Settings.defaults.resolution == Settings.autoResolution)
        #expect(Settings.defaults.audioMode == Settings.autoAudioMode)
    }
}

@Suite struct AutoModeTests {
    private var chosen: Settings {
        var settings = Settings.defaults
        settings.resolution = .p720
        settings.audioMode = .none
        return settings
    }

    @Test func withAutoOnTheChoicesAreNativeAndWiredWhateverTheSlidersSay() {
        var settings = chosen
        settings.auto = true
        #expect(settings.effectiveResolution == .native)
        #expect(settings.effectiveAudioMode == .wired)
    }

    @Test func withAutoOffTheSlidersDecide() {
        var settings = chosen
        settings.auto = false
        #expect(settings.effectiveResolution == .p720)
        #expect(settings.effectiveAudioMode == .none)
    }

    @Test func turningAutoOffChangesNothingUntilASliderIsMoved() {
        var settings = Settings.defaults
        let before = (settings.effectiveResolution, settings.effectiveAudioMode)
        settings.auto = false
        #expect(settings.effectiveResolution == before.0)
        #expect(settings.effectiveAudioMode == before.1)
    }
}

@Suite struct AudioModeTests {
    @Test func theFourStepsInSliderOrderWithTheirWords() {
        #expect(AudioMode.allCases.map(\.rawValue) == ["none", "default-microphone", "wired", "all-inputs"])
        #expect(AudioMode.allCases.map(\.label) == ["None", "Default microphone", "Wired", "All"])
    }

    @Test func theSliderIndexRoundTrips() {
        for (index, mode) in AudioMode.allCases.enumerated() {
            #expect(mode.sliderIndex == Double(index))
            #expect(mode.choosing(sliderPosition: Double(index)) == nil)
        }
        #expect(AudioMode.none.choosing(sliderPosition: 2) == .wired)
        #expect(AudioMode.none.choosing(sliderPosition: 99) == .allInputs)
        #expect(AudioMode.allInputs.choosing(sliderPosition: -1) == AudioMode.none)
    }

    @Test func theNoteUnderTheSliderIsInTheDesign() throws {
        let note = AudioMode.bluetoothAndVirtualNote
        #expect(note.hasPrefix("Bluetooth and virtual microphones are recorded only under All, or when they are the default microphone"))
        #expect(try repositoryFile("docs/design/recorder.md").replacing("\n", with: " ")
            .replacing(/\s+/) { _ in " " }.contains(note))
    }

    private func input(_ transport: AudioTransport, isDefault: Bool = false) -> AudioInputInfo {
        AudioInputInfo(name: "X", channelCount: 1, isDefault: isDefault, transport: transport)
    }

    private func records(_ mode: AudioMode, _ input: AudioInputInfo) -> Bool {
        var settings = Settings.defaults
        settings.auto = false
        settings.audioMode = mode
        return settings.records(input)
    }

    @Test(arguments: [
        (AudioTransport.builtIn, true), (.usb, true), (.fireWire, true), (.pci, true), (.thunderbolt, true),
        (.hdmi, true), (.displayPort, true),
        (.bluetooth, false), (.bluetoothLE, false), (.virtual, false), (.aggregate, false), (.airPlay, false),
        (.continuityCapture, false), (.unknown, false), (.unreadable, false),
    ])
    func onlyBuiltInAndWiredTransportsAreWired(transport: AudioTransport, isWired: Bool) {
        #expect(transport.isWired == isWired)
    }

    @Test func everyTransportIsClassified() {
        #expect(AudioTransport.allCases.count == 15)
    }

    @Test(arguments: AudioTransport.allCases)
    func theDefaultMicrophoneIsRecordedInEveryModeButNone(transport: AudioTransport) {
        for mode in AudioMode.allCases where mode != .none {
            #expect(records(mode, input(transport, isDefault: true)))
        }
        #expect(!records(.none, input(transport, isDefault: true)))
    }

    @Test(arguments: AudioTransport.allCases)
    func otherInputsFollowTheMode(transport: AudioTransport) {
        let other = input(transport)
        #expect(!records(.none, other))
        #expect(!records(.defaultMicrophone, other))
        #expect(records(.wired, other) == transport.isWired)
        #expect(records(.allInputs, other))
    }

    @Test func autoModeRecordsWhatWiredRecords() {
        #expect(Settings.defaults.records(input(.usb)))
        #expect(!Settings.defaults.records(input(.bluetooth)))
        #expect(Settings.defaults.records(input(.bluetooth, isDefault: true)))
    }
}

@Suite struct SettingsJSONTests {
    private func read(_ text: String) -> SettingsRead {
        Settings.read(json: Data(text.utf8))
    }

    @Test func roundTripsThroughJSON() throws {
        var settings = Settings.defaults
        settings.auto = false
        settings.resolution = .p1080
        settings.audioMode = .allInputs
        settings.systemAudio = false
        settings.outputFolder = "/Volumes/Data/Recordings \"quoted\" \\ back"
        settings.requiredRecordingHours = 1.5
        settings.lowDiskWarningMinutes = 5
        #expect(Settings.read(json: try settings.jsonData()) == SettingsRead(settings: settings, ignored: []))
    }

    @Test func slashesAreWrittenAsTheyAre() throws {
        #expect(String(decoding: try Settings.defaults.jsonData(), as: UTF8.self)
            .contains(#""outputFolder" : "~/Movies/Multi Screen Recorder""#))
    }

    @Test func aVeryLargeNumberIsWrittenAsSwiftWritesItAndReadBack() throws {
        var settings = Settings.defaults
        settings.requiredRecordingHours = 1e20
        #expect(String(decoding: try settings.jsonData(), as: UTF8.self).contains(#""requiredRecordingHours" : 1e+20,"#))
        #expect(Settings.read(json: try settings.jsonData()).settings == settings)
    }

    @Test func missingKeysTakeTheirDefaultAndAreNotIgnored() {
        var expected = Settings.defaults
        expected.resolution = .p720
        #expect(read(#"{"resolution": "720p"}"#) == SettingsRead(settings: expected, ignored: []))
    }

    @Test func aFileOfBeforeAutoModeStaysValid() {
        let old = read(#"{"resolution": "native", "audioMode": "default-microphone", "systemAudio": false}"#)
        #expect(old.ignored.isEmpty)
        #expect(old.settings.resolution == .native)
        #expect(old.settings.audioMode == .defaultMicrophone)
        #expect(old.settings.systemAudio == false)
        #expect(old.settings.auto == true)
    }

    @Test func allInputsIsAValidAudioModeNow() {
        #expect(read(#"{"audioMode": "all-inputs"}"#).settings.audioMode == .allInputs)
    }

    @Test func anUnknownKeyIsIgnoredAndNamedAndTheRestIsRead() {
        let result = read(#"{"resolution": "720p", "agc": true}"#)
        #expect(result.settings.resolution == .p720)
        #expect(result.ignored == [IgnoredSetting(key: "agc", reason: "unknown key")])
    }

    @Test(arguments: [
        (#"{"auto": "yes"}"#, "auto"),
        (#"{"resolution": "999p"}"#, "resolution"),
        (#"{"resolution": 1080}"#, "resolution"),
        (#"{"audioMode": "loud"}"#, "audioMode"),
        (#"{"audioMode": true}"#, "audioMode"),
        (#"{"systemAudio": "on"}"#, "systemAudio"),
        (#"{"systemAudio": 1}"#, "systemAudio"),
        (#"{"outputFolder": ""}"#, "outputFolder"),
        (#"{"outputFolder": "relative/folder"}"#, "outputFolder"),
        (#"{"outputFolder": 3}"#, "outputFolder"),
        (#"{"requiredRecordingHours": 0}"#, "requiredRecordingHours"),
        (#"{"requiredRecordingHours": -1}"#, "requiredRecordingHours"),
        (#"{"requiredRecordingHours": "2"}"#, "requiredRecordingHours"),
        (#"{"requiredRecordingHours": true}"#, "requiredRecordingHours"),
        (#"{"lowDiskWarningMinutes": null}"#, "lowDiskWarningMinutes"),
    ])
    func anInvalidValueIsIgnoredAndNamedAndTheKeyTakesItsDefault(json: String, key: String) throws {
        let result = read(json)
        #expect(result.settings == .defaults)
        let ignored = try #require(result.ignored.first)
        #expect(result.ignored.count == 1)
        #expect(ignored.key == key)
        #expect(ignored.reason.hasPrefix("invalid value, expected "))
    }

    @Test func oneInvalidKeyLeavesTheValidOnesRead() {
        let result = read(#"{"resolution": "999p", "audioMode": "none", "systemAudio": false}"#)
        #expect(result.settings.audioMode == AudioMode.none)
        #expect(result.settings.systemAudio == false)
        #expect(result.settings.resolution == Settings.defaults.resolution)
    }

    @Test func notJSONGivesTheDefaultsAndIgnoresTheWholeFile() {
        #expect(read("{ not json") == SettingsRead(
            settings: .defaults, ignored: [IgnoredSetting(key: "the whole file", reason: "not valid JSON")]))
    }

    @Test func aJSONArrayIsIgnoredAsAWhole() {
        #expect(read("[]") == SettingsRead(
            settings: .defaults, ignored: [IgnoredSetting(key: "the whole file", reason: "not a JSON object")]))
    }

    @Test func theStandardErrorLineNamesEverythingIgnoredInKeyOrder() throws {
        let result = read(#"{"resolution": "999p", "agc": true}"#)
        #expect(result.note == "Settings file: ignored agc (unknown key),"
            + " resolution (invalid value, expected one of native, 4k, 1440p, 1200p, 1080p, 720p);"
            + " using defaults for those.")
    }

    @Test func nothingIgnoredNoLine() {
        #expect(read("{}").note == nil)
    }
}

@Suite struct SettingsFlagTests {
    @Test func flagsOverrideTheSettings() throws {
        let settings = try Settings.defaults.applying(flags: [
            .resolution: "720p",
            .audioMode: "none",
            .systemAudio: "off",
            .outputFolder: "~/Desktop/Recordings",
            .requiredRecordingHours: "0.5",
            .lowDiskWarningMinutes: "10",
        ])
        #expect(settings == Settings(
            auto: false,
            resolution: .p720,
            audioMode: .none,
            systemAudio: false,
            outputFolder: "~/Desktop/Recordings",
            requiredRecordingHours: 0.5,
            lowDiskWarningMinutes: 10
        ))
    }

    @Test func noFlagsChangeNothing() throws {
        #expect(try Settings.defaults.applying(flags: [:]) == .defaults)
    }

    @Test(arguments: [(SettingKey.resolution, "1080p"), (.audioMode, "all-inputs")])
    func aChoiceFlagTurnsAutoOffForTheRunAndSetsTheChoice(key: SettingKey, value: String) throws {
        let settings = try Settings.defaults.applying(flags: [key: value])
        #expect(settings.auto == false)
        #expect(key == .resolution ? settings.resolution == .p1080 : settings.audioMode == .allInputs)
    }

    @Test func otherFlagsKeepAuto() throws {
        #expect(try Settings.defaults.applying(flags: [.systemAudio: "off", .outputFolder: "/tmp"]).auto == true)
    }

    @Test func autoForcesAutoModeWhateverTheFileSays() throws {
        var file = Settings.defaults
        file.auto = false
        file.resolution = .p720
        let settings = try file.applying(flags: [:], auto: true)
        #expect(settings.auto == true)
        #expect(settings.effectiveResolution == .native)
        #expect(settings.resolution == .p720)
    }

    @Test(arguments: [SettingKey.resolution, .audioMode])
    func autoWithAChoiceFlagIsAConflict(key: SettingKey) throws {
        let error = try #require(throws: SettingsError.self) {
            try Settings.defaults.applying(flags: [key: key == .resolution ? "720p" : "none"], auto: true)
        }
        #expect(error == .conflictingFlags(flag: key.flagName))
        #expect(error.description == "--auto cannot be combined with \(key.flagName)")
    }

    @Test func systemAudioFlagTakesOnAndOff() throws {
        var settings = Settings.defaults
        settings.systemAudio = false
        #expect(try settings.applying(flags: [.systemAudio: "on"]).systemAudio == true)
        #expect(try Settings.defaults.applying(flags: [.systemAudio: "off"]).systemAudio == false)
    }

    @Test(arguments: [
        (SettingKey.resolution, "999p"),
        (.audioMode, "loud"),
        (.systemAudio, "true"),
        (.outputFolder, ""),
        (.requiredRecordingHours, "two"),
        (.requiredRecordingHours, "0"),
        (.lowDiskWarningMinutes, "-5"),
        (.lowDiskWarningMinutes, "nan"),
    ])
    func invalidFlagValueNamesTheFlag(key: SettingKey, value: String) throws {
        let error = try #require(throws: SettingsError.self) {
            try Settings.defaults.applying(flags: [key: value])
        }
        guard case .invalidFlagValue(let flag, let namedValue, _) = error else {
            Issue.record("expected an invalid flag value error, got \(error)")
            return
        }
        #expect(flag == key.flagName)
        #expect(namedValue == value)
        #expect(error.description.contains(key.flagName))
    }
}

@Suite struct OutputFolderTests {
    private let home = URL(filePath: "/Users/someone", directoryHint: .isDirectory)

    private func folder(_ path: String) -> String {
        var settings = Settings.defaults
        settings.outputFolder = path
        return settings.outputFolderURL(homeFolder: home).path(percentEncoded: false)
    }

    @Test func tildeExpandsToTheHomeFolder() {
        #expect(folder("~/Movies/Multi Screen Recorder") == "/Users/someone/Movies/Multi Screen Recorder/")
        #expect(folder("~") == "/Users/someone/")
    }

    @Test func absolutePathsStayAsTheyAre() {
        #expect(folder("/Volumes/Data/Recordings") == "/Volumes/Data/Recordings/")
    }

    @Test func aChosenFolderInTheHomeFolderIsWrittenWithTilde() {
        let chosen = URL(filePath: "/Users/someone/Movies/Talks", directoryHint: .isDirectory)
        #expect(Settings.outputFolderSetting(for: chosen, homeFolder: home) == "~/Movies/Talks")
        #expect(Settings.outputFolderSetting(for: home, homeFolder: home) == "~")
    }

    @Test func aChosenFolderElsewhereIsWrittenAsItsPath() {
        let chosen = URL(filePath: "/Volumes/Data/Recordings", directoryHint: .isDirectory)
        #expect(Settings.outputFolderSetting(for: chosen, homeFolder: home) == "/Volumes/Data/Recordings")
        let lookalike = URL(filePath: "/Users/someoneelse/Movies", directoryHint: .isDirectory)
        #expect(Settings.outputFolderSetting(for: lookalike, homeFolder: home) == "/Users/someoneelse/Movies")
    }
}

@Suite struct SettingsFileTests {
    private let folder: URL

    init() throws {
        folder = FileManager.default.temporaryDirectory
            .appending(path: "SettingsFileTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    }

    private var file: SettingsFile {
        SettingsFile(url: folder.appending(path: "nested/settings.json"))
    }

    private func write(_ text: String) throws {
        try FileManager.default.createDirectory(
            at: file.url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: file.url)
    }

    @Test func theStandardLocationIsInApplicationSupport() {
        let standard = SettingsFile.standard(homeFolder: URL(filePath: "/Users/someone", directoryHint: .isDirectory))
        #expect(
            standard.url.path(percentEncoded: false)
                == "/Users/someone/Library/Application Support/Multi Screen Recorder/settings.json"
        )
    }

    @Test func aMissingFileGivesTheDefaultsAndIsNotWritten() {
        defer { try? FileManager.default.removeItem(at: folder) }
        #expect(file.load() == SettingsRead(settings: .defaults, ignored: []))
        #expect(!FileManager.default.fileExists(atPath: file.url.path(percentEncoded: false)))
        #expect(!FileManager.default.fileExists(atPath: folder.path(percentEncoded: false)))
    }

    @Test func saveThenLoadReturnsTheSavedSettings() throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        var settings = Settings.defaults
        settings.auto = false
        settings.resolution = .p1440
        try file.save(settings)
        #expect(file.load() == SettingsRead(settings: settings, ignored: []))
    }

    @Test func aFileWithAnUnknownKeyIsReadAndLeftAsItIs() throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        try write(#"{"bogus": 1, "resolution": "720p"}"#)
        let result = file.load()
        #expect(result.settings.resolution == .p720)
        #expect(result.ignored == [IgnoredSetting(key: "bogus", reason: "unknown key")])
        #expect(try String(contentsOf: file.url, encoding: .utf8) == #"{"bogus": 1, "resolution": "720p"}"#)
        #expect(!FileManager.default.fileExists(atPath: file.url.path(percentEncoded: false) + ".previous"))
    }

    @Test func aBrokenFileGivesTheDefaultsAndIsLeftAsItIs() throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        try write("garbage")
        #expect(file.load() == SettingsRead(
            settings: .defaults, ignored: [IgnoredSetting(key: "the whole file", reason: "not valid JSON")]))
        #expect(try String(contentsOf: file.url, encoding: .utf8) == "garbage")
    }

    @Test func aFileThatCannotBeReadGivesTheDefaultsAndSaysWhy() throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        // A folder where the file must be: it exists and cannot be read as a file.
        try FileManager.default.createDirectory(at: file.url, withIntermediateDirectories: true)
        let result = file.load()
        #expect(result.settings == .defaults)
        #expect(result.ignored.map(\.key) == ["the whole file"])
        #expect(result.ignored.first?.reason.hasPrefix("cannot be read: ") == true)
    }

    @Test func aFailedWriteIsAReadableErrorNamingTheFile() throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        // A plain file where the folder must be, so the folder cannot be created.
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data().write(to: folder.appending(path: "nested"))
        let error = try #require(throws: SettingsFileError.self) { try file.save(.defaults) }
        #expect(error.description.contains("settings.json"))
        #expect(error.description.contains("cannot be written"))
        #expect(!error.description.contains("Error Domain="))
    }
}
