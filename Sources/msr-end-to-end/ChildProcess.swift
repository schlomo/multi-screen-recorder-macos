import Darwin
import Foundation

/// A process the driver starts: in a process group of its own, so a Ctrl-C
/// in the terminal reaches the driver alone, which then ends it as it
/// should; its standard output and error go to files; it inherits no other
/// open file but, for the device helper, the read end of a pipe whose write
/// end only the driver holds, so the helper sees the driver end.
final class ChildProcess {
    let pid: pid_t
    let executable: String
    let standardOutput: URL
    let standardError: URL
    private var lifeline: Int32?
    private(set) var exit: ExitStatus?

    enum ExitStatus: Equatable, CustomStringConvertible {
        case exited(Int32)
        case signalled(Int32)

        var description: String {
            switch self {
            case .exited(let code): "exit \(code)"
            case .signalled(let signal): "ended by signal \(signal)"
            }
        }
    }

    init(executable: String, arguments: [String], environment: [String: String], standardOutput: URL,
         standardError: URL, lifeline: Bool = false) throws {
        self.executable = executable
        self.standardOutput = standardOutput
        self.standardError = standardError
        var actions = posix_spawn_file_actions_t(nil as OpaquePointer?)
        posix_spawn_file_actions_init(&actions)
        defer { posix_spawn_file_actions_destroy(&actions) }
        var pipeEnds: [Int32] = [0, 0]
        if lifeline {
            guard pipe(&pipeEnds) == 0 else { throw DriverError("cannot make a pipe: \(String(cString: strerror(errno)))") }
            posix_spawn_file_actions_adddup2(&actions, pipeEnds[0], STDIN_FILENO)
        } else {
            posix_spawn_file_actions_addopen(&actions, STDIN_FILENO, "/dev/null", O_RDONLY, 0)
        }
        posix_spawn_file_actions_addopen(&actions, STDOUT_FILENO, standardOutput.path, O_WRONLY | O_CREAT | O_TRUNC, 0o644)
        posix_spawn_file_actions_addopen(&actions, STDERR_FILENO, standardError.path, O_WRONLY | O_CREAT | O_TRUNC, 0o644)
        var attributes = posix_spawnattr_t(nil as OpaquePointer?)
        posix_spawnattr_init(&attributes)
        defer { posix_spawnattr_destroy(&attributes) }
        posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETPGROUP | POSIX_SPAWN_CLOEXEC_DEFAULT | POSIX_SPAWN_SETSIGDEF))
        posix_spawnattr_setpgroup(&attributes, 0)
        var defaults = sigset_t()
        sigemptyset(&defaults)
        for signal in [SIGINT, SIGTERM, SIGHUP, SIGPIPE] { sigaddset(&defaults, signal) }
        posix_spawnattr_setsigdefault(&attributes, &defaults)

        let argv = ([executable] + arguments).map { strdup($0) } + [nil]
        let envp = environment.map { strdup("\($0.key)=\($0.value)") } + [nil]
        defer { (argv + envp).forEach { free($0) } }
        var pid: pid_t = 0
        let status = posix_spawn(&pid, executable, &actions, &attributes, argv, envp)
        if lifeline { close(pipeEnds[0]) }
        guard status == 0 else {
            if lifeline { close(pipeEnds[1]) }
            throw DriverError("cannot start \(executable): \(String(cString: strerror(status)))")
        }
        if lifeline {
            _ = fcntl(pipeEnds[1], F_SETFD, FD_CLOEXEC)
            self.lifeline = pipeEnds[1]
        }
        self.pid = pid
    }

    deinit {
        if let lifeline { close(lifeline) }
    }

    /// Whether it has ended, collecting its status once it has.
    var hasExited: Bool {
        if exit != nil { return true }
        var status: Int32 = 0
        guard waitpid(pid, &status, WNOHANG) == pid else { return false }
        let low = status & 0x7f
        exit = low == 0 ? .exited((status >> 8) & 0xff) : .signalled(low)
        return true
    }

    /// Writes to its standard input, the lifeline.
    func send(_ text: String) throws {
        guard let lifeline else { throw DriverError("\(executable) has no standard input to write to") }
        let bytes = Array(text.utf8)
        guard write(lifeline, bytes, bytes.count) == bytes.count else {
            throw DriverError("cannot write to \(executable): \(String(cString: strerror(errno)))")
        }
    }

    func signal(_ number: Int32) {
        if !hasExited { kill(pid, number) }
    }

    /// Waits up to `seconds` for it to end; true when it did.
    func wait(seconds: Double, interrupted: () -> Bool = { false }) -> Bool {
        let deadline = Date().addingTimeInterval(seconds)
        while !hasExited {
            if Date() > deadline || interrupted() { return false }
            Thread.sleep(forTimeInterval: 0.02)
        }
        return true
    }

    func output() -> String { (try? String(contentsOf: standardOutput, encoding: .utf8)) ?? "" }
    func errors() -> String { (try? String(contentsOf: standardError, encoding: .utf8)) ?? "" }
}

/// The executable at a process ID, or nil when there is none.
func executablePath(of pid: pid_t) -> String? {
    var buffer = [UInt8](repeating: 0, count: Int(4 * MAXPATHLEN))
    let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
    guard length > 0 else { return nil }
    return String(decoding: buffer.prefix(Int(length)), as: UTF8.self)
}
