import Foundation
import Testing

@Suite struct SupportTests {
    /// Against a helper that reads pipes one after the other this hangs;
    /// the pipeline's time limit on `test-and-build` ends it.
    @Test func runCapturesAChildThatWritesMuchToErrorsBeforeAnyOutput() throws {
        let outcome = try run(URL(filePath: "/usr/bin/env"),
                              ["sh", "-c", "head -c 1048576 /dev/zero >&2; echo done"])
        #expect(outcome.status == 0)
        #expect(outcome.output == "done\n")
        #expect(outcome.errors.utf8.count == 1_048_576)
    }
}
