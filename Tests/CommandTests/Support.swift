import Foundation
import Testing

/// What a command did.
struct CommandOutcome {
    let status: Int32
    let output: String
    let errors: String
}

/// Runs a program with exactly the given environment, so nothing of the
/// ambient one leaks into what is tested; PATH is passed through. Output and
/// errors go to files, so a child filling either cannot block on a full pipe.
func run(_ program: URL, _ arguments: [String] = [], environment: [String: String] = [:],
         in folder: URL? = nil) throws -> CommandOutcome {
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
    try process.run()
    process.waitUntilExit()
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
}

/// An Info.plist the scripts that read the bundle must refuse with a message.
enum InfoPlistDamage: CaseIterable, Sendable {
    case truncated
    case arrayAtTheRoot

    var message: String {
        switch self {
        case .truncated: "cannot read the bundle's Info.plist"
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
        }
    }
}
