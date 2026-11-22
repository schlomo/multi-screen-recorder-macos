import AppKit
import RecorderCore
import RecorderLogic
import SwiftUI

/// The app: an AppKit application with SwiftUI window content.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var startWindow: NSWindow?
    private var aboutWindow: NSWindow?
    private var model: StartModel?
    private var session: RecordingSession?
    /// Stop in progress, for a logout that comes meanwhile to wait for.
    private var stopping: Task<Void, Never>?
    /// For the rest of the process's life.
    private var audioWatch: AudioInputWatch?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = makeMainMenu()
        let model: StartModel
        do {
            model = StartModel(homeFolder: try homeFolder())
            audioWatch = try AudioInputWatch { model.devicesChanged() }
        } catch {
            let alert = NSAlert()
            alert.messageText = "Multi Screen Recorder cannot start"
            alert.informativeText = ErrorDetail(error).text
            alert.runModal()
            NSApp.terminate(nil)
            return
        }
        // Posted when a screen comes or goes or changes its resolution.
        _ = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated { model.devicesChanged() }
        }
        self.model = model
        startWindow = makeWindow(
            title: "Multi Screen Recorder", content: StartView(model: model) { [weak self] in self?.startRecording() })
        startWindow?.center()
        startWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate()
        model.load()
        offerReports(homeFolder: model.homeFolder)
    }

    /// Start: the window closes; the Dock icon shows "!" when something needs the person.
    private func startRecording() {
        guard let model, model.canStart, let facts = model.readyCheckFacts else { return }
        do {
            session = try RecordingSession(
                settings: model.settings, homeFolder: model.homeFolder, readyCheckFacts: facts, output: nil)
        } catch {
            showAlert("Cannot start the recording", ErrorDetail(error).text)
            return
        }
        model.recordingStarted()
        startWindow?.close()
    }

    /// Stop: finalizes, opens the recording folder in Finder and quits (D45, D46).
    private func stopRecording(openFolder: Bool) async {
        guard let session else { return }
        let summary = await session.stop()
        self.session = nil
        if openFolder, let folder = session.folder {
            NSWorkspace.shared.open(folder)
        }
        // Only after the person's Stop: at logout, restart and shutdown the
        // problem goes to the unified log and the problem list only (N-B).
        if openFolder, summary?.manifestWritten == false {
            showAlert("The recording manifest could not be written",
                      "\(RecordingNames.manifest) in the recording folder does not record the end of the recording.")
        }
        if openFolder, let notRemembered = session.notRemembered {
            showAlert("The recording is not remembered", ErrorDetail(notRemembered).text)
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        guard let session else { return true }
        session.showStatus { [weak self] in self?.stopAndQuit() }
        return false
    }

    /// Stop in the status window: finalizes, opens the recording folder and quits.
    private func stopAndQuit() {
        stopping = Task {
            await stopRecording(openFolder: true)
            NSApp.terminate(nil)
        }
    }

    /// Logout, restart and shutdown finalize without asking; any other quit
    /// opens the status window.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let session else { return .terminateNow }
        switch QuitDecision(isStopping: session.isStopping, endsTheSession: quitEndsTheSession(reason: currentQuitReason())) {
        case .ignore:
            return .terminateCancel
        case .waitForTheStop:
            let stopping = stopping
            Task {
                await stopping?.value
                NSApp.reply(toApplicationShouldTerminate: true)
            }
            return .terminateLater
        case .showStatus:
            session.showStatus { [weak self] in self?.stopAndQuit() }
            return .terminateCancel
        case .finalizeWithoutAsking:
            stopping = Task {
                await stopRecording(openFolder: false)
                NSApp.reply(toApplicationShouldTerminate: true)
            }
            return .terminateLater
        }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        model?.appBecameActive()
    }

    /// While a recording runs, closing the last window does not quit the app.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        session == nil
    }

    @objc func showAbout(_ sender: Any?) {
        if aboutWindow == nil {
            aboutWindow = makeWindow(title: "About Multi Screen Recorder", content: AboutView(version: runningVersion))
            aboutWindow?.center()
        }
        aboutWindow?.makeKeyAndOrderFront(nil)
    }

    private func makeWindow(title: String, content: some View) -> NSWindow {
        // The window takes its size from the content's preferred size. The
        // crash after a screen's HiDPI switch was a layout loop in a popup
        // menu's own window, not in this one; the start window has no popup
        // menu (D41), see `StartModel.checkAgain`.
        let hosting = NSHostingController(rootView: content)
        hosting.sizingOptions = [.preferredContentSize]
        let window = NSWindow(contentViewController: hosting)
        window.title = title
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.isReleasedWhenClosed = false
        return window
    }

    /// The crash report offer, then the notice of the last recording's
    /// problems, from one read of the state file: one that cannot be read is
    /// one alert, and nothing is offered.
    private func offerReports(homeFolder: URL) {
        let stateFile = StateFile(homeFolder: homeFolder)
        let state: AppState
        do { state = try stateFile.load() } catch {
            showAlert("Cannot offer to report a crash or a recording's problems", ErrorDetail(error).text)
            return
        }
        offerProblemReport(state: offerCrashReport(state: state, stateFile: stateFile, homeFolder: homeFolder),
                           stateFile: stateFile)
    }

    /// Offers the newest crash report of the app that was not offered before:
    /// opens a new GitHub issue in the browser and shows a text copy of the
    /// crash report in Finder. The app opens no connection itself (D15).
    /// Gives the state as the offer left it.
    private func offerCrashReport(state: AppState, stateFile: StateFile, homeFolder: URL) -> AppState {
        do {
            guard let name = try CrashReport.toOffer(
                fileNames: try crashReportFileNames(homeFolder: homeFolder),
                lastOffered: state.lastOfferedCrashReport,
                procPath: { try crashReportProcPath(of: $0, homeFolder: homeFolder) })
            else { return state }
            // Marked before the dialog, so a crash while it is open, or a quit, never offers it twice.
            let offered = state.offering(name)
            try stateFile.save(offered)
            let alert = NSAlert()
            alert.messageText = "Multi Screen Recorder quit unexpectedly"
            alert.informativeText = CrashReport.dialogText
            alert.addButton(withTitle: "Report on GitHub")
            alert.addButton(withTitle: "Not Now")
            guard alert.runModal() == .alertFirstButtonReturn else { return offered }
            let copy: URL
            do { copy = try makeTextCopy(of: name, homeFolder: homeFolder) } catch {
                showAlert("Cannot copy the crash report", ErrorDetail(error).text)
                return offered
            }
            let issue = CrashReport.issueURL(
                crashReportName: name, version: runningVersion.description,
                macOSVersion: ProcessInfo.processInfo.operatingSystemVersionString)
            NSWorkspace.shared.activateFileViewerSelecting([copy])
            if !NSWorkspace.shared.open(issue) {
                showAlert("Cannot open the browser", "Open this address yourself:\n\(issue.absoluteString)")
            }
            return offered
        } catch {
            showAlert("Cannot offer the crash report", ErrorDetail(error).text)
            return state
        }
    }

    /// Tells, once, that the last recording had problems, and offers to
    /// report them: Report a problem runs `ProblemReportAction` (D64).
    private func offerProblemReport(state: AppState, stateFile: StateFile) {
        do {
            guard let folder = state.problemsNoticeFolder(folderExists: { FileManager.default.fileExists(atPath: $0) })
            else { return }
            // Marked before the notice, so a crash while it is open, or a quit, never shows it twice.
            try stateFile.save(state.showingProblemsNotice())
            let alert = NSAlert()
            alert.messageText = ProblemReport.noticeTitle
            alert.informativeText = ProblemReport.noticeText(recordingFolder: folder)
            alert.addButton(withTitle: ProblemReport.reportButton)
            alert.addButton(withTitle: ProblemReport.dismissButton)
            guard alert.runModal() == .alertFirstButtonReturn else { return }
            let action = ProblemReportAction(recordingFolder: URL(filePath: folder, directoryHint: .isDirectory),
                                             version: runningVersion.description)
            if let notOpened = action.run(opener: Workspace()) {
                showAlert("Cannot open the browser", "Open this address yourself:\n\(notOpened.absoluteString)")
            }
        } catch {
            showAlert("Cannot offer to report the last recording", ErrorDetail(error).text)
        }
    }

    private func showAlert(_ message: String, _ informative: String) {
        let alert = NSAlert()
        alert.messageText = message
        alert.informativeText = informative
        alert.runModal()
    }

    private func makeMainMenu() -> NSMenu {
        let appMenu = NSMenu(title: "Multi Screen Recorder")
        let about = NSMenuItem(title: "About Multi Screen Recorder", action: #selector(showAbout(_:)), keyEquivalent: "")
        about.target = self
        appMenu.addItem(about)
        appMenu.addItem(.separator())
        appMenu.addItem(NSMenuItem(title: "Hide Multi Screen Recorder", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h"))
        appMenu.addItem(.separator())
        appMenu.addItem(NSMenuItem(title: "Quit Multi Screen Recorder", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(NSMenuItem(title: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w"))
        windowMenu.addItem(NSMenuItem(title: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m"))

        let mainMenu = NSMenu()
        for menu in [appMenu, windowMenu] {
            let item = NSMenuItem()
            item.submenu = menu
            mainMenu.addItem(item)
        }
        NSApp.windowsMenu = windowMenu
        return mainMenu
    }
}
