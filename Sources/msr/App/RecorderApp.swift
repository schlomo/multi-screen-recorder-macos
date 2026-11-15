import AppKit
import RecorderCore
import RecorderLogic
import SwiftUI

/// The app: an AppKit application with SwiftUI window content.
@MainActor
enum RecorderApp {
    static func run() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        withExtendedLifetime(delegate) { app.run() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var startWindow: NSWindow?
    private var aboutWindow: NSWindow?
    private var model: StartModel?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = makeMainMenu()
        let model: StartModel
        do {
            model = StartModel(homeFolder: try homeFolder())
            try watchAudioInputs { model.devicesChanged() }
        } catch {
            let alert = NSAlert()
            alert.messageText = "Multi Screen Recorder cannot start"
            alert.informativeText = String(describing: error)
            alert.runModal()
            NSApp.terminate(nil)
            return
        }
        // Posted when a display comes or goes or changes its resolution.
        _ = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated { model.devicesChanged() }
        }
        self.model = model
        startWindow = makeWindow(title: "Multi Screen Recorder", content: StartView(model: model))
        startWindow?.center()
        startWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate()
        model.load()
        offerCrashReport(homeFolder: model.homeFolder)
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        model?.appBecameActive()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
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
        // crash after a display's HiDPI switch was a layout loop in a popup
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

    /// Offers the newest crash report of `msr` that was not offered before:
    /// opens a new GitHub issue in the browser and shows a text copy of the
    /// crash report in Finder. The app opens no connection itself (D15).
    private func offerCrashReport(homeFolder: URL) {
        do {
            let stateFile = StateFile(homeFolder: homeFolder)
            let state = try stateFile.load()
            guard let name = CrashReport.toOffer(
                fileNames: try crashReportFileNames(homeFolder: homeFolder),
                lastOffered: state.lastOfferedCrashReport)
            else { return }
            // Marked before the dialog, so a crash while it is open, or a quit, never offers it twice.
            try stateFile.save(state.offering(name))
            let alert = NSAlert()
            alert.messageText = "Multi Screen Recorder quit unexpectedly"
            alert.informativeText = "You can report it on GitHub, which needs a GitHub account. Your browser opens a new issue, and Finder shows a copy of the crash report as a text file for you to drag into it. Issues are public, and a crash report contains your Mac's user name: check it before you attach it."
            alert.addButton(withTitle: "Report on GitHub")
            alert.addButton(withTitle: "Not Now")
            guard alert.runModal() == .alertFirstButtonReturn else { return }
            let copy: URL
            do { copy = try makeTextCopy(of: name, homeFolder: homeFolder) } catch {
                showAlert("Cannot copy the crash report", error.localizedDescription)
                return
            }
            let issue = CrashReport.issueURL(
                crashReportName: name, version: runningVersion.description,
                macOSVersion: ProcessInfo.processInfo.operatingSystemVersionString)
            NSWorkspace.shared.activateFileViewerSelecting([copy])
            if !NSWorkspace.shared.open(issue) {
                showAlert("Cannot open the browser", "Open this address yourself:\n\(issue.absoluteString)")
            }
        } catch {
            showAlert("Cannot offer the crash report", error.localizedDescription)
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
