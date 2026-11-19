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

    /// Runs `body` with the system in the appearance: dark is switched for the whole
    /// user session through System Events, which also tells the windows already open
    /// (Finder), and put back to what it was after it. The caller changes the appearance only
    /// where that harms nobody's session (`Appearance.taken`).
    static func withAppearance(_ appearance: Appearance, _ body: () throws -> Void) throws {
        guard appearance == .dark else { return try body() }
        let set = { (dark: Bool) in
            try AppleScript.run("tell application \"System Events\" to tell appearance preferences to set dark mode to \(dark)")
        }
        let wasDark = try AppleScript.output(of: "tell application \"System Events\" to tell appearance preferences to get dark mode") == "true"
        try set(true)
        defer { try? set(wasDark) }
        try body()
    }

    /// The first on-screen window of the program `owner` whose title is `title`.
    static func windowID(ownerName owner: String, title: String, seconds: Double, interruption: Interruption) throws -> CGWindowID {
        let deadline = Date().addingTimeInterval(seconds)
        while true {
            try interruption.check()
            let windows = (CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]]) ?? []
            if let number = windows.first(where: {
                ($0[kCGWindowOwnerName as String] as? String) == owner && ($0[kCGWindowName as String] as? String) == title
            })?[kCGWindowNumber as String] as? CGWindowID {
                return number
            }
            guard Date() < deadline else { throw DriverError("no window \"\(title)\" of \(owner) on screen within \(Int(seconds)) s") }
            Thread.sleep(forTimeInterval: 0.1)
        }
    }

    /// A video of one window's next `seconds` seconds, made by `screencapture -V`.
    static func video(_ window: CGWindowID, seconds: Int, to mov: URL) throws {
        try screencapture(["-x", "-l", "\(window)", "-V", "\(seconds)", mov.path], mov, what: "window \(window) as video")
    }
    /// `screencapture` of one window with macOS's own shadow around it (a PNG with
    /// transparent margins), without a sound.
    static func capture(_ window: CGWindowID, to png: URL) throws {
        try screencapture(["-x", "-l", "\(window)", png.path], png, what: "window \(window)")
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
