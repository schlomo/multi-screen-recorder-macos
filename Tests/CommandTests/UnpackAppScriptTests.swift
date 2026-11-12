import Foundation
import Testing

/// Runs scripts/unpack-app on scratch archives in a scratch checkout, since
/// the script unpacks into the build/ folder of the repository it lives in.
@Suite struct UnpackAppScriptTests {
    private static let bundle = "Multi Screen Recorder.app"

    private let scratch: ScratchFolder
    private let checkout: URL
    private let sources: URL

    init() throws {
        scratch = try ScratchFolder("UnpackAppScriptTests")
        checkout = scratch.url.appending(path: "checkout", directoryHint: .isDirectory)
        let scripts = checkout.appending(path: "scripts", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: scripts, withIntermediateDirectories: true)
        try FileManager.default.copyItem(
            at: repositoryRoot.appending(path: "scripts/unpack-app"), to: scripts.appending(path: "unpack-app"))
        sources = scratch.url.appending(path: "sources/inner", directoryHint: .isDirectory)
        let macOS = sources.appending(path: "\(Self.bundle)/Contents/MacOS", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: macOS, withIntermediateDirectories: true)
        let program = macOS.appending(path: "msr")
        try Data("#!/bin/sh\n".utf8).write(to: program)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: program.path(percentEncoded: false))
    }

    private var build: URL { checkout.appending(path: "build", directoryHint: .isDirectory) }

    /// Archives the given members with bsdtar, run in the sources folder;
    /// -P keeps absolute paths and `..` as given.
    private func archive(_ members: String...) throws -> URL {
        let archive = scratch.url.appending(path: "app.tar")
        let outcome = try run(URL(filePath: "/usr/bin/env"),
                              ["tar", "-cPf", archive.path(percentEncoded: false)] + members, in: sources)
        try #require(outcome.status == 0, "tar failed: \(outcome.errors)")
        return archive
    }

    private func unpack(_ archive: URL) throws -> CommandOutcome {
        try run(checkout.appending(path: "scripts/unpack-app"), [archive.path(percentEncoded: false)], in: scratch.url)
    }

    private func buildContents() throws -> [String] {
        guard FileManager.default.fileExists(atPath: build.path(percentEncoded: false)) else { return [] }
        return try FileManager.default.contentsOfDirectory(atPath: build.path(percentEncoded: false))
    }

    @Test func aGoodArchiveIsUnpackedWithItsExecutableBit() throws {
        defer { scratch.remove() }
        let outcome = try unpack(try archive(Self.bundle))
        #expect(outcome.status == 0, "\(outcome.errors)")
        let program = build.appending(path: "\(Self.bundle)/Contents/MacOS/msr").path(percentEncoded: false)
        #expect(FileManager.default.isExecutableFile(atPath: program))
    }

    @Test func aSymbolicLinkInsideTheBundleIsAccepted() throws {
        defer { scratch.remove() }
        try FileManager.default.createSymbolicLink(
            atPath: sources.appending(path: "\(Self.bundle)/Contents/link").path(percentEncoded: false),
            withDestinationPath: "MacOS/msr")
        #expect(try unpack(try archive(Self.bundle)).status == 0)
    }

    @Test func aNonEmptyBuildFolderStops() throws {
        defer { scratch.remove() }
        try FileManager.default.createDirectory(at: build, withIntermediateDirectories: true)
        try Data("left over".utf8).write(to: build.appending(path: "old.zip"))
        let outcome = try unpack(try archive(Self.bundle))
        #expect(outcome.status == 1)
        #expect(outcome.errors.contains("is not empty"))
        #expect(try buildContents() == ["old.zip"])
    }

    @Test func aMemberWithDotDotStops() throws {
        defer { scratch.remove() }
        try Data("outside".utf8).write(to: sources.deletingLastPathComponent().appending(path: "evil"))
        let outcome = try unpack(try archive(Self.bundle, "../evil"))
        #expect(outcome.status == 1)
        #expect(outcome.errors.contains("'../evil'"))
        #expect(outcome.errors.contains(".."))
        #expect(try buildContents().isEmpty)
    }

    @Test func aMemberWithAnAbsolutePathStops() throws {
        defer { scratch.remove() }
        let absolute = scratch.url.appending(path: "absolute")
        try Data("outside".utf8).write(to: absolute)
        let outcome = try unpack(try archive(Self.bundle, absolute.path(percentEncoded: false)))
        #expect(outcome.status == 1)
        #expect(outcome.errors.contains("absolute path"))
        #expect(try buildContents().isEmpty)
    }

    @Test func aMemberOutsideTheBundleStops() throws {
        defer { scratch.remove() }
        try Data("beside".utf8).write(to: sources.appending(path: "beside"))
        let outcome = try unpack(try archive(Self.bundle, "beside"))
        #expect(outcome.status == 1)
        #expect(outcome.errors.contains("outside \(Self.bundle)"))
        #expect(try buildContents().isEmpty)
    }

    @Test func aSymbolicLinkPointingOutsideTheBundleStops() throws {
        defer { scratch.remove() }
        try FileManager.default.createSymbolicLink(
            atPath: sources.appending(path: "\(Self.bundle)/Contents/escape").path(percentEncoded: false),
            withDestinationPath: "../../..")
        let outcome = try unpack(try archive(Self.bundle))
        #expect(outcome.status == 1)
        #expect(outcome.errors.contains("points outside"))
        #expect(try buildContents().isEmpty)
    }
}
