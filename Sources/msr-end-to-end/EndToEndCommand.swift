import ArgumentParser
import EndToEndLogic
import Foundation

@main
struct EndToEndCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "msr-end-to-end",
        abstract: "The end-to-end tests: record with the built app while screens and audio change, then examine the recording folder.",
        discussion: """
            A run adds virtual screens and records every screen and audio input of this Mac: the Mac cannot be \
            used meanwhile. It needs ffmpeg and ffprobe on the PATH, BlackHole 2ch, and both permissions for \
            the program running it. See docs/design/end-to-end-tests.md.
            """,
        subcommands: [Run.self, Restore.self, State.self, VirtualScreenCommand.self, SwitchMode.self],
        defaultSubcommand: Run.self)

    static func scratchFolder(_ given: String?) throws -> URL {
        let folder = given.map { URL(filePath: $0) }
            ?? FileManager.default.temporaryDirectory.appending(path: "msr-end-to-end")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.resolvingSymlinksInPath()
    }

    /// Runs a subcommand's body with the log open in the scratch folder; an
    /// error is logged on standard error and the exit is non-zero.
    static func logged(scratch: String?, fresh: Bool, _ body: (URL) throws -> Void) throws {
        setvbuf(stdout, nil, _IOLBF, 0)
        let folder = try scratchFolder(scratch)
        try RunLog.open(scratch: folder, fresh: fresh)
        do {
            try body(folder)
        } catch let exit as ExitCode {
            throw exit
        } catch {
            RunLog.error("msr-end-to-end: \(error)")
            throw ExitCode.failure
        }
    }
}

struct ScratchOption: ParsableArguments {
    @Option(help: "The folder for the restore file and the recordings (default: msr-end-to-end in the temporary folder).")
    var scratchFolder: String?
}

struct Run: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Runs the named scenarios (all by default).")

    @Option(help: "The app bundle under test, as scripts/build-app builds it.")
    var app = "build/Multi Screen Recorder.app"

    @Option(name: .customLong("scenario"), help: "A scenario to run; repeat for several. One of: \(Scenario.named.map(\.name).joined(separator: ", ")).")
    var scenarioNames: [String] = []

    @Flag(help: "Told by scripts/end-to-end-test: this runs in the throwaway VM, where the driver may switch the system appearance to dark for the start window's screenshot. Without it, light only.")
    var throwawayVM = false

    @OptionGroup var scratch: ScratchOption

    func validate() throws {
        for name in scenarioNames where !Scenario.named.contains(where: { $0.name == name }) {
            throw ValidationError("no scenario \(name); the scenarios: \(Scenario.named.map(\.name).joined(separator: ", "))")
        }
    }

    func run() throws {
        try EndToEndCommand.logged(scratch: scratch.scratchFolder, fresh: true, run(in:))
    }

    private func run(in scratchFolder: URL) throws {
        let scenarios = scenarioNames.isEmpty ? Scenario.named : Scenario.named.filter { scenarioNames.contains($0.name) }
        let media = try Media(scratch: scratchFolder)
        try Driver.requirePreconditions()
        let restorer = Restorer(scratch: scratchFolder)
        let driver = try Driver(
            app: URL(filePath: app), scratch: scratchFolder, restorer: restorer, media: media,
            inThrowawayVM: throwawayVM)
        _ = try restorer.save()
        Interruption.shared.watch()
        RunLog.out("msr-end-to-end: \(driver.version), \(scenarios.count) scenarios; the Mac cannot be used until they end")
        Review.clear(scratch: scratchFolder)
        var tally = RunTally(total: scenarios.count)
        do {
            try driver.startWindow()
            try driver.recordingWindows()
            RunLog.out("ok    \(ReviewNames.appStep): the start window's screenshot")
        } catch {
            let failure = "the start window's screenshot was not taken: \(error)"
            tally.stepFailed(failure)
            RunLog.error("FAIL  \(ReviewNames.appStep): \(failure)")
        }
        for scenario in scenarios {
            if Interruption.shared.happened {
                tally.stopped("interrupted before \(scenario.name)")
                RunLog.error("STOP  interrupted before \(scenario.name)")
                break
            }
            let began = Date()
            do {
                let failures = try driver.run(scenario)
                let seconds = Int(Date().timeIntervalSince(began).rounded())
                let folder = scratchFolder.appending(path: scenario.name)
                if failures.isEmpty {
                    tally.passed()
                    RunLog.out("ok    \(scenario.name) (\(seconds) s): \(scenario.summary)")
                } else {
                    tally.failed()
                    RunLog.error("FAIL  \(scenario.name) (\(seconds) s): \(scenario.summary)")
                    for failure in failures { RunLog.error("      \(failure)") }
                    RunLog.error("      kept: \(folder.path)")
                }
                if let margin = driver.margin { RunLog.out("      margin: \(margin)") }
                for window in driver.eventWindows { RunLog.out("      window: \(window)") }
                if let count = driver.playbackBreakCount { RunLog.out("      playback breaks: \(count)") }
                for pardon in driver.pardons { RunLog.out("      \(pardon)") }
            } catch {
                tally.stopped("\(scenario.name): \(error)")
                RunLog.error("STOP  \(scenario.name): \(error); kept: \(scratchFolder.appending(path: scenario.name).path)")
                break
            }
            guard restore(driver, keepingFile: true) else {
                tally.stopped("the restore after \(scenario.name) failed")
                RunLog.error("STOP  the restore after \(scenario.name) failed")
                break
            }
            if Interruption.shared.happened {
                tally.stopped("interrupted after \(scenario.name)")
                RunLog.error("STOP  interrupted after \(scenario.name)")
                break
            }
        }
        let verdict = tally.verdict(finalRestoreSucceeded: restore(driver, keepingFile: false))
        switch verdict {
        case .passed(let line):
            RunLog.out(line)
        case .failed(let lines):
            for line in lines { RunLog.error(line) }
            throw ExitCode.failure
        }
    }

    /// Runs `restore` in a process of its own, as a person would, so it
    /// reads the screens afresh; whether the Mac is as it was.
    private func restore(_ driver: Driver, keepingFile: Bool) -> Bool {
        let arguments = ["restore", "--scratch-folder", driver.scratch.path] + (keepingFile ? ["--keep-restore-file"] : [])
        let process = Foundation.Process()
        process.executableURL = URL(filePath: driver.ownExecutable)
        process.arguments = arguments
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            RunLog.error("restore: FAILED to start: \(error); run msr-end-to-end restore --scratch-folder \(driver.scratch.path)")
            return false
        }
        if process.terminationStatus != 0 { RunLog.error("restore: FAILED; run msr-end-to-end restore --scratch-folder \(driver.scratch.path)") }
        return process.terminationStatus == 0
    }
}

struct Restore: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Puts back what a run changed, from the restore file, should the driver itself have been killed.")

    @OptionGroup var scratch: ScratchOption

    @Flag(help: "Keep the restore file once restored, for the next scenario of a run.")
    var keepRestoreFile = false

    func run() throws {
        // A Ctrl-C meant for the driver must never cut a restore short.
        signal(SIGINT, SIG_IGN)
        try EndToEndCommand.logged(scratch: scratch.scratchFolder, fresh: false, run(in:))
    }

    private func run(in scratchFolder: URL) throws {
        let restorer = Restorer(scratch: scratchFolder)
        guard restorer.exists else {
            RunLog.out("restore: no restore file, nothing to restore (\(restorer.file.path))")
            try VirtualScreenHelper.waitUntilNoVirtualScreen(seconds: 0)
            return
        }
        let still = try restorer.restore(removingFile: !keepRestoreFile)
        for line in still { RunLog.error("restore: NOT RESTORED  \(line)") }
        if !still.isEmpty {
            RunLog.error("restore: the restore file is kept: \(restorer.file.path)")
            throw ExitCode.failure
        }
        if !keepRestoreFile { RunLog.out("restore: the Mac is as it was before the run") }
    }
}

struct State: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Prints what a run may change, as the restore file saves it: screens, default devices, the loopback device.")

    func run() throws {
        print(String(decoding: try RestoreFile(saved: Machine.state()).jsonData(), as: UTF8.self))
    }
}

struct VirtualScreenCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "virtual-screen",
        abstract: "The device helper: holds one virtual screen until SIGTERM or until standard input closes.")

    @Option var serialNumber: UInt32
    @Option(name: .customLong("size"), help: "A mode, such as 1280x720; repeat for more, the first is the one it starts at.",
            transform: { text in
                guard let size = ScreenSize(text) else { throw ValidationError("a size is <width>x<height>, not \(text)") }
                return size
            })
    var sizes: [ScreenSize]

    func run() throws {
        try VirtualScreenHelper.hold(VirtualScreenSpec(serialNumber: serialNumber, sizes: sizes))
    }
}

struct SwitchMode: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "switch-mode",
        abstract: "The device helper's mode switch: a virtual screen of the tests to another of its modes.")

    @Option var screenUUID: String
    @Option(transform: { text in
        guard let size = ScreenSize(text) else { throw ValidationError("a size is <width>x<height>, not \(text)") }
        return size
    })
    var size: ScreenSize

    func run() throws {
        try VirtualScreenHelper.switchMode(uuid: screenUUID, to: size)
    }
}
