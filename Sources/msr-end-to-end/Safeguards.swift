import CoreGraphics
import Dispatch
import EndToEndLogic
import Foundation
import Synchronization

/// Ctrl-C, SIGTERM and SIGHUP while the driver runs: noted, so the run
/// stops at its next step and restores the Mac.
final class Interruption: Sendable {
    static let shared = Interruption()
    private let flag = Atomic<Bool>(false)
    private let sources = Mutex<[any DispatchSourceSignal]>([])

    var happened: Bool { flag.load(ordering: .relaxed) }

    func watch() {
        let queue = DispatchQueue(label: "signals")
        let made = [SIGINT, SIGTERM, SIGHUP].map { number in
            signal(number, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: number, queue: queue)
            source.setEventHandler { [self] in flag.store(true, ordering: .relaxed) }
            source.resume()
            return source
        }
        sources.withLock { $0 = made }
    }

    func check() throws {
        if happened { throw DriverError("interrupted") }
    }

    /// Sleeps until `deadline`, stopping early when interrupted.
    func sleep(until deadline: Date) throws {
        while Date() < deadline {
            try check()
            Thread.sleep(forTimeInterval: min(0.02, max(0, deadline.timeIntervalSinceNow)))
        }
    }
}

/// The restore file in the scratch folder and the restore itself
/// (docs/design/end-to-end-tests.md, "Safeguards for the person's session").
struct Restorer {
    let file: URL

    init(scratch: URL) {
        file = scratch.appending(path: "restore.json")
    }

    var exists: Bool { FileManager.default.fileExists(atPath: file.path) }

    func read() throws -> RestoreFile {
        do {
            return try RestoreFile(json: Data(contentsOf: file))
        } catch {
            throw DriverError("cannot read the restore file \(file.path): \(error)")
        }
    }

    func write(_ restore: RestoreFile) throws {
        try restore.jsonData().write(to: file, options: .atomic)
    }

    /// Saves what a run may change; refuses when a restore file is left
    /// from a run that did not restore.
    func save() throws -> RestoreFile {
        if exists {
            throw DriverError("a run did not restore the Mac: run msr-end-to-end restore --scratch-folder \(file.deletingLastPathComponent().path) first (\(file.path))")
        }
        let restore = RestoreFile(saved: try Machine.state())
        try write(restore)
        return restore
    }

    func started(_ process: ChildProcess, stopSignal: Int32) throws {
        var restore = try read()
        restore.processes.append(.init(pid: process.pid, executable: process.executable, stopSignal: stopSignal))
        try write(restore)
    }

    func ended(_ process: ChildProcess) throws {
        var restore = try read()
        restore.processes.removeAll { $0.pid == process.pid }
        try write(restore)
    }

    /// Ends the processes the run left, removes the tests' virtual screens
    /// and aggregate devices, puts back what changed and reads it back.
    /// Returns what is still different, which only the person can put
    /// back; removes the restore file when nothing is.
    @discardableResult
    func restore(removingFile: Bool) throws -> [String] {
        let restore = try read()
        for process in restore.processes {
            guard let path = executablePath(of: process.pid),
                  URL(filePath: path).resolvingSymlinksInPath() == URL(filePath: process.executable).resolvingSymlinksInPath()
            else { continue }
            RunLog.out("restore: ending \(process.executable) (\(process.pid))")
            kill(process.pid, process.stopSignal)
            let deadline = Date().addingTimeInterval(30)
            while kill(process.pid, 0) == 0, Date() < deadline { Thread.sleep(forTimeInterval: 0.05) }
            if kill(process.pid, 0) == 0 { kill(process.pid, SIGKILL) }
        }
        try VirtualScreenHelper.waitUntilNoVirtualScreen(seconds: 5)
        for uid in try Machine.removeTestAggregateDevices() { RunLog.out("restore: removed the aggregate device \(uid)") }
        let plan = RestorePlan(saved: restore.saved, current: try Machine.state())
        try Machine.apply(plan, saved: restore.saved)
        if !plan.actions.isEmpty {
            RunLog.out("restore: put back \(plan.actions.map { "\($0)" }.joined(separator: ", "))")
            Thread.sleep(forTimeInterval: 1)
        }
        let differences = restore.saved.differences(to: try Machine.freshState())
        if differences.isEmpty {
            var cleared = restore
            cleared.processes = []
            try write(cleared)
            if removingFile { try FileManager.default.removeItem(at: file) }
        }
        return differences
    }
}
