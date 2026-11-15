import Foundation
import Testing

/// Runs the built `msr` with a scratch HOME. Only the commands that raise no
/// permission prompt: `msr settings` and `msr version`.
@Suite struct MSRTests {
    private let home: ScratchFolder

    init() throws {
        home = try ScratchFolder("MSRTests")
    }

    private var settingsFile: URL {
        home.url.appending(path: "Library/Application Support/Multi Screen Recorder/settings.json")
    }

    private func writeSettings(_ text: String) throws {
        try FileManager.default.createDirectory(
            at: settingsFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: settingsFile)
    }

    private func msr(_ arguments: String..., home: String? = nil) throws -> CommandOutcome {
        try msr(arguments, home: home)
    }

    private func msr(_ arguments: [String], home: String? = nil) throws -> CommandOutcome {
        try run(try buildProducts().appending(path: "msr"), arguments,
                environment: ["HOME": home ?? self.home.url.path(percentEncoded: false)])
    }

    private var settingsFileExists: Bool {
        FileManager.default.fileExists(atPath: settingsFile.path(percentEncoded: false))
    }

    private func savedSettings() throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: Data(contentsOf: settingsFile)) as? [String: Any])
    }

    @Test func settingsPrintsTheDefaultsAndWritesNothing() throws {
        defer { home.remove() }
        let outcome = try msr("settings")
        #expect(outcome.status == 0)
        #expect(outcome.output.contains(#""requiredRecordingHours" : 2"#))
        #expect(outcome.output.contains(#""auto" : true"#))
        #expect(outcome.output.contains(#""resolution" : "native""#))
        #expect(outcome.output.contains(#""audioMode" : "wired""#))
        #expect(outcome.errors.isEmpty)
        #expect(!settingsFileExists)
    }

    @Test func aFlagSavesTheEffectiveSettingsWholeAndPrintsThem() throws {
        defer { home.remove() }
        let outcome = try msr("settings", "--system-audio", "off")
        #expect(outcome.status == 0)
        #expect(try String(contentsOf: settingsFile, encoding: .utf8) == outcome.output)
        #expect(try savedSettings()["systemAudio"] as? Bool == false)
    }

    @Test func aResolutionFlagSavesAndTurnsAutoOff() throws {
        defer { home.remove() }
        #expect(try msr("settings", "--resolution", "1080p").status == 0)
        let saved = try savedSettings()
        #expect(saved["resolution"] as? String == "1080p")
        #expect(saved["auto"] as? Bool == false)
    }

    @Test func anAudioModeFlagSavesAndTurnsAutoOff() throws {
        defer { home.remove() }
        #expect(try msr("settings", "--audio-mode", "all-inputs").status == 0)
        let saved = try savedSettings()
        #expect(saved["audioMode"] as? String == "all-inputs")
        #expect(saved["auto"] as? Bool == false)
    }

    @Test func theAutoFlagSavesAutoOn() throws {
        defer { home.remove() }
        try writeSettings(#"{"auto": false, "resolution": "720p"}"#)
        #expect(try msr("settings", "--auto").status == 0)
        let saved = try savedSettings()
        #expect(saved["auto"] as? Bool == true)
        #expect(saved["resolution"] as? String == "720p")
    }

    @Test func plainSettingsOnlyShowsAndLeavesTheFileAsItIs() throws {
        defer { home.remove() }
        let content = #"{"auto": false}"#
        try writeSettings(content)
        #expect(try msr("settings").output.contains(#""auto" : false"#))
        #expect(try String(contentsOf: settingsFile, encoding: .utf8) == content)
    }

    @Test func saveIsNoLongerAFlag() throws {
        defer { home.remove() }
        #expect(try msr("settings", "--save").status == 64)
        #expect(try msr("settings", "--resolution", "720p", "--save").status == 64)
        #expect(!settingsFileExists)
    }

    @Test(arguments: [["--resolution", "720p"], ["--audio-mode", "none"]])
    func autoWithAChoiceFlagIsAUsageError(choice: [String]) throws {
        defer { home.remove() }
        let outcome = try msr(["settings", "--auto"] + choice)
        #expect(outcome.status == 64)
        #expect(outcome.errors.contains("--auto cannot be combined with \(choice[0])"))
        #expect(!settingsFileExists)
    }

    @Test func aSettingsFileWithAnUnknownKeyIsNeverRefused() throws {
        defer { home.remove() }
        try writeSettings(#"{"agc": true, "resolution": "720p"}"#)
        let outcome = try msr("settings")
        #expect(outcome.status == 0)
        #expect(outcome.errors == "Settings file: ignored agc (unknown key); using defaults for those.\n")
        #expect(outcome.output.contains(#""resolution" : "720p""#))
    }

    @Test func aBrokenSettingsFileGivesTheDefaultsAndIsLeftAsItIs() throws {
        defer { home.remove() }
        try writeSettings("garbage")
        let outcome = try msr("settings")
        #expect(outcome.status == 0)
        #expect(outcome.errors == "Settings file: ignored the whole file (not valid JSON); using defaults for those.\n")
        #expect(outcome.output.contains(#""auto" : true"#))
        #expect(try String(contentsOf: settingsFile, encoding: .utf8) == "garbage")
    }

    @Test func aSettingsFileWithAnInvalidValueIsNeverRefused() throws {
        defer { home.remove() }
        try writeSettings(#"{"audioMode": "loud"}"#)
        let outcome = try msr("settings")
        #expect(outcome.status == 0)
        #expect(outcome.errors.contains("ignored audioMode (invalid value, expected one of none, default-microphone, wired, all-inputs)"))
        #expect(outcome.output.contains(#""audioMode" : "wired""#))
    }

    @Test func aFileOfBeforeAutoModeIsReadWithoutAWord() throws {
        defer { home.remove() }
        try writeSettings(#"{"resolution": "native", "audioMode": "default-microphone"}"#)
        let outcome = try msr("settings")
        #expect(outcome.status == 0)
        #expect(outcome.errors.isEmpty)
        #expect(outcome.output.contains(#""audioMode" : "default-microphone""#))
    }

    @Test func aChangeThatCannotBeWrittenExits1NamingTheFile() throws {
        defer { home.remove() }
        // A plain file where the Library folder must be.
        try Data().write(to: home.url.appending(path: "Library"))
        let outcome = try msr("settings", "--system-audio", "off")
        #expect(outcome.status == 1)
        #expect(outcome.errors.contains("settings.json"))
        #expect(outcome.errors.contains("cannot be written"))
    }

    @Test func anUnsetHomeExits78() throws {
        defer { home.remove() }
        let outcome = try msr("settings", home: "")
        #expect(outcome.status == 78)
        #expect(outcome.errors.contains("HOME is not set"))
    }

    @Test func versionDoesNotReadTheSettings() throws {
        defer { home.remove() }
        try writeSettings(#"{"agc": true}"#)
        let outcome = try msr("version")
        #expect(outcome.status == 0)
        #expect(outcome.errors.isEmpty)
        #expect(outcome.output == "development build (not bundled)\n")
    }

    @Test func aUsageErrorExits64() throws {
        defer { home.remove() }
        #expect(try msr("settings", "--resolution", "999p").status == 64)
    }
}
