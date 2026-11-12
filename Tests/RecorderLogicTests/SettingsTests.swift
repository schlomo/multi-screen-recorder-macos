import Foundation
import Testing
@testable import RecorderLogic

@Suite struct SettingsDefaultsTests {
    @Test func defaultsMatchTheDesign() {
        let defaults = Settings.defaults
        #expect(defaults.resolution == .p1080)
        #expect(defaults.audioMode == .defaultMicrophone)
        #expect(defaults.systemAudio == true)
        #expect(defaults.outputFolder == "~/Movies/Multi Screen Recorder")
        #expect(defaults.readyCheckHours == 2)
        #expect(defaults.lowDiskWarningMinutes == 20)
    }

    @Test func defaultsRenderExactlyAsTheDocumentedFile() {
        let expected = """
            {
              "resolution": "1080p",
              "audioMode": "default-microphone",
              "systemAudio": true,
              "outputFolder": "~/Movies/Multi Screen Recorder",
              "readyCheckHours": 2,
              "lowDiskWarningMinutes": 20
            }

            """
        #expect(Settings.defaults.json == expected)
    }

    @Test func flagNamesAreTheKeysInKebabCase() {
        #expect(SettingKey.allCases.map(\.flagName) == [
            "--resolution", "--audio-mode", "--system-audio", "--output-folder",
            "--ready-check-hours", "--low-disk-warning-minutes",
        ])
    }
}

@Suite struct SettingsJSONTests {
    private func decode(_ text: String) throws -> Settings {
        try Settings(json: Data(text.utf8))
    }

    @Test func roundTripsThroughJSON() throws {
        var settings = Settings.defaults
        settings.resolution = .native
        settings.audioMode = .none
        settings.systemAudio = false
        settings.outputFolder = "/Volumes/Data/Recordings \"quoted\" \\ back"
        settings.readyCheckHours = 1.5
        settings.lowDiskWarningMinutes = 5
        #expect(try decode(settings.json) == settings)
    }

    @Test func missingKeysTakeTheirDefault() throws {
        #expect(try decode(#"{"resolution": "720p"}"#) == {
            var settings = Settings.defaults
            settings.resolution = .p720
            return settings
        }())
    }

    @Test func unknownKeyIsNamed() {
        #expect(throws: SettingsError.unknownKey("agc")) {
            try decode(#"{"resolution": "720p", "agc": true}"#)
        }
    }

    @Test(arguments: [
        (#"{"resolution": "999p"}"#, "resolution"),
        (#"{"resolution": 1080}"#, "resolution"),
        (#"{"audioMode": "all-inputs"}"#, "audioMode"),
        (#"{"systemAudio": "on"}"#, "systemAudio"),
        (#"{"systemAudio": 1}"#, "systemAudio"),
        (#"{"outputFolder": ""}"#, "outputFolder"),
        (#"{"outputFolder": "relative/folder"}"#, "outputFolder"),
        (#"{"outputFolder": 3}"#, "outputFolder"),
        (#"{"readyCheckHours": 0}"#, "readyCheckHours"),
        (#"{"readyCheckHours": -1}"#, "readyCheckHours"),
        (#"{"readyCheckHours": "2"}"#, "readyCheckHours"),
        (#"{"readyCheckHours": true}"#, "readyCheckHours"),
        (#"{"lowDiskWarningMinutes": null}"#, "lowDiskWarningMinutes"),
    ])
    func invalidValueNamesTheKey(json: String, key: String) throws {
        let error = try #require(throws: SettingsError.self) { try decode(json) }
        guard case .invalidValue(let namedKey, _) = error else {
            Issue.record("expected an invalid value error, got \(error)")
            return
        }
        #expect(namedKey == key)
        #expect(error.description.contains("\"\(key)\""))
    }

    @Test func notJSONIsAnError() {
        #expect(throws: SettingsError.self) { try decode("{ not json") }
    }

    @Test func aJSONArrayIsNotASettingsFile() {
        #expect(throws: SettingsError.notAnObject) { try decode("[]") }
    }

    @Test func errorMessagesSayWhatIsWrong() {
        #expect(SettingsError.unknownKey("agc").description == #"unknown key "agc""#)
        #expect(
            SettingsError.invalidValue(key: "resolution", expected: "one of native, 4k").description
                == #"invalid value for "resolution", expected one of native, 4k"#
        )
    }
}

@Suite struct SettingsFlagTests {
    @Test func flagsOverrideTheSettings() throws {
        let settings = try Settings.defaults.applying(flags: [
            .resolution: "720p",
            .audioMode: "none",
            .systemAudio: "off",
            .outputFolder: "~/Desktop/Recordings",
            .readyCheckHours: "0.5",
            .lowDiskWarningMinutes: "10",
        ])
        #expect(settings == Settings(
            resolution: .p720,
            audioMode: .none,
            systemAudio: false,
            outputFolder: "~/Desktop/Recordings",
            readyCheckHours: 0.5,
            lowDiskWarningMinutes: 10
        ))
    }

    @Test func noFlagsChangeNothing() throws {
        #expect(try Settings.defaults.applying(flags: [:]) == .defaults)
    }

    @Test func systemAudioFlagTakesOnAndOff() throws {
        var settings = Settings.defaults
        settings.systemAudio = false
        #expect(try settings.applying(flags: [.systemAudio: "on"]).systemAudio == true)
        #expect(try Settings.defaults.applying(flags: [.systemAudio: "off"]).systemAudio == false)
    }

    @Test(arguments: [
        (SettingKey.resolution, "999p"),
        (.audioMode, "all-inputs"),
        (.systemAudio, "true"),
        (.outputFolder, ""),
        (.readyCheckHours, "two"),
        (.readyCheckHours, "0"),
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

    @Test func theStandardLocationIsInApplicationSupport() {
        let standard = SettingsFile.standard(homeFolder: URL(filePath: "/Users/someone", directoryHint: .isDirectory))
        #expect(
            standard.url.path(percentEncoded: false)
                == "/Users/someone/Library/Application Support/Multi Screen Recorder/settings.json"
        )
    }

    @Test func firstLoadWritesTheDefaults() throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        #expect(try file.load() == .defaults)
        let written = try String(contentsOf: file.url, encoding: .utf8)
        #expect(written == Settings.defaults.json)
    }

    @Test func saveThenLoadReturnsTheSavedSettings() throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        var settings = Settings.defaults
        settings.resolution = .p1440
        try file.save(settings)
        #expect(try file.load() == settings)
    }

    @Test func aBrokenFileIsReportedWithItsPathAndKey() throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(
            at: file.url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(#"{"bogus": 1}"#.utf8).write(to: file.url)
        let error = try #require(throws: SettingsFileError.self) { try file.load() }
        #expect(error.problem == .unknownKey("bogus"))
        #expect(error.description.contains(file.url.path(percentEncoded: false)))
        #expect(error.description.contains("\"bogus\""))
    }

    @Test func resetWritesTheDefaultsOverABrokenFile() throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(
            at: file.url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("garbage".utf8).write(to: file.url)
        try file.save(.defaults)
        #expect(try file.load() == .defaults)
    }
}
