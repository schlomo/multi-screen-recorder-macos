import Foundation
import RecorderLogic
import Testing
@testable import RecorderCore

/// Crash markers in a scratch home folder.
@Suite struct CrashMarkersTests {
    private let home: URL

    init() {
        home = FileManager.default.temporaryDirectory.appending(path: "CrashMarkers-\(UUID().uuidString)", directoryHint: .isDirectory)
    }

    private func recording(_ name: String) throws -> URL {
        let folder = home.appending(path: "Movies/\(name)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var manifest = RecordingManifest(app: "test", started: Date(), timeZone: .current, settings: .defaults)
        manifest.files.append(.init(name: "a.mov", display: "A", displayUUID: "U", frameSize: FrameSize(width: 2, height: 2),
                                    start: 0, timecode: "00:00:00:00"))
        try manifest.jsonData().write(to: folder.appending(path: RecordingNames.manifest))
        return folder
    }

    @Test func aMarkerOfAGoneProcessIsReportedItsManifestMarkedAndItIsRemoved() throws {
        defer { try? FileManager.default.removeItem(at: home) }
        let markers = CrashMarkers(homeFolder: home)
        let gone = try recording("gone")
        let running = try recording("running")
        try markers.write(recordingFolder: gone, processID: 100)
        try markers.write(recordingFolder: running, processID: 200)

        let lines = markers.finishLeftBehind { $0 == 200 }
        #expect(lines == [CrashMarker(recordingFolder: gone.path(percentEncoded: false)).report])
        let manifest = try RecordingManifest(json: Data(contentsOf: gone.appending(path: RecordingNames.manifest)))
        #expect(manifest.state == .notFinalized)
        #expect(manifest.files.map(\.state) == [.notFinalized])
        #expect(!FileManager.default.fileExists(atPath: markers.url(processID: 100).path(percentEncoded: false)))
        #expect(FileManager.default.fileExists(atPath: markers.url(processID: 200).path(percentEncoded: false)))
        let untouched = try RecordingManifest(json: Data(contentsOf: running.appending(path: RecordingNames.manifest)))
        #expect(untouched.state == .recording)
    }

    @Test func noMarkerFolderIsNoMarkers() {
        #expect(CrashMarkers(homeFolder: home).finishLeftBehind().isEmpty)
    }

    @Test func aMarkerThatCannotBeReadIsNamedAndLeft() throws {
        defer { try? FileManager.default.removeItem(at: home) }
        let markers = CrashMarkers(homeFolder: home)
        try FileManager.default.createDirectory(at: markers.folder, withIntermediateDirectories: true)
        try Data("garbage".utf8).write(to: markers.url(processID: 300))
        let lines = markers.finishLeftBehind { _ in false }
        #expect(lines.count == 1)
        #expect(lines.first?.hasPrefix("Crash marker ") == true)
        #expect(FileManager.default.fileExists(atPath: markers.url(processID: 300).path(percentEncoded: false)))
    }

    @Test func thisProcessIsRunning() {
        #expect(processIsRunning(getpid()))
    }
}
