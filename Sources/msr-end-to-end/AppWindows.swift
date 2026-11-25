import CoreText
import EndToEndLogic
import Foundation

/// AppleScript run by `osascript`, a process of its own: AppKit or NSAppleScript in the driver itself
/// left it blind to the virtual screens that connect later (`CGDisplayCreateUUIDFromDisplayID` gave
/// nil, tried 2026-11-19), as the note on modes in docs/troubleshooting.md says of a long-running process.
enum AppleScript {
    static func run(_ source: String) throws { _ = try output(of: source) }

    /// What the script printed, without the final newline.
    static func output(of source: String) throws -> String {
        let process = Process()
        process.executableURL = URL(filePath: try Media.onPath("osascript"))
        process.arguments = ["-e", source]
        let errors = Pipe()
        process.standardError = errors
        let printed = Pipe()
        process.standardOutput = printed
        try process.run()
        let message = String(decoding: errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        let text = String(decoding: printed.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        process.waitUntilExit()
        let reason = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard process.terminationStatus == 0 else {
            // -1743: macOS refused to let this program send Apple events to the target.
            throw DriverError(reason.contains("-1743")
                ? "the program running this (a terminal app) lacks the Automation permission for the program the script drives; "
                    + "grant it in System Settings > Privacy & Security > Automation (\(reason))"
                : "osascript failed (exit \(process.terminationStatus)): \(reason)")
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
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

/// The app's own recording, as a person sees it: the status window while it records, with more screens
/// connected and one of them back after a disconnect, and the Finder window of the finished recording
/// folder, in each appearance, each window brought to the front before its capture. Only in the throwaway VM, which grants the
/// driver the Automation and Accessibility permissions this needs (scripts/end-to-end-vm/guest-configure-tcc), or
/// on the person's Mac (`onThisMac`, D82): light only, no virtual screen and no window moved, so no Accessibility permission.
extension Driver {
    /// How long the status window's video is, ending just before Stop.
    static let statusVideoSeconds = 5

    func recordingWindows() throws {
        guard inThrowawayVM || onThisMac else {
            RunLog.out("      the status window, its video and the Finder window are not taken, nor the dark appearance: "
                + "only a run told it is in the throwaway VM (--throwaway-vm) or on this Mac (app-windows) drives them")
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
        var screens: [UInt32: (process: ChildProcess, uuid: String)] = [:]
        defer {
            for screen in screens.values {
                try? VirtualScreenHelper.disconnect(screen.process, uuid: screen.uuid)
                try? restorer.ended(screen.process)
            }
        }
        if !onThisMac { try connectStatusWindowScreens(into: &screens, logs: folder) }
        try interruption.sleep(until: Date().addingTimeInterval(8))

        // The app's own reopen event, as a click on its Dock icon, opens the status window; sent to its pid, so
        // no other copy of the app gets it. Retried, as the app may not take events yet.
        let reopenBy = Date().addingTimeInterval(10)
        while true {
            do {
                try Screenshots.send(AEEventID(kAEReopenApplication), to: recorder.pid, askingIfNeeded: onThisMac)
                break
            } catch {
                guard Date() < reopenBy else { throw error }
                try interruption.sleep(until: Date().addingTimeInterval(1))
            }
        }
        let status = try Screenshots.windowID(of: recorder.pid, seconds: 20, interruption: interruption)
        if !onThisMac {
            // Its first position can lie partly off the VM's small screen, where a video of it would be cut off.
            try AppleScript.run(
                "tell application \"System Events\" to set position of window 1 of (first process whose unix id is \(recorder.pid)) to {30, 40}",
                retryingFor: 10)
        }
        try Screenshots.bringToFront(recorder.pid)
        try interruption.sleep(until: Date().addingTimeInterval(2))

        try waitForAudioMeasured(in: recording)

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

    /// Waits, polling once a second, until every audio input file of the recording is out of measuring, so
    /// the status window shows them synced; past `EndToEndValues.audioMeasuringLimit` it fails naming those still measuring.
    private func waitForAudioMeasured(in recording: URL) throws {
        let log = recording.appending(path: "recording.log")
        let deadline = Date().addingTimeInterval(EndToEndValues.audioMeasuringLimit)
        while true {
            let measuring = AudioMeasuring.filesMeasuring(log: try String(contentsOf: log, encoding: .utf8))
            if measuring.isEmpty { return }
            guard Date() < deadline else {
                throw DriverError("audio files still measuring after \(Int(EndToEndValues.audioMeasuringLimit)) s: "
                    + measuring.joined(separator: ", ") + "; see \(log.path)")
            }
            try interruption.sleep(until: Date().addingTimeInterval(1))
        }
    }

    /// Connects and disconnects the virtual screens of `Scenario.statusWindowScreenEvents`, timed from
    /// now; `screens` holds those still connected, for the caller to disconnect.
    private func connectStatusWindowScreens(into screens: inout [UInt32: (process: ChildProcess, uuid: String)], logs: URL) throws {
        let begun = Date()
        for (at, event) in Scenario.statusWindowScreenEvents {
            try interruption.sleep(until: begun.addingTimeInterval(at))
            switch event {
            case .connectScreen(let spec):
                let (process, uuid) = try VirtualScreenHelper.connect(spec, executable: ownExecutable, folder: logs)
                try restorer.started(process, stopSignal: SIGTERM)
                screens[spec.serialNumber] = (process, uuid)
            case .disconnectScreen(let serialNumber):
                guard let screen = screens.removeValue(forKey: serialNumber) else {
                    throw DriverError("no virtual screen \(serialNumber) to disconnect")
                }
                try VirtualScreenHelper.disconnect(screen.process, uuid: screen.uuid)
                try restorer.ended(screen.process)
            case .switchScreenMode:
                throw DriverError("the status window's screens switch no mode")
            }
        }
    }

    /// A Finder window of the finished recording folder: list view, no sidebar, no toolbar, every
    /// column as wide as its content and the window as high as its rows.
    private func finderWindow(of recording: URL, appearance: Appearance, review: URL) throws {
        let names = try FileManager.default.contentsOfDirectory(atPath: recording.path)
        let font = CTFontCreateUIFontForLanguage(.system, 13, nil)!
        let widest = names.map { name -> Double in
            let line = CTLineCreateWithAttributedString(NSAttributedString(string: name, attributes: [kCTFontAttributeName as NSAttributedString.Key: font]))
            return CTLineGetTypographicBounds(line, nil, nil, nil)
        }.max() ?? 0
        let nameWidth = Int(widest.rounded(.up)) + 60
        let (left, top) = (30, 40)
        let right = left + nameWidth + 181 + 97 + 125 + 20
        let bottom = top + 66 + names.count * 20 + 10
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
