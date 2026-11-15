import CoreServices
import Testing
@testable import msr

/// Logout, restart and shutdown finalize a recording without asking; any
/// other quit asks "Stop recording?".
@Suite struct QuitReasonTests {
    @Test(arguments: [kAELogOut, kAEReallyLogOut, kAEShowRestartDialog, kAEShowShutdownDialog, kAERestart, kAEShutDown])
    func theSessionEndingFinalizesWithoutAsking(reason: OSType) {
        #expect(quitEndsTheSession(reason: reason))
    }

    @Test func aQuitOfItsOwnAsks() {
        #expect(!quitEndsTheSession(reason: nil))
        #expect(!quitEndsTheSession(reason: OSType(kAEQuitApplication)))
    }
}

@Suite struct QuitDecisionTests {
    @Test func aQuitDuringARecordingAsksAndALogoutFinalizes() {
        #expect(QuitDecision(isStopping: false, endsTheSession: false) == .ask)
        #expect(QuitDecision(isStopping: false, endsTheSession: true) == .finalizeWithoutAsking)
    }

    /// A logout while Stop is in progress waits for it instead of cancelling the logout.
    @Test func whileStoppingALogoutWaitsAndAQuitIsIgnored() {
        #expect(QuitDecision(isStopping: true, endsTheSession: true) == .waitForTheStop)
        #expect(QuitDecision(isStopping: true, endsTheSession: false) == .ignore)
    }
}
