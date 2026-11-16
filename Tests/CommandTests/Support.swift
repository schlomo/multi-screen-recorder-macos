import Foundation
import Testing

/// What a command did.
struct CommandOutcome {
    let status: Int32
    let output: String
    let errors: String
}

/// How many programs the tests run at once: one per processor. Waiting off
/// the pool lets every test start its program together, over a hundred at
/// once, which starves the timing of the other tests in the process.
actor ProgramSlots {
    static let shared = ProgramSlots(ProcessInfo.processInfo.activeProcessorCount)

    private var free: Int
    private var waiting: [CheckedContinuation<Void, Never>] = []

    init(_ count: Int) { free = count }

    func take() async {
        if free > 0 {
            free -= 1
        } else {
            await withCheckedContinuation { waiting.append($0) }
        }
    }

    func give() {
        if waiting.isEmpty { free += 1 } else { waiting.removeFirst().resume() }
    }
}

/// Runs a program with exactly the given environment, so nothing of the
/// ambient one leaks into what is tested; PATH is passed through. Output and
/// errors go to files, so a child filling either cannot block on a full pipe.
/// Waits for the program's end without blocking a thread of the test's pool,
/// and for a free slot (`ProgramSlots`) before it starts.
func run(_ program: URL, _ arguments: [String] = [], environment: [String: String] = [:],
         in folder: URL? = nil) async throws -> CommandOutcome {
    await ProgramSlots.shared.take()
    do {
        let outcome = try await runInSlot(program, arguments, environment: environment, in: folder)
        await ProgramSlots.shared.give()
        return outcome
    } catch {
        await ProgramSlots.shared.give()
        throw error
    }
}

private func runInSlot(_ program: URL, _ arguments: [String], environment: [String: String],
                       in folder: URL?) async throws -> CommandOutcome {
    let process = Process()
    process.executableURL = program
    process.arguments = arguments
    process.environment = environment.merging(
        ["PATH": try #require(ProcessInfo.processInfo.environment["PATH"])]) { given, _ in given }
    if let folder { process.currentDirectoryURL = folder }
    let capture = FileManager.default.temporaryDirectory
        .appending(path: "run-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: capture, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: capture) }
    let outputFile = capture.appending(path: "output")
    let errorsFile = capture.appending(path: "errors")
    for file in [outputFile, errorsFile] {
        try #require(FileManager.default.createFile(atPath: file.path(percentEncoded: false), contents: nil))
    }
    let output = try FileHandle(forWritingTo: outputFile)
    let errors = try FileHandle(forWritingTo: errorsFile)
    defer { try? output.close(); try? errors.close() }
    process.standardOutput = output
    process.standardError = errors
    try await withCheckedThrowingContinuation { (ended: CheckedContinuation<Void, any Error>) in
        process.terminationHandler = { _ in ended.resume() }
        do {
            try process.run()
        } catch {
            ended.resume(throwing: error)
        }
    }
    return CommandOutcome(
        status: process.terminationStatus,
        output: String(decoding: try Data(contentsOf: outputFile), as: UTF8.self),
        errors: String(decoding: try Data(contentsOf: errorsFile), as: UTF8.self))
}

/// The folder `swift build` puts the products in: the one holding the
/// `.xctest` bundle this code is loaded from.
func buildProducts() throws -> URL {
    var info = Dl_info()
    try #require(dladdr(#dsohandle, &info) != 0, "the test bundle's path cannot be read")
    var url = URL(filePath: String(cString: info.dli_fname))
    while url.pathExtension != "xctest" {
        let parent = url.deletingLastPathComponent()
        try #require(parent != url, "the test code is not loaded from an .xctest bundle")
        url = parent
    }
    return url.deletingLastPathComponent()
}

/// This repository's root.
let repositoryRoot = URL(filePath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

/// A folder of its own for one test, removed by `remove()`.
struct ScratchFolder {
    let url: URL

    init(_ name: String) throws {
        url = FileManager.default.temporaryDirectory
            .appending(path: "\(name)-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    func remove() {
        try? FileManager.default.removeItem(at: url)
    }

    /// A stand-in for gpg, as git calls it: signing writes a fake signature to
    /// stdout and SIG_CREATED to the status fd; verifying prints the status
    /// lines to stdout and the human lines to stderr, which `log.showSignature`
    /// puts into the output of `git show`.
    func installFakeGPG() throws -> URL {
        let program = url.appending(path: "fake-gpg")
        let script = """
            #!/bin/sh
            for argument in "$@"; do
                if [ "$argument" = --verify ]; then
                    echo "[GNUPG:] GOODSIG ABCDEF0123456789 Test"
                    echo "[GNUPG:] VALIDSIG ABCDEF0123456789 2026-11-15 1 0 4 0 1 10 00 ABCDEF0123456789"
                    echo "gpg: Signature made Sun Nov 15 12:00:00 2026 UTC" >&2
                    echo 'gpg: Good signature from "Test"' >&2
                    exit 0
                fi
            done
            cat > /dev/null
            echo "[GNUPG:] SIG_CREATED D 1 10 00 1 ABCDEF0123456789" >&2
            printf -- '-----BEGIN PGP SIGNATURE-----\\n\\nZmFrZQ==\\n-----END PGP SIGNATURE-----\\n'
            """
        try script.write(to: program, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: program.path(percentEncoded: false))
        return program
    }
}

/// An Info.plist the scripts that read the bundle must refuse with a message.
enum InfoPlistDamage: CaseIterable, Sendable {
    case truncated
    case arrayAtTheRoot
    /// Python's plistlib fails on it with an AttributeError, not a ValueError.
    case malformedDate

    var message: String {
        switch self {
        case .truncated, .malformedDate: "cannot read the bundle's Info.plist"
        case .arrayAtTheRoot: "the bundle's Info.plist does not hold a dictionary"
        }
    }

    func write(to url: URL) throws {
        switch self {
        case .truncated:
            let whole = try PropertyListSerialization.data(
                fromPropertyList: ["MSRVersion": "0.20261115.2-dev+abcdef0"], format: .xml, options: 0)
            try whole.prefix(whole.count / 2).write(to: url)
        case .arrayAtTheRoot:
            try PropertyListSerialization.data(fromPropertyList: ["0.20261115.2-dev+abcdef0"], format: .xml, options: 0)
                .write(to: url)
        case .malformedDate:
            try Data("""
                <?xml version="1.0" encoding="UTF-8"?>
                <plist version="1.0"><dict><key>MSRVersion</key><string>0.20261115.2-dev+abcdef0</string>
                <key>built</key><date>not a date</date></dict></plist>
                """.utf8).write(to: url)
        }
    }
}
