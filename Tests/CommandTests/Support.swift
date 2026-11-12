import Foundation
import Testing

/// What a command did.
struct CommandOutcome {
    let status: Int32
    let output: String
    let errors: String
}

/// Runs a program with exactly the given environment, so nothing of the
/// ambient one leaks into what is tested; PATH is passed through.
func run(_ program: URL, _ arguments: [String] = [], environment: [String: String] = [:],
         in folder: URL? = nil) throws -> CommandOutcome {
    let process = Process()
    process.executableURL = program
    process.arguments = arguments
    process.environment = environment.merging(
        ["PATH": try #require(ProcessInfo.processInfo.environment["PATH"])]) { given, _ in given }
    if let folder { process.currentDirectoryURL = folder }
    let output = Pipe()
    let errors = Pipe()
    process.standardOutput = output
    process.standardError = errors
    try process.run()
    let outputData = output.fileHandleForReading.readDataToEndOfFile()
    let errorData = errors.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    return CommandOutcome(
        status: process.terminationStatus,
        output: String(decoding: outputData, as: UTF8.self),
        errors: String(decoding: errorData, as: UTF8.self))
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
                fromPropertyList: ["MSRVersion": "0.2.0-dev+abcdef0"], format: .xml, options: 0)
            try whole.prefix(whole.count / 2).write(to: url)
        case .arrayAtTheRoot:
            try PropertyListSerialization.data(fromPropertyList: ["0.2.0-dev+abcdef0"], format: .xml, options: 0)
                .write(to: url)
        }
    }
}
