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

/// Exit 3: a file not finalized or ended by a failure (D47), the final manifest not written, or no start.
let recordingEndedWithErrorExitCode: Int32 = 3

extension CommandLineInterface {
    struct Record: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Record every screen and audio source until Ctrl-C, SIGTERM, SIGHUP, the duration or Stop in the status window.",
            discussion: "Prints what will be recorded, runs the ready check, then records with the app's Dock icon. "
                + "Standard output carries one line, the recording folder's path, when recording starts; everything for people goes to standard error, "
                + "on a terminal with a status line redrawn once a second. "
                + "Exits 0 when every file is finalized and no file was ended by a failure, 1 when not ready, 3 otherwise or when it could not start.")

        @OptionGroup var flags: SettingsFlags

        @Option(help: "Stop after this long: hours, minutes and seconds, such as 1h30m, 45m or 90s; a number alone is minutes.")
        var duration: RecordingDuration?

        @Flag(help: "Also prints the detail lines on standard error, and writes them at debug level in the unified log.")
        var debug = false

        @Flag(help: "No output for people: only the recording folder's path on standard output, and on standard error a failing ready check, errors, the settings file note, each problem as it happens and the summary of a run that exits 3. Not with --debug.")
        var quiet = false

        func validate() throws {
            if quiet && debug { throw ValidationError("--quiet cannot be combined with --debug.") }
        }

        /// Never called: `main` runs `msr record` in the event loop, through `RecordCommandDelegate`.
        func run() async throws {
            preconditionFailure("msr record runs in the event loop")
        }
    }
}

@MainActor
final class RecordCommandDelegate: NSObject, NSApplicationDelegate {
    private let record: CommandLineInterface.Record
    private let output: RecordOutput
    private var session: RecordingSession?
    private var signalSources: [any DispatchSourceSignal] = []
    private var stopRequests = StopRequests()
    private var isStopping: Bool { stopRequests.isStopping }
    /// Stop in progress, for a logout that comes meanwhile to wait for.
    private var stopping: Task<Void, Never>?
    private(set) var exitStatus: Int32 = 0

    init(record: CommandLineInterface.Record) {
        self.record = record
        output = RecordOutput(record: record)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = makeRecordMenu()
        Task { await checkAndStart() }
    }

    /// Prints what will be recorded and the ready check, then starts, or
    /// ends with the exit status of a command that ends early.
    private func checkAndStart() async {
        // A closed reader of standard output must not end the process with the files not finalized.
        signal(SIGPIPE, SIG_IGN)
        if record.debug { RecorderLog.enableDebug() }
        let settings: Settings
        let home: URL
        do {
            settings = try record.flags.effectiveSettings(from: standardSettingsFile())
            home = try homeFolderOrExit()
        } catch {
            exitStatus = CommandLineInterface.exitCode(for: error).rawValue
            endEventLoop()
            return
        }
        let facts = await probeReadyCheckFacts(proof: .captureOneFrame, settings: settings, homeFolder: home)
        let result = ReadyCheck.evaluate(facts, settings: settings)
        output.tell(.banner, runningVersion.banner)
        output.tell(.whatWillBeRecorded, WhatWillBeRecorded(settings: settings, facts: facts).text + "\n")
        output.tell(.readyCheck(isReady: result.isReady), result.text)
        guard result.isReady else {
            exitStatus = 1
            endEventLoop()
            return
        }
        do {
            session = try RecordingSession(settings: settings, homeFolder: home, readyCheckFacts: facts, output: output)
        } catch {
            output.tell(.error, "Error: \(ErrorDetail(error).text)\n")
            exitStatus = recordingEndedWithErrorExitCode
            endEventLoop()
            return
        }
        // Without the icon the recording goes on: Ctrl-C still stops it.
        if !NSApp.setActivationPolicy(.regular) {
            session?.recorder?.dockIconNotShown()
        }
        guard let folder = session?.folder else { preconditionFailure("a started recording has its folder") }
        let folderPath = folder.path(percentEncoded: false)
        output.tell(.recordingFolderNotice, "Recording into \(folderPath)\n")
        output.tell(.recordingFolder, folderPath)
        for signalNumber in [SIGINT, SIGTERM, SIGHUP] {
            signal(signalNumber, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: signalNumber, queue: .main)
            source.setEventHandler { [weak self] in MainActor.assumeIsolated { self?.stopRequested() } }
            source.resume()
            signalSources.append(source)
        }
        if let duration = record.duration {
            Task { [weak self] in
                while let self, !self.isStopping {
                    if let recorder = self.session?.recorder, recorder.elapsedSeconds >= Double(duration.seconds) {
                        self.stopRequested()
                        return
                    }
                    try? await Task.sleep(for: .milliseconds(200))
                }
            }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        session?.showStatus { [weak self] in self?.stopRequested() }
        return false
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let session else { return .terminateNow }
        switch QuitDecision(isStopping: isStopping, endsTheSession: quitEndsTheSession(reason: currentQuitReason())) {
        case .ignore:
            return .terminateCancel
        case .waitForTheStop:
            let stopping = stopping
            Task {
                await stopping?.value
                NSApp.reply(toApplicationShouldTerminate: true)
            }
            return .terminateLater
        case .finalizeWithoutAsking:
            // Logout and shutdown finalize without asking, then let the process end.
            output.tell(.stopMessage, stopRequests.request() + "\n")
            stopping = Task {
                _ = await session.stop()
                NSApp.reply(toApplicationShouldTerminate: true)
            }
            return .terminateLater
        case .showStatus:
            session.showStatus { [weak self] in self?.stopRequested() }
            return .terminateCancel
        }
    }

    /// Ctrl-C, SIGTERM, SIGHUP, the duration and Stop all end here: told at
    /// once, then finalized; a request while finalizing is only answered.
    private func stopRequested() {
        guard let session else { return }
        let first = !isStopping
        output.tell(.stopMessage, stopRequests.request() + "\n")
        guard first else { return }
        stopping = Task {
            if let summary = await session.stop() {
                // The summary is the message of a run that exits 3, so `--quiet` still tells it then.
                let report = summary.endedWithError ? summary.reportText(version: runningVersion.description) : ""
                output.tell(.summary(endedWithError: summary.endedWithError), summary.text + report)
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

/// What `msr record` tells when asked to stop: the first request starts the
/// stop, any later one only tells that it goes on.
struct StopRequests {
    static let stopping = "Stopping the recording and finalizing the files…"
    static let stillFinalizing = "Still finalizing the files…"
    private(set) var isStopping = false

    /// The line for standard error; the first request starts the stop.
    mutating func request() -> String {
        defer { isStopping = true }
        return isStopping ? Self.stillFinalizing : Self.stopping
    }
}
