import Foundation
import Synchronization

/// Every line the driver itself prints: on the terminal, and appended to
/// `run.log` in the scratch folder, so a failed pipeline run keeps them.
/// Error lines go to standard error, progress and `ok` lines to standard
/// output (D63).
enum RunLog {
    static let fileName = "run.log"
    private static let descriptor = Atomic<Int32>(-1)

    /// Starts writing the log in `scratch`; a run starts it afresh, a
    /// `restore` (also the one a run starts) adds to it.
    static func open(scratch: URL, fresh: Bool) throws {
        let path = scratch.appending(path: fileName).path
        let opened = Foundation.open(path, O_WRONLY | O_CREAT | O_APPEND | O_CLOEXEC | (fresh ? O_TRUNC : 0), 0o644)
        guard opened >= 0 else { throw DriverError("cannot write the log \(path): \(String(cString: strerror(errno)))") }
        descriptor.store(opened, ordering: .sequentiallyConsistent)
    }

    static func out(_ line: String) {
        print(line)
        append(line)
    }

    static func error(_ line: String) {
        FileHandle.standardError.write(Data("\(line)\n".utf8))
        append(line)
    }

    private static func append(_ line: String) {
        let file = descriptor.load(ordering: .sequentiallyConsistent)
        guard file >= 0 else { return }
        let bytes = Array("\(line)\n".utf8)
        _ = bytes.withUnsafeBytes { write(file, $0.baseAddress, $0.count) }
    }
}
