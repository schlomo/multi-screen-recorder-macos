import CoreServices
import Testing
@testable import msr

/// Logout, restart and shutdown finalize a recording without asking; any
/// other quit opens the status window.
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
    @Test func aQuitDuringARecordingShowsTheStatusAndALogoutFinalizes() {
        #expect(QuitDecision(isStopping: false, endsTheSession: false) == .showStatus)
        #expect(QuitDecision(isStopping: false, endsTheSession: true) == .finalizeWithoutAsking)
    }

    /// A logout while Stop is in progress waits for it instead of cancelling the logout.
    @Test func whileStoppingALogoutWaitsAndAQuitIsIgnored() {
        #expect(QuitDecision(isStopping: true, endsTheSession: true) == .waitForTheStop)
        #expect(QuitDecision(isStopping: true, endsTheSession: false) == .ignore)
    }
}

/// `msr record` says at once that it stops; asked again while finalizing,
/// it says that it goes on and does nothing more.
@Suite struct StopRequestsTests {
    @Test func theFirstRequestStopsAndLaterOnesSayItGoesOn() {
        var requests = StopRequests()
        #expect(!requests.isStopping)
        #expect(requests.request() == "Stopping the recording and finalizing the files…")
        #expect(requests.isStopping)
        #expect(requests.request() == "Still finalizing the files…")
        #expect(requests.request() == "Still finalizing the files…")
    }

    /// The app's Stop: under way from its first request, before the stop's task runs, so a second Stop starts
    /// none and a logout waits for the first.
    @Test func aStopIsUnderWayFromItsFirstRequestSoASecondStopStartsNoneAndALogoutWaits() {
        var requests = StopRequests()
        let first = requests.start()
        let second = requests.start()
        #expect(first && !second)
        #expect(QuitDecision(isStopping: requests.isStopping, endsTheSession: true) == .waitForTheStop)
        #expect(QuitDecision(isStopping: requests.isStopping, endsTheSession: false) == .ignore)
    }
}
