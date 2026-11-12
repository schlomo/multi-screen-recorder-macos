import Foundation
import RecorderLogic
import Testing
@testable import RecorderCore

/// File-system only: each test works in a scratch folder of its own.
@Suite struct OutputFolderProbeTests {
    private let scratch: URL

    init() throws {
        scratch = FileManager.default.temporaryDirectory
            .appending(path: "OutputFolderProbeTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
    }

    private func removeScratch() throws {
        try makeWritable(scratch)
        try FileManager.default.removeItem(at: scratch)
    }

    private func makeWritable(_ folder: URL) throws {
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: folder.path(percentEncoded: false))
    }

    private func makeReadOnly(_ folder: URL) throws {
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: folder.path(percentEncoded: false))
    }

    private func contents(of folder: URL) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: folder.path(percentEncoded: false))
    }

    private func isUsableWithFreeSpace(_ probe: OutputFolderProbe) -> Bool {
        guard case .usable(.bytes(let bytes)) = probe else { return false }
        return bytes > 0
    }

    @Test func anExistingFolderIsUsableAndKeepsNoProbeFile() throws {
        defer { try? removeScratch() }
        let folder = scratch.appending(path: "Recordings", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        #expect(isUsableWithFreeSpace(probeOutputFolder(folder)))
        #expect(try contents(of: folder).isEmpty)
    }

    @Test func aMissingFolderIsCreatedWithItsParents() throws {
        defer { try? removeScratch() }
        let folder = scratch.appending(path: "Movies/Multi Screen Recorder", directoryHint: .isDirectory)
        #expect(isUsableWithFreeSpace(probeOutputFolder(folder)))
        var isDirectory: ObjCBool = false
        #expect(FileManager.default.fileExists(atPath: folder.path(percentEncoded: false), isDirectory: &isDirectory))
        #expect(isDirectory.boolValue)
        #expect(try contents(of: folder).isEmpty)
    }

    @Test func aReadOnlyFolderIsUnusable() throws {
        defer { try? removeScratch() }
        let folder = scratch.appending(path: "Locked", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        try makeReadOnly(folder)
        defer { try? makeWritable(folder) }
        guard case .unusable(let reason) = probeOutputFolder(folder) else {
            Issue.record("a read-only folder was reported usable")
            return
        }
        #expect(!reason.isEmpty)
    }

    @Test func aFolderThatCannotBeCreatedIsUnusable() throws {
        defer { try? removeScratch() }
        let parent = scratch.appending(path: "Locked", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: false)
        try makeReadOnly(parent)
        defer { try? makeWritable(parent) }
        let folder = parent.appending(path: "Recordings", directoryHint: .isDirectory)
        guard case .unusable(let reason) = probeOutputFolder(folder) else {
            Issue.record("a folder in a read-only parent was reported usable")
            return
        }
        #expect(!reason.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: folder.path(percentEncoded: false)))
    }

    @Test func aFileInTheWayIsUnusable() throws {
        defer { try? removeScratch() }
        let folder = scratch.appending(path: "Recordings")
        try Data("not a folder".utf8).write(to: folder)
        guard case .unusable(let reason) = probeOutputFolder(folder) else {
            Issue.record("a file was reported as a usable folder")
            return
        }
        #expect(!reason.isEmpty)
        #expect(try String(contentsOf: folder, encoding: .utf8) == "not a folder")
    }
}

@Suite struct MicrophoneProbeTests {
    /// Without a microphone there is nothing to open: the granted permission
    /// stands, and the ready check's audio item alone reports the missing
    /// microphone. Opening a real microphone needs the permission and a
    /// device, so it is checked on a Mac by a person, not here.
    @Test func noMicrophoneLeavesTheGrantStanding() {
        #expect(openMicrophone(nil) == .granted)
    }
}
