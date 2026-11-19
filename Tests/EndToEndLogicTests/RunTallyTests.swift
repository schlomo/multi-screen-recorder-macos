import Testing
@testable import EndToEndLogic

@Suite struct RunTallyTests {
    @Test func everyScenarioPassedAndRestoredIsAPass() {
        var tally = RunTally(total: 2)
        tally.passed()
        tally.passed()
        #expect(tally.verdict(finalRestoreSucceeded: true) == .passed("msr-end-to-end: all 2 scenarios passed"))
    }

    @Test func aRestoreThatFailedMidRunIsNeverAPass() {
        var tally = RunTally(total: 6)
        tally.passed()
        tally.passed()
        tally.stopped("the restore after tone failed")
        #expect(tally.verdict(finalRestoreSucceeded: true) == .failed([
            "msr-end-to-end: stopped, the restore after tone failed; 2 of 6 scenarios ran",
        ]))
    }

    @Test func fewerScenariosThanAskedForAreNeverAPass() {
        var tally = RunTally(total: 3)
        tally.passed()
        #expect(tally.verdict(finalRestoreSucceeded: true) == .failed(["msr-end-to-end: only 1 of 3 scenarios ran"]))
    }

    @Test func aFailedStepBeforeTheScenariosFailsTheRun() {
        var tally = RunTally(total: 1)
        tally.stepFailed("the start window: no window of process 7 on screen within 20 s")
        tally.passed()
        #expect(tally.verdict(finalRestoreSucceeded: true) == .failed([
            "msr-end-to-end: the start window: no window of process 7 on screen within 20 s",
        ]))
    }

    @Test func aFailedScenarioOrAFailedFinalRestoreFails() {
        var tally = RunTally(total: 2)
        tally.passed()
        tally.failed()
        #expect(tally.verdict(finalRestoreSucceeded: true) == .failed(["msr-end-to-end: 1 of 2 scenarios failed"]))
        var restoredBadly = RunTally(total: 1)
        restoredBadly.passed()
        #expect(restoredBadly.verdict(finalRestoreSucceeded: false) == .failed([
            "msr-end-to-end: the final restore failed; run scripts/end-to-end-test restore",
        ]))
    }
}
