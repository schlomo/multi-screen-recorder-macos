import Foundation
import Testing

@Suite struct SupportTests {
    @Test(.timeLimit(.minutes(1)))
    func runReadsAChildThatFillsTheErrorPipeBeforeClosingOutput() throws {
        let outcome = try run(URL(filePath: "/usr/bin/env"),
                              ["sh", "-c", "head -c 1048576 /dev/zero >&2; echo done"])
        #expect(outcome.status == 0)
        #expect(outcome.output == "done\n")
        #expect(outcome.errors.utf8.count == 1_048_576)
    }
}
