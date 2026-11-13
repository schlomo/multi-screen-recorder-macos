import AppKit
import Testing
@testable import RecorderCore

@MainActor
@Suite struct MainRunLoopTests {
    /// With the application object, `.eventTracking` and `.modalPanel` are
    /// among the main run loop's common modes, as in the app; an action
    /// queued for the common modes would run in them.
    init() {
        _ = NSApplication.shared
    }

    /// Runs the main run loop in `mode` for a moment. AppKit is documented
    /// to do so in `.eventTracking` while a menu is open and in
    /// `.modalPanel` under a modal panel.
    private func runMainRunLoop(in mode: RunLoop.Mode) {
        let end = Date().addingTimeInterval(0.2)
        // A run loop without a source in the mode returns at once.
        RunLoop.main.add(Timer(timeInterval: 0.3, repeats: false) { _ in }, forMode: mode)
        while Date() < end { RunLoop.main.run(mode: mode, before: end) }
    }

    @Test(arguments: [RunLoop.Mode.eventTracking, .modalPanel])
    func theActionWaitsForTheDefaultMode(mode: RunLoop.Mode) {
        var ran = false
        whenMainRunLoopIsInDefaultMode { ran = true }
        runMainRunLoop(in: mode)
        #expect(!ran)
        runMainRunLoop(in: .default)
        #expect(ran)
    }
}
