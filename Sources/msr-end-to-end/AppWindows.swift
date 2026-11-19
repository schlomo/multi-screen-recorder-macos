import AppKit
import EndToEndLogic
import Foundation

/// AppleScript run in this process: the driver's own Automation permission applies.
enum AppleScript {
    static func run(_ source: String) throws {
        guard let script = NSAppleScript(source: source) else { throw DriverError("AppleScript does not compile: \(source)") }
        var error: NSDictionary?
        script.executeAndReturnError(&error)
        if let error { throw DriverError("AppleScript failed: \(error[NSAppleScript.errorMessage] ?? error)") }
    }

    static func quoted(_ text: String) -> String {
        "\"" + text.replacing("\\", with: "\\\\").replacing("\"", with: "\\\"") + "\""
    }

    /// Runs `source` until it succeeds, for up to `seconds`: the target may not be ready yet.
    static func run(_ source: String, retryingFor seconds: Double) throws {
        let deadline = Date().addingTimeInterval(seconds)
        while true {
            do { try run(source); return } catch {
                guard Date() < deadline else { throw error }
                Thread.sleep(forTimeInterval: 1)
            }
        }
    }
}

/// The app's own recording, as a person sees it: the status window while it records and the Finder window
/// of the finished recording folder, in each appearance. Only in the throwaway VM, which grants the
/// driver the Automation and Accessibility permissions this needs (scripts/end-to-end-vm/guest-configure-tcc).
extension Driver {
    /// How long the status window's video is, ending just before Stop.
    static let statusVideoSeconds = 5

    func recordingWindows() throws {
        guard inThrowawayVM else {
            RunLog.out("      the status window, its video and the Finder window are not taken, nor the dark appearance: "
                + "only a run told it is in the throwaway VM (--throwaway-vm) drives them")
            return
        }
        for appearance in appearances {
            try Screenshots.withAppearance(appearance) { try recordingWindows(in: appearance) }
        }
    }

    private func recordingWindows(in appearance: Appearance) throws {
        let folder = scratch.appending(path: "app-recording-\(appearance.rawValue)")
        try? FileManager.default.removeItem(at: folder)
        let home = folder.appending(path: "home")
        let recordings = folder.appending(path: "recordings")
        for made in [home, recordings] { try FileManager.default.createDirectory(at: made, withIntermediateDirectories: true) }
        var environment = ProcessInfo.processInfo.environment
        environment["HOME"] = home.path
        // The duration is only a ceiling, so a killed driver never leaves a recording running.
        let recorder = try ChildProcess(
            executable: msr.path, arguments: ["record", "--duration", "180s", "--output-folder", recordings.path],
            environment: environment, standardOutput: folder.appending(path: "rec.out"), standardError: folder.appending(path: "rec.err"))
        try restorer.started(recorder, stopSignal: SIGINT)
        defer {
            if !recorder.hasExited {
                recorder.signal(SIGINT)
                if !recorder.wait(seconds: 60, interrupted: { interruption.happened }) {
                    recorder.signal(SIGKILL)
                    _ = recorder.wait(seconds: 5)
                }
            }
            try? restorer.ended(recorder)
        }

        while recorder.output().isEmpty {
            try interruption.check()
            guard !recorder.hasExited else { throw DriverError("msr record ended before it started recording: \(recorder.errors())") }
            Thread.sleep(forTimeInterval: 0.2)
        }
        let recording = URL(filePath: recorder.output().trimmingCharacters(in: .whitespacesAndNewlines))
        try interruption.sleep(until: Date().addingTimeInterval(8))

        // The app's own reopen event, as a click on its Dock icon, opens the status window.
        try AppleScript.run("tell application id \"org.schapiro.multiscreenrecorder\" to reopen", retryingFor: 10)
        let status = try Screenshots.windowID(of: recorder.pid, seconds: 20, interruption: interruption)
        // Its first position can lie partly off the VM's small screen, where a video of it would be cut off.
        try AppleScript.run(
            "tell application \"System Events\" to set position of window 1 of (first process whose unix id is \(recorder.pid)) to {30, 40}",
            retryingFor: 10)
        try interruption.sleep(until: Date().addingTimeInterval(2))

        let review = scratch.appending(path: ReviewNames.folder).appending(path: ReviewNames.appStep)
        try FileManager.default.createDirectory(at: review, withIntermediateDirectories: true)
        try Screenshots.video(status, seconds: Self.statusVideoSeconds, to: review.appending(
            path: ReviewNames.video(scenario: ReviewNames.appStep, window: "status-window", appearance: appearance)))
        try Screenshots.capture(status, to: review.appending(
            path: ReviewNames.screenshot(scenario: ReviewNames.appStep, window: "status-window", appearance: appearance)))

        recorder.signal(SIGINT)
        guard recorder.wait(seconds: 90, interrupted: { interruption.happened }), recorder.exit == .exited(0) else {
            throw DriverError("msr record did not end with exit 0 after Stop: \(recorder.exit.map { "\($0)" } ?? "still running")")
        }
        try finderWindow(of: recording, appearance: appearance, review: review)
    }

    /// A Finder window of the finished recording folder: list view, no sidebar, no toolbar, every
    /// column as wide as its content and the window as high as its rows.
    private func finderWindow(of recording: URL, appearance: Appearance, review: URL) throws {
        let names = try FileManager.default.contentsOfDirectory(atPath: recording.path)
        let font = NSFont.systemFont(ofSize: 13)
        let widest = names.map { NSAttributedString(string: $0, attributes: [.font: font]).size().width }.max() ?? 0
        let nameWidth = Int(widest.rounded(.up)) + 60
        let (left, top) = (30, 40)
        let right = left + nameWidth + 181 + 97 + 125 + 20
        let bottom = top + 52 + names.count * 20 + 10
        try AppleScript.run("""
            tell application "Finder"
              activate
              set w to make new Finder window to (POSIX file \(AppleScript.quoted(recording.path)) as alias)
              set current view of w to list view
              set sidebar width of w to 0
              set toolbar visible of w to false
              set statusbar visible of w to false
              tell list view options of w
                set icon size to small
                set width of column id name column to \(nameWidth)
                set width of column id modification date column to 181
                set width of column id size column to 97
                set width of column id kind column to 125
              end tell
              set bounds of w to {\(left), \(top), \(right), \(bottom)}
            end tell
            """)
        let title = recording.lastPathComponent
        defer { try? AppleScript.run("tell application \"Finder\" to close (every Finder window whose name is \(AppleScript.quoted(title)))") }
        try interruption.sleep(until: Date().addingTimeInterval(2))
        let id = try Screenshots.windowID(ownerName: "Finder", title: title, seconds: 20, interruption: interruption)
        try Screenshots.capture(id, to: review.appending(
            path: ReviewNames.screenshot(scenario: ReviewNames.appStep, window: "finder-window", appearance: appearance)))
    }
}
