import Foundation
import Testing

/// Runs scripts/end-to-end-test only for its help, which exits before it
/// builds or runs anything, and scripts/ci-install-end-to-end-tools only
/// outside CI, where it refuses before it downloads or installs anything.
@Suite struct EndToEndScriptTests {
    @Test(arguments: ["--help", "-h"])
    func helpPrintsTheUsage(argument: String) async throws {
        let outcome = try await run(repositoryRoot.appending(path: "scripts/end-to-end-test"), [argument])
        #expect(outcome.status == 0, "\(outcome.errors)")
        #expect(outcome.output.hasPrefix("Runs the end-to-end tests"), "\(outcome.output)")
        #expect(outcome.output.contains("scripts/end-to-end-test restore"))
    }

    @Test func theToolInstallerRunsInCIOnly() async throws {
        let outcome = try await run(repositoryRoot.appending(path: "scripts/ci-install-end-to-end-tools"))
        #expect(outcome.status == 1)
        #expect(outcome.errors == "scripts/ci-install-end-to-end-tools: RUNNER_TEMP is not set; this script runs in CI only\n")
    }
}
