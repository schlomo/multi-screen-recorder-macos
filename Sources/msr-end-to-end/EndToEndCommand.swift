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
}

/// An error line: on standard error, where a program's errors go; progress
/// and `ok` lines stay on standard output.
func printError(_ line: String) {
    FileHandle.standardError.write(Data("\(line)\n".utf8))
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

    @OptionGroup var scratch: ScratchOption

    func validate() throws {
        for name in scenarioNames where !Scenario.named.contains(where: { $0.name == name }) {
            throw ValidationError("no scenario \(name); the scenarios: \(Scenario.named.map(\.name).joined(separator: ", "))")
        }
    }

    func run() throws {
        let scenarios = scenarioNames.isEmpty ? Scenario.named : Scenario.named.filter { scenarioNames.contains($0.name) }
        let scratchFolder = try EndToEndCommand.scratchFolder(scratch.scratchFolder)
        let media = try Media(scratch: scratchFolder)
        try Driver.requirePreconditions()
        let restorer = Restorer(scratch: scratchFolder)
        let driver = try Driver(app: URL(filePath: app), scratch: scratchFolder, restorer: restorer, media: media)
        _ = try restorer.save()
        Interruption.shared.watch()
        setvbuf(stdout, nil, _IOLBF, 0)
        print("msr-end-to-end: \(driver.version), \(scenarios.count) scenarios; the Mac cannot be used until they end")
        var failed = 0
        var stopped: Error?
        for scenario in scenarios {
            let began = Date()
            do {
                let failures = try driver.run(scenario)
                let took = String(format: "%.0f s", Date().timeIntervalSince(began))
                let folder = scratchFolder.appending(path: scenario.name)
                if failures.isEmpty {
                    print("ok    \(scenario.name) (\(took)): \(scenario.summary)")
                    try? FileManager.default.removeItem(at: folder)
                } else {
                    failed += 1
                    printError("FAIL  \(scenario.name) (\(took)): \(scenario.summary)")
                    for failure in failures { printError("      \(failure)") }
                    printError("      kept: \(folder.path)")
                }
                if let margin = driver.margin { print("      margin: \(margin)") }
            } catch {
                stopped = error
                printError("STOP  \(scenario.name): \(error); kept: \(scratchFolder.appending(path: scenario.name).path)")
                break
            }
            guard restore(driver, keepingFile: true) else { break }
            if Interruption.shared.happened {
                stopped = DriverError("interrupted")
                printError("STOP  interrupted after \(scenario.name)")
                break
            }
        }
        let restored = restore(driver, keepingFile: false)
        if let stopped { throw stopped }
        if !restored { throw ExitCode.failure }
        if failed > 0 {
            printError("msr-end-to-end: \(failed) of \(scenarios.count) scenarios failed")
            throw ExitCode.failure
        }
        print("msr-end-to-end: all \(scenarios.count) scenarios passed")
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
            printError("restore: FAILED to start: \(error); run scripts/end-to-end-test restore")
            return false
        }
        if process.terminationStatus != 0 { printError("restore: FAILED; run scripts/end-to-end-test restore") }
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
        let restorer = Restorer(scratch: try EndToEndCommand.scratchFolder(scratch.scratchFolder))
        guard restorer.exists else {
            print("restore: no restore file, nothing to restore (\(restorer.file.path))")
            try VirtualScreenHelper.waitUntilNoVirtualScreen(seconds: 0)
            return
        }
        let still = try restorer.restore(removingFile: !keepRestoreFile)
        for line in still { printError("restore: NOT RESTORED  \(line)") }
        if !still.isEmpty {
            printError("restore: the restore file is kept: \(restorer.file.path)")
            throw ExitCode.failure
        }
        if !keepRestoreFile { print("restore: the Mac is as it was before the run") }
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
