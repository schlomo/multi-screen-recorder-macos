import AppKit
import ArgumentParser
import RecorderCore

/// With arguments msr is the command line; without, it is the app. Started
/// through a symbolic link, it first re-executes itself at its real path.
@main
enum EntryPoint {
    static func main() {
        reexecuteAtRealPathIfLinked()
        switch EntryRoute(arguments: Array(CommandLine.arguments.dropFirst())) {
        case .app:
            let delegate = AppDelegate()
            EventLoop.run(delegate, activationPolicy: .regular)
        case .record(let record):
            let delegate = RecordCommandDelegate(record: record)
            // A full AppKit app without a Dock icon; the icon shows once the recording starts.
            EventLoop.run(delegate, activationPolicy: .accessory)
            exit(delegate.exitStatus)
        case .command(let command):
            runWithoutEventLoop(command)
        case .failed(let error):
            CommandLineInterface.exit(withError: error)
        }
    }

    /// The other commands run as tasks while the main queue is drained.
    private static func runWithoutEventLoop(_ command: sending any ParsableCommand) -> Never {
        Task.detached {
            do {
                if var command = command as? any AsyncParsableCommand {
                    try await command.run()
                } else {
                    var command = command
                    try command.run()
                }
                CommandLineInterface.exit()
            } catch {
                CommandLineInterface.exit(withError: error)
            }
        }
        dispatchMain()
    }
}

/// What `main` runs, decided before anything runs.
enum EntryRoute {
    case app
    case record(CommandLineInterface.Record)
    case command(any ParsableCommand)
    /// Wrong arguments, or `--help`: the parser's own exit.
    case failed(any Error)

    init(arguments: [String]) {
        guard !arguments.isEmpty else {
            self = .app
            return
        }
        do {
            let command = try CommandLineInterface.parseAsRoot(arguments)
            self = if let record = command as? CommandLineInterface.Record { .record(record) } else { .command(command) }
        } catch {
            self = .failed(error)
        }
    }
}

/// The AppKit event loop of the app and of `msr record`: macOS reports
/// screen changes only under `NSApplication.run()` (D45). Started from
/// `main` itself: inside a main-queue job the loop would never drain the
/// main queue, so no task, signal source or screen callback would run.
@MainActor
enum EventLoop {
    static func run(_ delegate: some NSApplicationDelegate, activationPolicy: NSApplication.ActivationPolicy) {
        let app = NSApplication.shared
        app.delegate = delegate
        app.setActivationPolicy(activationPolicy)
        withExtendedLifetime(delegate) { app.run() }
    }
}
