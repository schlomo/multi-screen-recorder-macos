import AppKit
import ArgumentParser
import Foundation
import RecorderCore
import RecorderLogic

extension RecordingDuration: ExpressibleByArgument {
    public init?(argument: String) {
        self.init(argument)
    }
}

/// EX 3: the recording ended with an error (a file not finalized, or an error event).
let recordingEndedWithErrorExitCode: Int32 = 3

extension CommandLineInterface {
    struct Record: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Record every display until Ctrl-C, SIGTERM, SIGHUP, the duration or Stop in the Dock.",
            discussion: "Prints what will be recorded, runs the ready check, then records with the app's Dock icon. "
                + "Exits 0 when the recording ended well, 1 when not ready, 3 when it ended with an error.")

        @OptionGroup var flags: SettingsFlags

        @Option(help: "Stop after this long: hours, minutes and seconds, such as 1h30m, 45m or 90s.")
        var duration: RecordingDuration?

        func run() async throws {
            let settings = try flags.effectiveSettings(from: standardSettingsFile())
            let home = try homeFolderOrExit()
            let facts = await probeReadyCheckFacts(settings: settings, homeFolder: home)
            let result = ReadyCheck.evaluate(facts, settings: settings)
            print(WhatWillBeRecorded(settings: settings, facts: facts).text, terminator: "")
            print("  \(ProductText.displaysOnly)\n")
            print(result.text, terminator: "")
            fflush(stdout)
            if !result.isReady { throw ExitCode(1) }
            let status = await MainActor.run {
                RecordCommandApp.run(settings: settings, homeFolder: home, duration: duration)
            }
            if status != 0 { throw ExitCode(status) }
        }
    }
}

/// `msr record` runs the app's event loop with its Dock icon: macOS reports
/// display changes only under `NSApplication.run()` (D45).
@MainActor
enum RecordCommandApp {
    static func run(settings: Settings, homeFolder: URL, duration: RecordingDuration?) -> Int32 {
        let app = NSApplication.shared
        let delegate = RecordCommandDelegate(settings: settings, homeFolder: homeFolder, duration: duration)
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        withExtendedLifetime(delegate) { app.run() }
        return delegate.exitStatus
    }
}

@MainActor
final class RecordCommandDelegate: NSObject, NSApplicationDelegate {
    private let settings: Settings
    private let homeFolder: URL
    private let duration: RecordingDuration?
    private var session: RecordingSession?
    private var signalSources: [any DispatchSourceSignal] = []
    private var isPoweringOff = false
    private var isStopping = false
    private(set) var exitStatus: Int32 = 0

    init(settings: Settings, homeFolder: URL, duration: RecordingDuration?) {
        self.settings = settings
        self.homeFolder = homeFolder
        self.duration = duration
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = makeRecordMenu()
        do {
            session = try RecordingSession(settings: settings, homeFolder: homeFolder, tellOnStandardError: true)
        } catch {
            standardError("Error: \(error)")
            exitStatus = recordingEndedWithErrorExitCode
            endEventLoop()
            return
        }
        print("Recording into \(session?.folder?.path(percentEncoded: false) ?? "")")
        fflush(stdout)
        for signalNumber in [SIGINT, SIGTERM, SIGHUP] {
            signal(signalNumber, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: signalNumber, queue: .main)
            source.setEventHandler { [weak self] in MainActor.assumeIsolated { self?.stop() } }
            source.resume()
            signalSources.append(source)
        }
        _ = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.willPowerOffNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.isPoweringOff = true }
        }
        if let duration {
            Task { [weak self] in
                while let self, !self.isStopping {
                    if let recorder = self.session?.recorder, recorder.elapsedSeconds >= Double(duration.seconds) {
                        self.stop()
                        return
                    }
                    try? await Task.sleep(for: .milliseconds(200))
                }
            }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if session != nil, !isStopping, RecordingSession.askToStop() { stop() }
        return false
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let session, !isStopping else { return .terminateNow }
        if isPoweringOff {
            // Logout and shutdown finalize without asking, then let the process end.
            isStopping = true
            Task {
                _ = await session.stop()
                NSApp.reply(toApplicationShouldTerminate: true)
            }
            return .terminateLater
        }
        if RecordingSession.askToStop() { stop() }
        return .terminateCancel
    }

    /// Ctrl-C, SIGTERM, SIGHUP, the duration and Stop in the Dock all end here.
    private func stop() {
        guard let session, !isStopping else { return }
        isStopping = true
        Task {
            if let summary = await session.stop() {
                print(summary.text, terminator: "")
                fflush(stdout)
                if summary.endedWithError { exitStatus = recordingEndedWithErrorExitCode }
            }
            endEventLoop()
        }
    }

    private func endEventLoop() {
        NSApp.stop(nil)
        // `stop` takes effect after the next event.
        if let event = NSEvent.otherEvent(
            with: .applicationDefined, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0,
            context: nil, subtype: 0, data1: 0, data2: 0) {
            NSApp.postEvent(event, atStart: true)
        }
    }

    private func makeRecordMenu() -> NSMenu {
        let appMenu = NSMenu(title: "Multi Screen Recorder")
        appMenu.addItem(NSMenuItem(title: "Quit Multi Screen Recorder", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        let item = NSMenuItem()
        item.submenu = appMenu
        let mainMenu = NSMenu()
        mainMenu.addItem(item)
        return mainMenu
    }
}
