import Foundation
import Testing

/// Runs scripts/test only for its help, which exits before it checks or runs
/// anything.
@Suite struct TestScriptTests {
    @Test(arguments: ["--help", "-h"])
    func helpPrintsTheUsage(argument: String) async throws {
        let outcome = try await run(repositoryRoot.appending(path: "scripts/test"), [argument])
        #expect(outcome.status == 0, "\(outcome.errors)")
        #expect(outcome.output.hasPrefix("Compiles the Python scripts"), "\(outcome.output)")
        #expect(outcome.output.contains("swift test"))
    }
}
