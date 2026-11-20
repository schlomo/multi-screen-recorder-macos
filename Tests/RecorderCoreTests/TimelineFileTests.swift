import Foundation
import RecorderLogic
import Testing
@testable import RecorderCore

private struct Reader: FileDurationReader {
    var seconds: Double?

    func duration(of url: URL) async throws -> Double {
        guard let seconds else { throw NoUsableDuration(detail: "no duration") }
        return seconds
    }
}

@Suite struct TimelineFileTests {
    private let folder: URL

    init() throws {
        folder = FileManager.default.temporaryDirectory
            .appending(path: "timeline-\(UUID().uuidString)", directoryHint: .isDirectory)
            .appending(path: "2026-11-20 10.00.00", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    private func writeManifest(ended: Double?) throws {
        let end = ended.map { String($0) } ?? "null"
        let json = """
            {"app": "test", "state": "finalized", "started": "2026-11-20T10:00:00.000+01:00", "ended": null,
             "settings": {"audioMode": "wired", "resolution": "native", "systemAudio": true},
             "files": [{"name": "2026-11-20 10.00.00 Audio 1 - Mic.mov", "audioSource": "Mic", "channels": 1, "start": 0,
                        "end": \(end), "timecode": "10:00:00:00", "state": "finalized"}],
             "events": [], "problems": []}
            """
        try Data(json.utf8).write(to: folder.appending(path: RecordingNames.manifest))
    }

    private var contents: [String] { (try? FileManager.default.contentsOfDirectory(atPath: folder.path(percentEncoded: false)).sorted()) ?? [] }

    private func length(of file: URL) throws -> Double {
        let json = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
        let stack = try #require(json["tracks"] as? [String: Any])
        let track = try #require((stack["children"] as? [[String: Any]])?.first)
        let clip = try #require((track["children"] as? [[String: Any]])?.first)
        let range = try #require(clip["source_range"] as? [String: Any])
        return try #require((range["duration"] as? [String: Any])?["value"] as? Double)
    }

    @Test func itWritesTheTimelineFileWholeNextToTheManifestAndReplacesAnOlderOne() async throws {
        defer { try? FileManager.default.removeItem(at: folder.deletingLastPathComponent()) }
        try writeManifest(ended: 10)
        let file = folder.appending(path: "2026-11-20 10-00-00.otio")
        try Data("old".utf8).write(to: file)
        let written = try await TimelineFile.write(in: folder, reader: Reader(seconds: nil))
        #expect(written.lastPathComponent == "2026-11-20 10-00-00.otio")
        #expect(contents == ["2026-11-20 10-00-00.otio", "recording.json"])
        #expect(try length(of: file) == 300)
    }

    @Test func aFileWithoutAnEndIsMeasuredByTheMedia() async throws {
        defer { try? FileManager.default.removeItem(at: folder.deletingLastPathComponent()) }
        try writeManifest(ended: nil)
        let file = try await TimelineFile.write(in: folder, reader: Reader(seconds: 2.0999))
        #expect(try length(of: file) == 62)
    }

    @Test func aMediaFileWhoseLengthCannotBeReadWritesNothing() async throws {
        defer { try? FileManager.default.removeItem(at: folder.deletingLastPathComponent()) }
        try writeManifest(ended: nil)
        await #expect(throws: TimelineFile.Failure.self) { try await TimelineFile.write(in: folder, reader: Reader(seconds: nil)) }
        #expect(contents == ["recording.json"])
    }

    @Test func aMissingManifestWritesNothing() async throws {
        defer { try? FileManager.default.removeItem(at: folder.deletingLastPathComponent()) }
        await #expect(throws: TimelineFile.Failure.self) { try await TimelineFile.write(in: folder, reader: Reader(seconds: 1)) }
        #expect(contents.isEmpty)
    }
}
