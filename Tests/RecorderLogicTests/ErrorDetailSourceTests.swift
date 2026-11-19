import Foundation
import Testing

/// Every error turned into text goes through the error detail, which keeps
/// its domain, code and underlying errors (D64): only its own file reads
/// `localizedDescription`, which says none of them.
@Suite struct ErrorDetailSourceTests {
    @Test func noSourceFileButTheErrorDetailReadsTheLocalizedDescription() throws {
        let sources = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "Sources")
        let files = try #require(FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil))
            .compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }
        #expect(files.count > 10)
        let reading = try files.filter { file in
            try String(contentsOf: file, encoding: .utf8).contains("localizedDescription")
        }.map(\.lastPathComponent)
        #expect(reading == ["ErrorDetail.swift"])
    }
}
