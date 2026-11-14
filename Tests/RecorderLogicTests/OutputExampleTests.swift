import Foundation
import Testing

/// The folder listing and the recording manifest in docs/design/recorder.md
/// describe the same recording.
@Suite struct OutputExampleTests {
    private func design() throws -> String {
        try repositoryFile("docs/design/recorder.md")
    }

    /// The code block after `marker`, without its fences.
    private func block(after marker: String, in text: String) throws -> String {
        let start = try #require(text.range(of: marker)).upperBound
        let rest = text[start...]
        let body = try #require(rest.range(of: "\n")).upperBound
        let end = try #require(rest[body...].range(of: "```")).lowerBound
        return String(rest[body..<end])
    }

    private func listedFiles() throws -> [String] {
        try block(after: "```\n~/Movies/Multi Screen Recorder/2026-11-12 14.03.05/", in: design())
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .compactMap { line in line.split(separator: "    ←").first.map { $0.trimmingCharacters(in: .whitespaces) } }
            .filter { $0.hasSuffix(".mov") }
    }

    private func manifest() throws -> [String: Any] {
        let text = try design()
        let start = try #require(text.range(of: "```json\n{\n  \"app\"")).lowerBound
        let json = try block(after: "```json", in: String(text[start...]))
        let data = Data(json.utf8)
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    @Test func theFolderListingAndTheManifestNameTheSameFiles() throws {
        let files = try #require(try manifest()["files"] as? [[String: Any]])
        let names = files.compactMap { $0["name"] as? String }
        #expect(names.count == files.count)
        #expect(try listedFiles().sorted() == names.sorted())
        #expect(try listedFiles().count == 6)
    }

    @Test func aFrameSizeChangeEndsOneFileAndStartsTheNext() throws {
        let manifest = try manifest()
        let files = try #require(manifest["files"] as? [[String: Any]])
        let events = try #require(manifest["events"] as? [[String: Any]])
        for event in events where event["event"] as? String == "display frame size changed" {
            let display = try #require(event["display"] as? String)
            let at = try #require(event["at"] as? Double)
            let ofDisplay = files.filter { $0["display"] as? String == display }
            #expect(ofDisplay.contains { $0["end"] as? Double == at && $0["frameSize"] as? [Int] == event["from"] as? [Int] })
            #expect(ofDisplay.contains { $0["start"] as? Double == at && $0["frameSize"] as? [Int] == event["to"] as? [Int] })
        }
    }
}
