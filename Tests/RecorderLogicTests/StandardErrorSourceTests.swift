import Foundation
import Testing

/// Everything on standard error passes the one writer, so a line never lands in the middle of the status line.
@Suite struct StandardErrorSourceTests {
    @Test func noSourceFileWritesToStandardErrorButTheWriter() throws {
        let sources = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "Sources")
        let files = try #require(FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil))
            .compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }
        #expect(files.count > 10)
        let writing = try files.filter { file in
            let text = try String(contentsOf: file, encoding: .utf8)
            return ["FileHandle.standardError", "stderr", "STDERR_FILENO"].contains { text.contains($0) }
        }.map(\.lastPathComponent)
        #expect(writing == ["StandardErrorWriter.swift"])
    }
}
