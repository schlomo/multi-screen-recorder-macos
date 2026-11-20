import Foundation
import Testing

/// Everything the app writes on standard error passes the one writer, so a
/// line never lands in the middle of the app's status line. Every target
/// under `Sources/` is scanned, a new one too, except the end-to-end tests'
/// targets: the driver is a program of its own, with no status line.
@Suite struct StandardErrorSourceTests {
    static let sources = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().appending(path: "Sources")
    static let endToEndTargets = ["msr-end-to-end", "EndToEndLogic", "VirtualScreen"]

    @Test func everyExemptedTargetExists() {
        for target in Self.endToEndTargets {
            var isDirectory: ObjCBool = false
            #expect(FileManager.default.fileExists(atPath: Self.sources.appending(path: target).path, isDirectory: &isDirectory)
                && isDirectory.boolValue, "\(target) is exempted but not a target under Sources/")
        }
    }

    @Test func noSourceFileWritesToStandardErrorButTheWriter() throws {
        let exempted = Self.endToEndTargets.map { Self.sources.appending(path: $0).standardizedFileURL.path + "/" }
        let files = try #require(FileManager.default.enumerator(at: Self.sources, includingPropertiesForKeys: nil))
            .compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }
            .filter { file in !exempted.contains { file.standardizedFileURL.path.hasPrefix($0) } }
        #expect(files.count > 10)
        let writing = try files.filter { file in
            let text = try String(contentsOf: file, encoding: .utf8)
            return ["FileHandle.standardError", "stderr", "STDERR_FILENO"].contains { text.contains($0) }
        }.map(\.lastPathComponent)
        #expect(writing == ["StandardErrorWriter.swift"])
    }
}
