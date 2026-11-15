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
