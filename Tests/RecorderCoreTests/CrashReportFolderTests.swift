import Foundation
import Testing
@testable import RecorderCore

@Suite struct CrashReportFolderTests {
    private func scratchHome(_ files: [String]?) throws -> URL {
        let home = FileManager.default.temporaryDirectory
            .appending(path: "crash-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        guard let files else { return home }
        let reports = home.appending(path: "Library/Logs/DiagnosticReports", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: reports.appending(path: "Retired"), withIntermediateDirectories: true)
        for name in files { try Data().write(to: reports.appending(path: name)) }
        try Data().write(to: reports.appending(path: "Retired/msr-2030-01-01-000000.ips"))
        return home
    }

    @Test func listsTheTopLevelEntriesNotWhatIsInRetired() throws {
        let home = try scratchHome(["msr-2026-11-14-212425.ips", "other-2026-11-14-212425.ips"])
        defer { try? FileManager.default.removeItem(at: home) }
        #expect(try crashReportFileNames(homeFolder: home).sorted() == ["Retired", "msr-2026-11-14-212425.ips", "other-2026-11-14-212425.ips"])
    }

    @Test func theTextCopyIsMadeAndReplaced() throws {
        let home = try scratchHome(["msr-2026-11-14-212425.ips"])
        defer { try? FileManager.default.removeItem(at: home) }
        let reports = crashReportFolder(homeFolder: home)
        try Data("first".utf8).write(to: reports.appending(path: "msr-2026-11-14-212425.ips"))
        let copy = try makeTextCopy(of: "msr-2026-11-14-212425.ips", homeFolder: home)
        #expect(copy == home.appending(path: "Library/Application Support/Multi Screen Recorder/Crash Reports/msr-2026-11-14-212425.txt"))
        #expect(try String(contentsOf: copy, encoding: .utf8) == "first")
        try Data("second".utf8).write(to: reports.appending(path: "msr-2026-11-14-212425.ips"))
        _ = try makeTextCopy(of: "msr-2026-11-14-212425.ips", homeFolder: home)
        #expect(try String(contentsOf: copy, encoding: .utf8) == "second")
    }

    @Test func copyingAMissingCrashReportIsAnError() throws {
        let home = try scratchHome([])
        defer { try? FileManager.default.removeItem(at: home) }
        #expect(throws: (any Error).self) {
            try makeTextCopy(of: "msr-2026-11-14-212425.ips", homeFolder: home)
        }
    }

    @Test func aMissingFolderMeansNoReports() throws {
        let home = try scratchHome(nil)
        defer { try? FileManager.default.removeItem(at: home) }
        #expect(try crashReportFileNames(homeFolder: home).isEmpty)
    }

    @Test func anUnreadableFolderIsAnError() throws {
        // Assumes a non-root user: root reads a folder without permissions.
        let home = try scratchHome([])
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: crashReportFolder(homeFolder: home).path(percentEncoded: false))
            try? FileManager.default.removeItem(at: home)
        }
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: crashReportFolder(homeFolder: home).path(percentEncoded: false))
        #expect(throws: (any Error).self) { try crashReportFileNames(homeFolder: home) }
    }
}
