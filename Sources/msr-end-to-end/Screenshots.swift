import AppKit
import CoreGraphics
import EndToEndLogic
import Foundation

/// Screenshots of the app's real windows, taken while the end-to-end run
/// drives it, for a person to look at (docs/design/end-to-end-tests.md,
/// "Artifacts for review"); one that cannot be taken fails the run.
enum Screenshots {
    /// The first ordinary window of the process, once it is on screen.
    static func windowID(of pid: pid_t, seconds: Double, interruption: Interruption) throws -> CGWindowID {
        let deadline = Date().addingTimeInterval(seconds)
        while true {
            try interruption.check()
            let windows = (CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]]) ?? []
            if let window = windows.first(where: {
                ($0[kCGWindowOwnerPID as String] as? pid_t) == pid && ($0[kCGWindowLayer as String] as? Int) == 0
            }), let number = window[kCGWindowNumber as String] as? CGWindowID {
                return number
            }
            guard Date() < deadline else { throw DriverError("no window of process \(pid) on screen within \(Int(seconds)) s") }
            Thread.sleep(forTimeInterval: 0.1)
        }
    }

    /// `screencapture` of one window, without its shadow and without a sound.
    static func capture(_ window: CGWindowID, to png: URL) throws {
        try screencapture(["-x", "-o", "-l", "\(window)", png.path], png, what: "window \(window)")
    }

    private static func screencapture(_ arguments: [String], _ png: URL, what: String) throws {
        let process = Process()
        process.executableURL = URL(filePath: try Media.onPath("screencapture"))
        process.arguments = arguments
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0, FileManager.default.fileExists(atPath: png.path) else {
            throw DriverError("screencapture of \(what) failed (exit \(process.terminationStatus))")
        }
    }

    /// Sends a core Apple event (quit) to the process, as Quit does;
    /// refuses, rather than asks, should macOS want the person's consent.
    static func send(_ eventID: AEEventID, to pid: pid_t) throws {
        let target = NSAppleEventDescriptor(processIdentifier: pid)
        let permission = AEDeterminePermissionToAutomateTarget(target.aeDesc, AEEventClass(kCoreEventClass), eventID, false)
        guard permission == noErr else {
            throw DriverError("macOS does not let this program send the event without asking (status \(permission))")
        }
        let event = NSAppleEventDescriptor(eventClass: AEEventClass(kCoreEventClass), eventID: eventID,
                                           targetDescriptor: target, returnID: AEReturnID(kAutoGenerateReturnID),
                                           transactionID: AETransactionID(kAnyTransactionID))
        _ = try event.sendEvent(options: [.noReply], timeout: 5)
    }
}
