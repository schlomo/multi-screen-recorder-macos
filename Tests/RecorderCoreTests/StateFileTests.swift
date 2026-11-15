import Foundation
import Testing
@testable import RecorderCore
import RecorderLogic

@Suite struct StateFileTests {
    private func scratchHome() throws -> URL {
        let home = FileManager.default.temporaryDirectory.appending(path: "state-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        return home
    }

    @Test func theFileLivesNextToTheSettingsFile() throws {
        let home = try scratchHome()
        defer { try? FileManager.default.removeItem(at: home) }
        #expect(StateFile(homeFolder: home).url == home.appending(path: "Library/Application Support/Multi Screen Recorder/state.json"))
    }

    @Test func aMissingFileMeansNothingOfferedYet() throws {
        let home = try scratchHome()
        defer { try? FileManager.default.removeItem(at: home) }
        #expect(try StateFile(homeFolder: home).load() == .empty)
    }

    @Test func savedStateIsLoadedAgain() throws {
        let home = try scratchHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let file = StateFile(homeFolder: home)
        let state = AppState(lastOfferedCrashReport: "msr-2026-11-14-212425.ips")
        try file.save(state)
        #expect(try file.load() == state)
    }

    @Test func aBrokenFileIsAnErrorNamingTheFile() throws {
        let home = try scratchHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let file = StateFile(homeFolder: home)
        try FileManager.default.createDirectory(at: file.url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: file.url)
        #expect {
            try file.load()
        } throws: { ($0 as? StateFileError)?.description.contains("state.json") == true }
        do { _ = try file.load() } catch { #expect(error.localizedDescription.contains("state.json")) }
    }
}
