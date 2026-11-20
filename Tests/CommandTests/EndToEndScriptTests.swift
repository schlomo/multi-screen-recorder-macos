import Foundation
import Testing

/// Runs the end-to-end scripts only as far as they refuse before they build,
/// boot a VM or install anything: their help, their arguments and the tools
/// they require. A PATH without tart and packer makes the missing tool
/// deterministic.
@Suite struct EndToEndScriptTests {
    private let withoutTart = ["PATH": "/usr/bin:/bin"]

    @Test(arguments: ["scripts/end-to-end-test", "scripts/end-to-end-setup"], ["--help", "-h"])
    func helpPrintsTheUsage(script: String, argument: String) async throws {
        let outcome = try await run(repositoryRoot.appending(path: script), [argument])
        #expect(outcome.status == 0, "\(outcome.errors)")
        #expect(outcome.output.contains("\(script) --help"), "\(outcome.output)")
    }

    @Test func theTestsNeedAScratchFolder() async throws {
        let outcome = try await run(repositoryRoot.appending(path: "scripts/end-to-end-test"), ["--scenario", "plain"])
        #expect(outcome.status == 64)
        #expect(outcome.errors.hasPrefix("scripts/end-to-end-test: --scratch-folder <folder> is required"), "\(outcome.errors)")
    }

    @Test func theTestsRefuseAScratchFolderWithContent() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "e2e-scratch-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        try Data().write(to: folder.appending(path: "old"))
        let outcome = try await run(repositoryRoot.appending(path: "scripts/end-to-end-test"),
                                    ["--scratch-folder", folder.path(percentEncoded: false)])
        #expect(outcome.status == 1)
        #expect(outcome.errors.hasSuffix("exists and is not an empty folder\n"), "\(outcome.errors)")
    }

    @Test func theTestsNeedTart() async throws {
        let outcome = try await run(repositoryRoot.appending(path: "scripts/end-to-end-test"),
                                    ["--scratch-folder", "/nonexistent/e2e-scratch"], environment: withoutTart)
        #expect(outcome.status == 1)
        #expect(outcome.errors == "scripts/end-to-end-test: tart is not on the PATH\n")
    }

    @Test func theSetupNeedsTart() async throws {
        let outcome = try await run(repositoryRoot.appending(path: "scripts/end-to-end-setup"), environment: withoutTart)
        #expect(outcome.status == 1)
        #expect(outcome.errors == "scripts/end-to-end-setup: tart is not on the PATH\n")
    }

    @Test func theSetupTakesNoArguments() async throws {
        let outcome = try await run(repositoryRoot.appending(path: "scripts/end-to-end-setup"), ["now"])
        #expect(outcome.status == 64)
    }

    @Test func theToolInstallerNeedsAFolder() async throws {
        let outcome = try await run(repositoryRoot.appending(path: "scripts/install-end-to-end-tools"))
        #expect(outcome.status == 64)
        #expect(outcome.errors == "scripts/install-end-to-end-tools: usage: scripts/install-end-to-end-tools <folder for ffmpeg and ffprobe>\n")
    }
}
