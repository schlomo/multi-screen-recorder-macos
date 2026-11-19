import AVFoundation
import CoreGraphics
import EndToEndLogic
import Foundation
import VirtualScreen

/// Runs scenarios against the built app's `msr record`, as shipped, with a
/// scratch HOME and a scratch output folder, and runs the assertions.
final class Driver {
    let msr: URL
    /// The driver's own executable, which is also the device helper and `restore`.
    let ownExecutable: String
    let scratch: URL
    let restorer: Restorer
    let media: Media
    let interruption = Interruption.shared
    /// `msr version`'s line: the manifest's `app` is the name and it.
    let version: String
    private var screens: [UInt32: (process: ChildProcess, uuid: String)] = [:]
    /// The last finalized scenario's margins past its stop, for calibrating
    /// the finalize allowance.
    private(set) var margin: String?
    /// The last scenario's screenshots that could not be taken, one line each.
    private(set) var evidenceNotes: [String] = []
    /// The last scenario's recording, for its review files.
    private var lastRecording: (folder: URL, files: [ListedFile], probed: [String: ProbedFile])?

    init(app: URL, scratch: URL, restorer: Restorer, media: Media) throws {
        msr = app.appending(path: "Contents/MacOS/msr")
        guard FileManager.default.isExecutableFile(atPath: msr.path) else {
            throw DriverError("\(msr.path) does not exist; run scripts/build-app first")
        }
        guard let executable = Bundle.main.executableURL else { throw DriverError("cannot find its own executable") }
        ownExecutable = executable.resolvingSymlinksInPath().path
        self.scratch = scratch
        self.restorer = restorer
        self.media = media
        let versionFolder = scratch.appending(path: "version")
        try FileManager.default.createDirectory(at: versionFolder, withIntermediateDirectories: true)
        let process = try ChildProcess(
            executable: msr.path, arguments: ["version"], environment: ["HOME": versionFolder.path],
            standardOutput: versionFolder.appending(path: "out"), standardError: versionFolder.appending(path: "err"))
        guard process.wait(seconds: 30), process.exit == .exited(0) else {
            throw DriverError("msr version failed: \(process.errors())")
        }
        version = process.output().trimmingCharacters(in: .newlines)
        try FileManager.default.removeItem(at: versionFolder)
    }

    /// The preconditions, checked before anything changes: both permissions,
    /// asked without a prompt; the loopback device; the private interface.
    static func requirePreconditions() throws {
        guard CGPreflightScreenCaptureAccess() else {
            throw DriverError("the program running this (a terminal app) lacks the Screen & System Audio Recording permission; run msr check once from this terminal to get the prompt")
        }
        guard AVCaptureDevice.authorizationStatus(for: .audio) == .authorized else {
            throw DriverError("the program running this (a terminal app) lacks the Microphone permission; run msr check once from this terminal to get the prompt")
        }
        guard CoreAudioDevices.device(uid: Machine.loopbackUID) != nil else {
            throw DriverError("the loopback device \(Machine.loopbackName) (\(Machine.loopbackUID)) is missing; install BlackHole 2ch (brew install --cask blackhole-2ch)")
        }
        guard MSRVirtualScreen.isAvailable else {
            throw DriverError("this macOS has no CGVirtualDisplay, the private interface virtual screens need")
        }
    }

    /// One scenario: its failures, one line each.
    func run(_ scenario: Scenario) throws -> [String] {
        margin = nil
        evidenceNotes = []
        lastRecording = nil
        let folder = scratch.appending(path: scenario.name)
        try? FileManager.default.removeItem(at: folder)
        let home = folder.appending(path: "home")
        let output = folder.appending(path: "recordings")
        let logs = folder.appending(path: "logs")
        for made in [home, output, logs] { try FileManager.default.createDirectory(at: made, withIntermediateDirectories: true) }
        let ownScreenCount = Machine.screenIDs(online: false).filter { !Machine.isVirtualScreen($0) }.count

        var tone: TonePlayer?
        defer { tone?.stop() }
        if scenario.playsTone {
            tone = try TonePlayer(deviceUID: Machine.loopbackUID)
            try tone?.start()
        }

        var environment = ProcessInfo.processInfo.environment
        environment["HOME"] = home.path
        let recorder = try ChildProcess(
            executable: msr.path, arguments: scenario.arguments(outputFolder: output.path), environment: environment,
            standardOutput: logs.appending(path: "msr.out"), standardError: logs.appending(path: "msr.err"))
        defer { disconnectAllScreens() }
        try restorer.started(recorder, stopSignal: SIGINT)
        defer {
            if !recorder.hasExited {
                recorder.signal(SIGINT)
                if !recorder.wait(seconds: 60) { recorder.signal(SIGKILL); _ = recorder.wait(seconds: 5) }
            }
            try? restorer.ended(recorder)
        }

        let startDeadline = Date().addingTimeInterval(60)
        while !recorder.output().contains("\n") {
            try interruption.check()
            if recorder.hasExited || Date() > startDeadline {
                return ["msr record did not start recording (\(recorder.exit.map { "\($0)" } ?? "still running after 60 s")): \(recorder.errors())"]
            }
            Thread.sleep(forTimeInterval: 0.02)
        }
        let begun = Date()
        var happened: [(Date, Scenario.Event, String?)] = []
        for (at, event) in scenario.events {
            try interruption.sleep(until: begun.addingTimeInterval(at))
            switch event {
            case .connectScreen(let spec):
                let (process, uuid) = try VirtualScreenHelper.connect(spec, executable: ownExecutable, folder: logs)
                try restorer.started(process, stopSignal: SIGTERM)
                screens[spec.serialNumber] = (process, uuid)
                happened.append((Date(), event, uuid))
            case .switchScreenMode(let serialNumber, let size):
                guard let (process, uuid) = screens[serialNumber] else {
                    throw DriverError("\(scenario.name): no virtual screen \(serialNumber) for a mode switch")
                }
                let switched = Date()
                try VirtualScreenHelper.requestModeSwitch(process, to: size)
                happened.append((switched, event, uuid))
            case .disconnectScreen(let serialNumber):
                guard let (process, uuid) = screens.removeValue(forKey: serialNumber) else {
                    throw DriverError("\(scenario.name): no virtual screen \(serialNumber) to disconnect")
                }
                let ended = Date()
                try VirtualScreenHelper.disconnect(process, uuid: uuid)
                try restorer.ended(process)
                happened.append((ended, event, nil))
            }
        }

        if let at = scenario.statusWindowAt {
            try interruption.sleep(until: begun.addingTimeInterval(at))
            evidenceNotes += screenshot(of: recorder.pid, scenario: scenario.name, window: "status-window",
                                        opening: { try Screenshots.send(AEEventID(kAEReopenApplication), to: recorder.pid) })
            if !evidenceNotes.isEmpty { evidenceNotes += mainScreenshot(scenario: scenario.name) }
        }

        let stoppedAt: Date
        switch scenario.stop {
        case .duration:
            stoppedAt = begun.addingTimeInterval(scenario.stopAt)
        case .interrupt, .kill:
            try interruption.sleep(until: begun.addingTimeInterval(scenario.stopAt))
            stoppedAt = Date()
            recorder.signal(scenario.stop == .kill ? SIGKILL : SIGINT)
        }
        guard recorder.wait(seconds: scenario.stopAt + 60, interrupted: { interruption.happened }) else {
            try interruption.check()
            return ["msr record did not end within 60 s of its stop"]
        }
        disconnectAllScreens()
        tone?.stop()
        tone = nil

        var failures = try assertions(scenario, recorder: recorder, output: output, logs: logs, ownScreenCount: ownScreenCount,
                                      happened: happened, stoppedAt: stoppedAt)
        if let recording = lastRecording {
            do {
                try Review(scratch: scratch, scenario: scenario.name, media: media)
                    .collect(recording: recording.folder, files: recording.files, probed: recording.probed,
                             playsTone: scenario.playsTone)
            } catch {
                failures.append("the review files cannot be made: \(error)")
            }
        }
        return failures
    }

    /// The app's start window, as a person sees it on starting the app:
    /// the built app started with the scratch HOME, its window captured,
    /// then quit. Evidence only: what went wrong is returned, one line each.
    func startWindow() -> [String] {
        do {
            return try startWindowScreenshot()
        } catch {
            return ["the screenshot of the start window was not taken: \(error)"]
        }
    }

    private func startWindowScreenshot() throws -> [String] {
        let folder = scratch.appending(path: ReviewNames.appStep)
        try? FileManager.default.removeItem(at: folder)
        let home = folder.appending(path: "home")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        var environment = ProcessInfo.processInfo.environment
        environment["HOME"] = home.path
        let app = try ChildProcess(executable: msr.path, arguments: [], environment: environment,
                                   standardOutput: folder.appending(path: "app.out"), standardError: folder.appending(path: "app.err"))
        try restorer.started(app, stopSignal: SIGTERM)
        defer {
            if !app.hasExited {
                do {
                    try Screenshots.send(AEEventID(kAEQuitApplication), to: app.pid)
                } catch {
                    app.signal(SIGTERM)
                }
                if !app.wait(seconds: 15) { app.signal(SIGKILL); _ = app.wait(seconds: 5) }
            }
            try? restorer.ended(app)
            try? FileManager.default.removeItem(at: folder)
        }
        return screenshot(of: app.pid, scenario: ReviewNames.appStep, window: "start-window", opening: {})
    }

    /// The main screen instead, when the window could not be opened.
    private func mainScreenshot(scenario: String) -> [String] {
        do {
            let folder = scratch.appending(path: ReviewNames.folder).appending(path: scenario)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try Screenshots.captureMainScreen(to: folder.appending(path: ReviewNames.mainScreen(scenario: scenario)))
            return ["the main screen was taken instead"]
        } catch {
            return ["the main screen was not taken either: \(error)"]
        }
    }

    /// Opens a window of the process, waits for it, lets it draw and
    /// captures it into the review folder; what went wrong, if anything.
    private func screenshot(of pid: pid_t, scenario: String, window: String, opening: () throws -> Void) -> [String] {
        do {
            try opening()
            let id = try Screenshots.windowID(of: pid, seconds: 20)
            Thread.sleep(forTimeInterval: 1.5)
            let folder = scratch.appending(path: ReviewNames.folder).appending(path: scenario)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try Screenshots.capture(id, to: folder.appending(path: ReviewNames.screenshot(scenario: scenario, window: window)))
            return []
        } catch {
            return ["the screenshot of the \(window.replacing("-", with: " ")) was not taken: \(error)"]
        }
    }

    private func disconnectAllScreens() {
        for (serial, screen) in screens {
            try? VirtualScreenHelper.disconnect(screen.process, uuid: screen.uuid)
            try? restorer.ended(screen.process)
            screens[serial] = nil
        }
    }

    // MARK: Assertions

    private func assertions(
        _ scenario: Scenario, recorder: ChildProcess, output: URL, logs: URL, ownScreenCount: Int,
        happened: [(Date, Scenario.Event, String?)], stoppedAt: Date
    ) throws -> [String] {
        var failures: [String] = []
        let expectedExit: ChildProcess.ExitStatus = scenario.stop == .kill ? .signalled(SIGKILL) : .exited(0)
        if recorder.exit != expectedExit {
            failures.append("msr record: \(recorder.exit.map { "\($0)" } ?? "running"), expected \(expectedExit); its messages are in \(logs.path)")
        }
        let lines = recorder.output().split(separator: "\n", omittingEmptySubsequences: false)
        guard lines.count == 2, lines[1].isEmpty, let printed = lines.first,
              let folder = (try? FileManager.default.contentsOfDirectory(at: output, includingPropertiesForKeys: nil))?
                .first(where: { $0.hasDirectoryPath }),
              URL(filePath: String(printed)).standardizedFileURL.path == folder.standardizedFileURL.path
        else {
            return failures + ["standard output is \(recorder.output().debugDescription), expected the recording folder's path alone"]
        }
        let manifestFile = folder.appending(path: "recording.json")
        let manifest: JSONValue
        do {
            manifest = try JSONValue(json: Data(contentsOf: manifestFile))
        } catch {
            return failures + ["recording.json cannot be read: \(error)"]
        }
        guard let started = (manifest["started"]?.string).flatMap(Self.date) else {
            return failures + ["recording.json has no readable started"]
        }
        let seconds = { (date: Date) in date.timeIntervalSince(started) }
        let virtual = Scenario.virtualScreenExpectation(
            happened.map { HappenedEvent(at: seconds($0.0), event: $0.1, screenUUID: $0.2) },
            settleTime: EndToEndValues.settleTime)
        let stopped = scenario.stop == .duration ? scenario.stopAt : seconds(stoppedAt)
        let expectation = ManifestExpectation(
            app: "Multi Screen Recorder \(version)", settings: scenario.settings,
            ending: scenario.stop == .kill ? .killed(at: stopped) : .finalized, stoppedAt: stopped,
            ownScreenCount: ownScreenCount, virtualScreenNamePrefix: VirtualScreenSpec.namePrefix,
            virtualScreenFiles: virtual.files, virtualScreenEvents: virtual.events,
            playedAudioInputs: scenario.playsTone
                ? [.init(name: Machine.loopbackName, uid: Machine.loopbackUID, channels: 2)] : [],
            timeTolerance: EndToEndValues.timeTolerance, finalizeAllowance: EndToEndValues.finalizeAllowance,
            settleTime: EndToEndValues.settleTime)
        let names = try FileManager.default.contentsOfDirectory(atPath: folder.path)
        let check = ManifestCheck(manifest: manifest, folder: names, expectation: expectation)
        failures += check.failures
        if let ranFor = check.ranFor {
            let latestEnd = check.files.compactMap(\.end).max()
            margin = "ended − started − stop \(Self.signed(ranFor - stopped)) s, latest file end − stop "
                + (latestEnd.map { "\(Self.signed($0 - stopped)) s" } ?? "none")
        }

        var probed: [String: ProbedFile] = [:]
        for file in check.files {
            try interruption.check()
            let url = folder.appending(path: file.name)
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            do {
                let probe = try media.probe(url)
                probed[file.name] = probe
                failures += FileCheck.failures(file, probed: probe, ending: expectation.ending, slack: EndToEndValues.killSlack)
                if let errors = try media.decodeErrors(url) {
                    failures.append("\(file.name): does not decode: \(errors)")
                }
            } catch {
                failures.append("\(file.name): cannot be read: \(error)")
            }
        }
        lastRecording = (folder, check.files, probed)
        if scenario.playsTone {
            failures += try toneFailures(check.files, probed: probed, folder: folder)
        }
        return failures
    }

    /// The tone in the loopback device's audio file, and in each screen
    /// file's guide track "Audio inputs".
    private func toneFailures(_ files: [ListedFile], probed: [String: ProbedFile], folder: URL) throws -> [String] {
        func tracks(_ file: ListedFile, titled include: (String) -> Bool) throws -> [ToneCheck.Track] {
            guard let probe = probed[file.name], let start = TimecodeValue(file.timecode) else { return [] }
            return try probe.audio.filter { include($0.title ?? "") }.map { stream in
                let rate = stream.sampleRate ?? 48_000
                return ToneCheck.Track(
                    name: "\(file.name), \(stream.title ?? "track \(stream.index)")",
                    samples: try media.samples(folder.appending(path: file.name), stream: stream.index, sampleRate: rate),
                    sampleRate: Double(rate), startsAt: start.seconds)
            }
        }
        var played: [ToneCheck.Track] = []
        var mixed: [ToneCheck.Track] = []
        for file in files {
            try interruption.check()
            switch file.source {
            case .audioInput(let uid, _, _) where uid == Machine.loopbackUID:
                played += try tracks(file) { _ in true }
            case .screen:
                mixed += try tracks(file) { $0 == "Audio inputs" }
            default:
                break
            }
        }
        return ToneCheck.failures(played: played, mixed: mixed)
    }

    static func signed(_ seconds: Double) -> String { String(format: "%+.2f", seconds) }

    static func date(_ timestamp: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: timestamp)
    }
}
