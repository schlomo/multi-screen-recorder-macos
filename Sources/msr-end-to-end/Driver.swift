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
    /// The last scenario's events: when each was asked and done, and the
    /// width of the window the recorder's time for it must lie in.
    private(set) var eventWindows: [String] = []
    /// The last scenario's breaks in playback on the loopback device; nil
    /// without the tone.
    private(set) var playbackBreaks: [PlaybackBreak]?
    /// How many there were, those beyond what the player's log holds included.
    private(set) var playbackBreakCount: Int?
    /// The last scenario's failing click spacings pardoned because the player broke (D67).
    private(set) var pardons: [String] = []
    /// The last scenario's recording, for its review files.
    private var lastRecording: (folder: URL, files: [ListedFile], probed: [String: ProbedFile])?

    /// Told by scripts/end-to-end-test: the throwaway VM, where the system appearance may be
    /// switched and the status and Finder windows are driven.
    let inThrowawayVM: Bool
    /// Told by `msr-end-to-end app-windows`: the person's own Mac, where only the app's windows are taken,
    /// in light, with no virtual screen and no window moved (D82).
    let onThisMac: Bool
    var appearances: [Appearance] { Appearance.taken(inThrowawayVM: inThrowawayVM) }

    init(app: URL, scratch: URL, restorer: Restorer, media: Media, inThrowawayVM: Bool, onThisMac: Bool = false) throws {
        self.inThrowawayVM = inThrowawayVM
        self.onThisMac = onThisMac
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
        try requireScreenRecording()
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

    static func requireScreenRecording() throws {
        guard CGPreflightScreenCaptureAccess() else {
            throw DriverError("the program running this (a terminal app) lacks the Screen & System Audio Recording permission; grant it in System Settings > Privacy & Security > Screen & System Audio Recording, or run msr check once from this terminal to get the prompt")
        }
    }

    /// One scenario: its failures, one line each. A failed scenario also
    /// saves the system log since its start (`SystemLog`); a system log
    /// that cannot be saved is a failure line of its own.
    func run(_ scenario: Scenario) throws -> [String] {
        let started = Date()
        var failures = try runScenario(scenario)
        if !failures.isEmpty {
            do {
                try saveSystemLog(since: started, to: scratch.appending(path: scenario.name).appending(path: "logs"))
            } catch {
                failures.append("the system log cannot be saved: \(error)")
            }
        }
        return failures
    }

    /// `log show` since `date`, filtered to the video, media and display subsystems, into `system.log` of `logs`.
    private func saveSystemLog(since date: Date, to logs: URL) throws {
        let process = try ChildProcess(
            executable: Media.onPath("log"), arguments: SystemLog.arguments(since: date),
            environment: ProcessInfo.processInfo.environment, standardOutput: logs.appending(path: SystemLog.fileName),
            standardError: logs.appending(path: "system-log.err"))
        guard process.wait(seconds: 300, interrupted: { interruption.happened }) else {
            process.signal(SIGKILL)
            throw DriverError("log show did not end within 300 s")
        }
        guard process.exit == .exited(0) else {
            throw DriverError("log show ended with \(process.exit.map { "\($0)" } ?? "no status"): \(process.errors())")
        }
    }

    private func runScenario(_ scenario: Scenario) throws -> [String] {
        margin = nil
        eventWindows = []
        playbackBreaks = nil
        playbackBreakCount = nil
        pardons = []
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
            standardOutput: logs.appending(path: "msr.out"), standardError: logs.appending(path: ReviewNames.standardError))
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
        var happened: [(asked: Date, done: Date, lastChange: Date, event: Scenario.Event, uuid: String?)] = []
        for (at, event) in scenario.events {
            try interruption.sleep(until: begun.addingTimeInterval(at))
            let watch = ScreenWatch()
            defer { watch.stop() }
            let asked = Date()
            let done: Date
            let uuid: String
            switch event {
            case .connectScreen(let spec):
                let process: ChildProcess
                (process, uuid) = try VirtualScreenHelper.connect(spec, executable: ownExecutable, folder: logs)
                done = Date()
                try restorer.started(process, stopSignal: SIGTERM)
                screens[spec.serialNumber] = (process, uuid)
            case .switchScreenMode(let serialNumber, let size):
                guard let screen = screens[serialNumber] else {
                    throw DriverError("\(scenario.name): no virtual screen \(serialNumber) for a mode switch")
                }
                uuid = screen.uuid
                try VirtualScreenHelper.requestModeSwitch(screen.process, to: size)
                done = Date()
            case .disconnectScreen(let serialNumber):
                guard let screen = screens.removeValue(forKey: serialNumber) else {
                    throw DriverError("\(scenario.name): no virtual screen \(serialNumber) to disconnect")
                }
                uuid = screen.uuid
                try VirtualScreenHelper.disconnect(screen.process, uuid: uuid)
                done = Date()
                try restorer.ended(screen.process)
            }
            guard let lastChange = try lastChange(of: uuid, watch: watch, done: done) else {
                return ["\(Self.describe(event)): the screen did not settle within \(Int(EndToEndValues.screensSettleLimit)) s"]
            }
            happened.append((asked, done, lastChange, event, uuid))
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
        playbackBreaks = tone?.breaks()
        playbackBreakCount = tone?.breakCount
        tone = nil

        var failures = try assertions(scenario, recorder: recorder, output: output, logs: logs, ownScreenCount: ownScreenCount,
                                      happened: happened, stoppedAt: stoppedAt)
        if let recording = lastRecording {
            do {
                try Review(scratch: scratch, scenario: scenario.name, media: media)
                    .collect(recording: recording.folder, logs: logs, files: recording.files, probed: recording.probed,
                             playsTone: scenario.playsTone)
            } catch {
                failures.append("the review files cannot be made: \(error)")
            }
        }
        return failures
    }

    /// The app's start window in each appearance to take.
    func startWindow() throws {
        for appearance in appearances {
            try Screenshots.withAppearance(appearance) { try startWindow(in: appearance) }
        }
    }

    /// The app's start window, as a person sees it on starting the app:
    /// the built app started with the scratch HOME, brought to the front,
    /// its window captured into the review folder, then quit. Its folder stays.
    private func startWindow(in appearance: Appearance) throws {
        let folder = scratch.appending(path: "\(ReviewNames.appStep)-\(appearance.rawValue)")
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
                if !app.wait(seconds: 15, interrupted: { interruption.happened }) {
                    app.signal(SIGKILL)
                    _ = app.wait(seconds: 5)
                }
            }
            try? restorer.ended(app)
        }
        let id = try Screenshots.windowID(of: app.pid, seconds: 20, interruption: interruption)
        try Screenshots.bringToFront(app.pid)
        try interruption.sleep(until: Date().addingTimeInterval(1.5))
        let review = scratch.appending(path: ReviewNames.folder).appending(path: ReviewNames.appStep)
        try FileManager.default.createDirectory(at: review, withIntermediateDirectories: true)
        try Screenshots.capture(id, to: review.appending(path: ReviewNames.screenshot(scenario: ReviewNames.appStep, window: "start-window", appearance: appearance)))
    }

    /// The changed screen's last change, once it has been unchanged for the
    /// settle time after it (`ScreenSettling`); nil when it has not within
    /// the limit after the done.
    private func lastChange(of uuid: String, watch: ScreenWatch, done: Date) throws -> Date? {
        let deadline = done.addingTimeInterval(EndToEndValues.screensSettleLimit)
        while true {
            try interruption.check()
            let observations = watch.observations(since: done)
            if let lastChange = ScreenSettling.lastChange(of: uuid, observations: observations, settleTime: EndToEndValues.settleTime) {
                return done.addingTimeInterval(lastChange)
            }
            guard Date() < deadline else { return nil }
            Thread.sleep(forTimeInterval: 0.02)
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
        happened: [(asked: Date, done: Date, lastChange: Date, event: Scenario.Event, uuid: String?)], stoppedAt: Date
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
        let changes = happened.map {
            HappenedEvent(times: ChangeTimes(asked: seconds($0.asked), done: seconds($0.done), lastChange: seconds($0.lastChange)),
                          event: $0.event, screenUUID: $0.uuid)
        }
        let virtual = Scenario.virtualScreenExpectation(changes)
        let stopped = scenario.stop == .duration ? scenario.stopAt : seconds(stoppedAt)
        let expectation = ManifestExpectation(
            app: "Multi Screen Recorder \(version)", settings: scenario.settings,
            ending: scenario.stop == .kill ? .killed(at: stopped) : .finalized, stoppedAt: stopped,
            ownScreenCount: ownScreenCount, virtualScreenNames: scenario.events.compactMap {
                if case .connectScreen(let spec) = $0.event { spec.name } else { nil }
            },
            virtualScreenFiles: virtual.files, virtualScreenEvents: virtual.events,
            playedAudioInputs: scenario.playsTone
                ? [.init(name: Machine.loopbackName, uid: Machine.loopbackUID, channels: 2)] : [],
            timeTolerance: EndToEndValues.timeTolerance, finalizeAllowance: EndToEndValues.finalizeAllowance,
            settleTime: EndToEndValues.settleTime, firstFrameLimit: EndToEndValues.firstFrameLimit)
        let names = try FileManager.default.contentsOfDirectory(atPath: folder.path)
        let check = ManifestCheck(manifest: manifest, folder: names, expectation: expectation)
        eventWindows = changes.enumerated().map { index, change in
            var times = change.times
            times.notice = check.notices[index]
            let width = { (kind: TimingKind) in
                times.windowWidth(kind, settleTime: EndToEndValues.settleTime, tolerance: EndToEndValues.timeTolerance,
                                  firstFrameLimit: EndToEndValues.firstFrameLimit)
            }
            let startedFile = expectation.virtualScreenFiles.firstIndex { $0.startedBy == change.times }
            let startUp = startedFile.map { file in
                check.startUps[file].map { String(format: "; its file started %.2f s after the settle time", $0) }
                    ?? "; its file's start-up was not measured"
            } ?? ""
            let anchor = times.anchor.map { String(format: "anchored at %.2f s, %@", $0.time, $0.source.description) } ?? "no anchor"
            return String(format: "%@ asked at %.2f s, done at %.2f s, the screen last changed at %.2f s, %@: the settled window is %.2f s wide, a file start's %.2f s, the immediate one %.2f s%@",
                          Self.describe(change.event), times.asked, times.done, times.lastChange ?? .nan, anchor,
                          width(.settled), width(.started), width(.immediate), startUp)
        }
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
                    sampleRate: Double(rate), startsAt: stream.firstSampleTime(fileStartsAt: start.seconds))
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
        let result = ToneCheck.check(played: played, mixed: mixed, breaks: playbackBreaks ?? [])
        pardons += result.pardoned
        return result.failures
    }

    static func describe(_ event: Scenario.Event) -> String {
        switch event {
        case .connectScreen(let spec): "the connect of \(spec.name) (virtual screen \(spec.serialNumber))"
        case .switchScreenMode(let serialNumber, let size): "the mode switch of virtual screen \(serialNumber) to \(size)"
        case .disconnectScreen(let serialNumber): "the disconnect of virtual screen \(serialNumber)"
        }
    }

    static func signed(_ seconds: Double) -> String { String(format: "%+.2f", seconds) }

    static func date(_ timestamp: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: timestamp)
    }
}
