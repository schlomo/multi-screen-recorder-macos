import Foundation
import Testing

/// Runs scripts/install-app with a zip argument and INSTALL_FOLDER in a
/// scratch folder, on small stand-in bundles. The modes without an argument
/// and --release build, sign and download, so they are not run here.
@Suite struct InstallAppScriptTests {
    private static let bundle = "Multi Screen Recorder.app"
    private static let quarantine = "com.apple.quarantine"
    private static let quarantineValue = "0083;00000000;Test;"

    private let scratch: ScratchFolder
    private let installFolder: URL
    private let sources: URL

    init() throws {
        scratch = try ScratchFolder("InstallAppScriptTests")
        installFolder = scratch.url.appending(path: "Applications", directoryHint: .isDirectory)
        sources = scratch.url.appending(path: "sources", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: installFolder, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: sources, withIntermediateDirectories: true)
    }

    private func path(_ url: URL) -> String { url.path(percentEncoded: false) }

    private func tool(_ arguments: String...) async throws {
        let outcome = try await run(URL(filePath: "/usr/bin/env"), arguments)
        try #require(outcome.status == 0, "\(arguments) failed: \(outcome.errors)")
    }

    /// A stand-in bundle holding a copy of /bin/sleep as its msr, in a folder
    /// of its own, signed ad hoc unless `signed` is false.
    private func makeBundle(version: String, in folder: URL, signed: Bool = true) async throws -> URL {
        let app = folder.appending(path: Self.bundle, directoryHint: .isDirectory)
        let macOS = app.appending(path: "Contents/MacOS", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: macOS, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: URL(filePath: "/bin/sleep"), to: macOS.appending(path: "msr"))
        try PropertyListSerialization.data(
            fromPropertyList: [
                "CFBundleExecutable": "msr", "CFBundleIdentifier": "org.schapiro.multiscreenrecorder", "MSRVersion": version,
            ],
            format: .xml, options: 0).write(to: app.appending(path: "Contents/Info.plist"))
        if signed { try await tool("codesign", "--force", "--sign", "-", path(app)) }
        return app
    }

    private func makeZip(_ app: URL, as name: String = "app.zip") async throws -> URL {
        let zip = scratch.url.appending(path: name)
        try await tool("ditto", "-c", "-k", "--keepParent", path(app), path(zip))
        return zip
    }

    private func install(_ zip: URL) async throws -> CommandOutcome {
        try await run(repositoryRoot.appending(path: "scripts/install-app"), [path(zip)],
                      environment: ["INSTALL_FOLDER": path(installFolder)])
    }

    private var installed: URL { installFolder.appending(path: Self.bundle, directoryHint: .isDirectory) }

    private func installedVersion() throws -> String? {
        let data = try? Data(contentsOf: installed.appending(path: "Contents/Info.plist"))
        let info = try data.map { try PropertyListSerialization.propertyList(from: $0, format: nil) } as? [String: String]
        return info?["MSRVersion"]
    }

    /// What `xattr -rl` lists for the folder.
    private func attributes(of url: URL) async throws -> String {
        try await run(URL(filePath: "/usr/bin/env"), ["xattr", "-rl", path(url)]).output
    }

    @Test func aSignedBundleIsInstalledAndItsVersionPrinted() async throws {
        defer { scratch.remove() }
        let app = try await makeBundle(version: "0.20261117.1", in: sources)
        let outcome = try await install(try await makeZip(app))
        #expect(outcome.status == 0, "\(outcome.errors)")
        #expect(outcome.output.contains("0.20261117.1"), "\(outcome.output)")
        #expect(try installedVersion() == "0.20261117.1")
    }

    @Test func anInstalledAppIsReplaced() async throws {
        defer { scratch.remove() }
        let old = try await makeBundle(version: "0.20261116.1", in: installFolder)
        try Data("left over".utf8).write(to: old.appending(path: "Contents/old-file"))
        let outcome = try await install(try await makeZip(try await makeBundle(version: "0.20261117.1", in: sources)))
        #expect(outcome.status == 0, "\(outcome.errors)")
        #expect(try installedVersion() == "0.20261117.1")
        #expect(!FileManager.default.fileExists(atPath: path(installed.appending(path: "Contents/old-file"))))
        #expect(try FileManager.default.contentsOfDirectory(atPath: path(installFolder)) == [Self.bundle])
    }

    @Test func quarantineOnTheZipAndOnTheUnpackedFilesIsRemoved() async throws {
        defer { scratch.remove() }
        let app = try await makeBundle(version: "0.20261117.1", in: sources)
        for file in ["", "Contents/MacOS/msr", "Contents/Info.plist"] {
            try await tool("xattr", "-w", Self.quarantine, Self.quarantineValue, path(app.appending(path: file)))
        }
        let archive = try await makeZip(app)
        try await tool("xattr", "-w", Self.quarantine, Self.quarantineValue, path(archive))

        let probe = scratch.url.appending(path: "probe", directoryHint: .isDirectory)
        try await tool("ditto", "-x", "-k", path(archive), path(probe))
        #expect(try await attributes(of: probe).contains(Self.quarantine), "the unpacked files do not carry the quarantine")

        let outcome = try await install(archive)
        #expect(outcome.status == 0, "\(outcome.errors)")
        #expect(try await !attributes(of: installed).contains(Self.quarantine))
    }

    /// The environment for a run with a stand-in for one tool, found first on
    /// the PATH: it exits with `status` when `condition` (shell) holds, and
    /// otherwise runs the real tool, at `real`.
    private func standIn(for tool: String, real: String, failingWhen condition: String, status: Int) throws -> [String: String] {
        let folder = scratch.url.appending(path: "stand-ins", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let program = folder.appending(path: tool)
        try "#!/bin/sh\nif \(condition); then exit \(status); fi\nexec \(real) \"$@\"\n"
            .write(to: program, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: path(program))
        let realPath = try #require(ProcessInfo.processInfo.environment["PATH"])
        return ["PATH": "\(path(folder)):\(realPath)", "INSTALL_FOLDER": path(installFolder)]
    }

    @Test func quarantineThatCannotBeRemovedFailsAndLeavesTheInstalledAppUntouched() async throws {
        defer { scratch.remove() }
        _ = try await makeBundle(version: "0.20261116.1", in: installFolder)
        let app = try await makeBundle(version: "0.20261117.1", in: sources)
        try await tool("xattr", "-w", Self.quarantine, Self.quarantineValue, path(app.appending(path: "Contents/Info.plist")))
        let archive = try await makeZip(app)
        // the stand-in xattr removes nothing, as if the attribute could not be removed
        let environment = try standIn(for: "xattr", real: "/usr/bin/xattr", failingWhen: "[ \"$1\" = -dr ]", status: 0)
        let outcome = try await run(repositoryRoot.appending(path: "scripts/install-app"), [path(archive)],
                                    environment: environment)
        #expect(outcome.status == 1)
        #expect(outcome.errors.contains("still carries com.apple.quarantine"), "\(outcome.errors)")
        #expect(try installedVersion() == "0.20261116.1")
        #expect(try FileManager.default.contentsOfDirectory(atPath: path(installFolder)) == [Self.bundle])
    }

    @Test func anInstalledAppThatCannotBeReplacedIsPutBack() async throws {
        defer { scratch.remove() }
        _ = try await makeBundle(version: "0.20261116.1", in: installFolder)
        let archive = try await makeZip(try await makeBundle(version: "0.20261117.1", in: sources))
        // the stand-in mv fails for the move of the new app, not for putting the old one back
        let environment = try standIn(for: "mv", real: "/bin/mv",
                                      failingWhen: "case \"$1\" in *.installing) true;; *) false;; esac", status: 1)
        let outcome = try await run(repositoryRoot.appending(path: "scripts/install-app"), [path(archive)],
                                    environment: environment)
        let folder = try FileManager.default.contentsOfDirectory(atPath: path(installFolder))
        #expect(outcome.status == 1, "\(outcome.errors) \(folder)")
        #expect(outcome.errors.contains("the old app is back"), "\(outcome.errors)")
        #expect(try installedVersion() == "0.20261116.1")
        #expect(folder == [Self.bundle], "\(folder)")
    }

    @Test func anUnsignedBundleIsRefusedAndNothingIsReplaced() async throws {
        defer { scratch.remove() }
        _ = try await makeBundle(version: "0.20261116.1", in: installFolder)
        let unsigned = try await makeBundle(version: "0.20261117.1", in: sources, signed: false)
        let outcome = try await install(try await makeZip(unsigned))
        #expect(outcome.status == 1)
        #expect(outcome.errors.contains("signature"), "\(outcome.errors)")
        #expect(try installedVersion() == "0.20261116.1")
    }

    @Test func aTamperedBundleIsRefusedAndNothingIsReplaced() async throws {
        defer { scratch.remove() }
        _ = try await makeBundle(version: "0.20261116.1", in: installFolder)
        let app = try await makeBundle(version: "0.20261117.1", in: sources)
        try Data("tampered".utf8).write(to: app.appending(path: "Contents/MacOS/msr"))
        let outcome = try await install(try await makeZip(app))
        #expect(outcome.status == 1)
        #expect(outcome.errors.contains("signature"), "\(outcome.errors)")
        #expect(try installedVersion() == "0.20261116.1")
    }

    @Test(arguments: ["full path", "symbolic link"])
    func aRunningInstalledAppMakesItRefuse(started: String) async throws {
        defer { scratch.remove() }
        let old = try await makeBundle(version: "0.20261116.1", in: installFolder)
        var program = old.appending(path: "Contents/MacOS/msr")
        if started == "symbolic link" {
            let link = scratch.url.appending(path: "msr-link")
            try FileManager.default.createSymbolicLink(at: link, withDestinationURL: program)
            program = link
        }
        let running = Process()
        running.executableURL = program
        running.arguments = ["60"]
        try running.run()
        defer { running.terminate(); running.waitUntilExit() }
        try await Task.sleep(for: .milliseconds(300))

        let outcome = try await install(try await makeZip(try await makeBundle(version: "0.20261117.1", in: sources)))
        #expect(outcome.status == 1)
        #expect(outcome.errors.contains("is running"), "\(outcome.errors)")
        #expect(try installedVersion() == "0.20261116.1")
    }

    @Test func aMissingZipFailsLoudly() async throws {
        defer { scratch.remove() }
        let outcome = try await install(scratch.url.appending(path: "missing.zip"))
        #expect(outcome.status == 1)
        #expect(outcome.errors.contains("missing.zip is not a file"), "\(outcome.errors)")
    }
}
