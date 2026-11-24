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
        let error = #expect(throws: StateFileError.self) { try file.load() }
        #expect(error?.localizedDescription.contains("state.json") == true)
    }

    @Test func aFailedWriteIsAReadableError() throws {
        let home = try scratchHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let file = StateFile(homeFolder: home)
        // A plain file where the Library folder must be, so the folder cannot be created.
        try Data().write(to: home.appending(path: "Library"))
        let error = #expect(throws: StateFileError.self) { try file.save(.empty) }
        let message = error?.localizedDescription ?? ""
        #expect(message.contains("state.json"))
        #expect(!message.contains("Error Domain="))
    }

    @Test func anUpdateKeepsWhatItDoesNotChange() throws {
        let home = try scratchHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let file = StateFile(homeFolder: home)
        try file.save(AppState(lastOfferedCrashReport: "msr-2026-11-14-212425.ips"))
        try file.update { $0.recorded(folder: "/r", result: .problems, noticeWanted: true) }
        #expect(try file.load() == AppState(
            lastOfferedCrashReport: "msr-2026-11-14-212425.ips",
            lastRecording: AppState.LastRecording(folder: "/r", result: .problems, noticeWanted: true)))
    }
}
