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
        try run(try buildProducts().appending(path: "msr"), arguments,
                environment: ["HOME": home ?? self.home.url.path(percentEncoded: false)])
    }

    @Test func settingsPrintsTheDefaultsAndWritesThem() throws {
        defer { home.remove() }
        let outcome = try msr("settings")
        #expect(outcome.status == 0)
        #expect(outcome.output.contains(#""requiredRecordingHours": 2"#))
        #expect(try String(contentsOf: settingsFile, encoding: .utf8) == outcome.output)
    }

    @Test func anUnusableSettingsFileExits78NamingTheKey() throws {
        defer { home.remove() }
        try writeSettings(#"{"agc": true}"#)
        let outcome = try msr("settings")
        #expect(outcome.status == 78)
        #expect(outcome.errors.contains(#"unknown key "agc""#))
        #expect(outcome.errors.contains(settingsFile.path(percentEncoded: false)))
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
        #expect(outcome.output == "development build (not bundled)\n")
    }

    @Test func aUsageErrorExits64() throws {
        defer { home.remove() }
        #expect(try msr("settings", "--resolution", "999p").status == 64)
    }
}
