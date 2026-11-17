import Foundation
import Testing

/// Runs scripts/install-app with INSTALL_FOLDER in a scratch folder, on small
/// stand-in bundles: with a zip, and with --release and --snapshot through a
/// stand-in gh. The mode without an argument builds and signs, so it is not
/// run here.
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

    /// A program that waits until it is ended, compiled once per test. Not a
    /// copy of a system program: macOS may kill such a copy at launch, and
    /// writes an msr crash report that the app then offers to report.
    private func standInProgram() async throws -> URL {
        let program = scratch.url.appending(path: "stand-in-msr")
        if !FileManager.default.fileExists(atPath: path(program)) {
            let source = scratch.url.appending(path: "stand-in-msr.c")
            try "#include <unistd.h>\nint main(void) { pause(); return 0; }\n".write(to: source, atomically: true, encoding: .utf8)
            try await tool("cc", "-o", path(program), path(source))
        }
        return program
    }

    /// A stand-in bundle holding the stand-in program as its msr, in a folder
    /// of its own, signed ad hoc, or unsigned when `signed` is false.
    private func makeBundle(version: String, in folder: URL, signed: Bool = true) async throws -> URL {
        let app = folder.appending(path: Self.bundle, directoryHint: .isDirectory)
        let macOS = app.appending(path: "Contents/MacOS", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: macOS, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: try await standInProgram(), to: macOS.appending(path: "msr"))
        try PropertyListSerialization.data(
            fromPropertyList: [
                "CFBundleExecutable": "msr", "CFBundleIdentifier": "org.schapiro.multiscreenrecorder", "MSRVersion": version,
            ],
            format: .xml, options: 0).write(to: app.appending(path: "Contents/Info.plist"))
        // the linker signs the program ad hoc, so an unsigned bundle needs that removed
        if signed {
            try await tool("codesign", "--force", "--sign", "-", path(app))
        } else {
            try await tool("codesign", "--remove-signature", path(macOS.appending(path: "msr")))
        }
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

    /// Runs `body` while `program` runs, then ends the program and waits for
    /// its end through its termination handler: `waitUntilExit()` on a thread
    /// of the test's pool can miss the end and wait forever.
    private func whileRunning<T>(_ program: URL, _ body: () async throws -> T) async throws -> T {
        let running = Process()
        running.executableURL = program
        running.standardOutput = FileHandle.nullDevice
        running.standardError = FileHandle.nullDevice
        let (ended, ending) = AsyncStream.makeStream(of: Void.self)
        running.terminationHandler = { _ in ending.finish() }
        try running.run()
        let result: Result<T, any Error>
        do { result = .success(try await body()) } catch { result = .failure(error) }
        running.terminate()
        for await _ in ended {}
        return try result.get()
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
        let archive = try await makeZip(try await makeBundle(version: "0.20261117.1", in: sources))
        let outcome = try await whileRunning(program) {
            try await Task.sleep(for: .milliseconds(300))
            return try await install(archive)
        }
        #expect(outcome.status == 1)
        #expect(outcome.errors.contains("is running"), "\(outcome.errors)")
        #expect(try installedVersion() == "0.20261116.1")
    }

    /// The environment for a run with a stand-in gh, found first on the PATH:
    /// it writes its arguments to `gh-arguments` in the scratch folder and
    /// "downloads" `zip` into the folder given with --dir.
    private func standInGH(delivering zip: URL) throws -> [String: String] {
        let folder = scratch.url.appending(path: "stand-in-gh", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let program = folder.appending(path: "gh")
        try """
            #!/bin/sh
            echo "$@" > '\(path(scratch.url.appending(path: "gh-arguments")))'
            while [ $# -gt 0 ]; do
                if [ "$1" = --dir ]; then mkdir -p "$2" && cp '\(path(zip))' "$2/"; fi
                shift
            done
            """.write(to: program, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: path(program))
        let realPath = try #require(ProcessInfo.processInfo.environment["PATH"])
        return ["PATH": "\(path(folder)):\(realPath)", "INSTALL_FOLDER": path(installFolder)]
    }

    @Test(arguments: [(["--snapshot", "20"], "release download pr-20 "), (["--release"], "release download --repo ")])
    func aReleaseIsDownloadedWithGHAndInstalled(arguments: [String], expected: String) async throws {
        defer { scratch.remove() }
        let archive = try await makeZip(try await makeBundle(version: "0.20261117.52-pr20+d73cb1e", in: sources))
        let outcome = try await run(repositoryRoot.appending(path: "scripts/install-app"), arguments,
                                    environment: try standInGH(delivering: archive))
        #expect(outcome.status == 0, "\(outcome.errors)")
        #expect(try installedVersion() == "0.20261117.52-pr20+d73cb1e")
        let ghArguments = try String(contentsOf: scratch.url.appending(path: "gh-arguments"), encoding: .utf8)
        #expect(ghArguments.hasPrefix(expected), "\(ghArguments)")
        #expect(ghArguments.contains("--repo schlomo/multi-screen-recorder-macos "), "\(ghArguments)")
    }

    @Test(arguments: [
        (["--snapshot", "x"], "--snapshot takes a PR number, such as 20, not 'x'"),
        (["--snapshot", "pr-20"], "--snapshot takes a PR number, such as 20, not 'pr-20'"),
        (["--snapshot"], "usage:"),
        (["--bogus"], "usage:"),
        ([""], " is not a file"),
    ])
    func aWrongArgumentFailsAndChangesNothing(arguments: [String], message: String) async throws {
        defer { scratch.remove() }
        let outcome = try await run(repositoryRoot.appending(path: "scripts/install-app"), arguments,
                                    environment: ["INSTALL_FOLDER": path(installFolder)])
        #expect(outcome.status == 1)
        #expect(outcome.errors.contains(message), "\(outcome.errors)")
        #expect(try FileManager.default.contentsOfDirectory(atPath: path(installFolder)).isEmpty)
    }

    @Test(arguments: ["--help", "-h"])
    func helpPrintsTheUsageAndChangesNothing(argument: String) async throws {
        defer { scratch.remove() }
        let outcome = try await run(repositoryRoot.appending(path: "scripts/install-app"), [argument],
                                    environment: ["INSTALL_FOLDER": path(installFolder)])
        #expect(outcome.status == 0, "\(outcome.errors)")
        #expect(outcome.output.hasPrefix("Installs the app"), "\(outcome.output)")
        #expect(outcome.output.contains("scripts/install-app --release"))
        #expect(try FileManager.default.contentsOfDirectory(atPath: path(installFolder)).isEmpty)
    }

    @Test func aMissingZipFailsLoudly() async throws {
        defer { scratch.remove() }
        let outcome = try await install(scratch.url.appending(path: "missing.zip"))
        #expect(outcome.status == 1)
        #expect(outcome.errors.contains("missing.zip is not a file"), "\(outcome.errors)")
    }
}
