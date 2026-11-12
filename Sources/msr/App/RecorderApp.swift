import AppKit
import RecorderCore
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

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = makeMainMenu()
        let home: URL
        do {
            home = try homeFolder()
        } catch {
            let alert = NSAlert()
            alert.messageText = "Multi Screen Recorder cannot start"
            alert.informativeText = String(describing: error)
            alert.runModal()
            NSApp.terminate(nil)
            return
        }
        let model = StartModel(homeFolder: home)
        startWindow = makeWindow(title: "Multi Screen Recorder", content: StartView(model: model))
        startWindow?.center()
        startWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate()
        model.load()
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
        let window = NSWindow(contentViewController: NSHostingController(rootView: content))
        window.title = title
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.isReleasedWhenClosed = false
        return window
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
