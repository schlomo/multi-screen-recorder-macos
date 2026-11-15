import Testing
@testable import msr

/// `main` decides synchronously what runs, so the AppKit event loop of the
/// app and of `msr record` starts at the same synchronous point, never
/// inside a main-queue job, where it would never drain the main queue.
@Suite struct EntryRouteTests {
    @Test func noArgumentsIsTheApp() {
        guard case .app = EntryRoute(arguments: []) else { Issue.record("not the app"); return }
    }

    @Test func recordIsParsedBeforeTheEventLoop() {
        guard case .record(let record) = EntryRoute(arguments: ["record", "--duration", "5", "--auto"]) else {
            Issue.record("not msr record")
            return
        }
        #expect(record.duration?.seconds == 300)
        #expect(record.flags.auto)
    }

    @Test func anyOtherCommandRunsWithoutTheEventLoop() {
        guard case .command(let command) = EntryRoute(arguments: ["version"]) else { Issue.record("not a command"); return }
        #expect(command is CommandLineInterface.Version)
    }

    @Test func aWrongArgumentIsAnErrorBeforeAnythingRuns() {
        guard case .failed = EntryRoute(arguments: ["record", "--bogus"]) else { Issue.record("not refused"); return }
    }
}
