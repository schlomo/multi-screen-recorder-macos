import Foundation
import RecorderLogic
import Testing
@testable import RecorderCore

private struct Reader: FileDurationReader {
    var result: Result<Double, NoUsableDuration>
    var read: Box?

    final class Box: @unchecked Sendable { var urls: [URL] = [] }

    func duration(of url: URL) async throws -> Double {
        read?.urls.append(url)
        switch result {
        case .success(let seconds): return seconds
        case .failure(let error): throw error
        }
    }
}

private let folder = URL(filePath: "/recording")

private func screenEnd(state: RecordingManifest.State) -> VideoFileEnd<RecordingManifest.ScreenFile> {
    var file = RecordingManifest.ScreenFile(
        name: "s.mov", screen: "LG", screenUUID: "U", frameSize: FrameSize(width: 2, height: 2), start: 1, timecode: "00:00:01:00")
    file.end = 6.933
    file.state = state
    return VideoFileEnd<RecordingManifest.ScreenFile>(file: file, error: VideoFileWriterError(description: "cannot write s.mov", isDiskFull: false))
}

private func audioEnd(state: RecordingManifest.State) -> AudioFileEnd {
    var file = RecordingManifest.AudioFile(
        name: "a.mov", audioSource: "Mic", audioSourceUID: "u", channels: .mono(1), start: 1, timecode: "00:00:01:00")
    file.end = 6.933
    file.state = state
    return AudioFileEnd(file: file, error: AudioFileWriterError(nil, while: "cannot write a.mov"))
}

@Suite struct FailedFileEndsTests {
    @Test func aFailedScreenFileEndsWhereItReallyEnds() async {
        let box = Reader.Box()
        let end = await screenEnd(state: .notFinalized)
            .readingItsFile(in: folder, with: Reader(result: .success(4.667), read: box))
        #expect(end.file.end == 5.667)
        #expect(end.failureSeconds == 6.933)
        #expect(end.lost?.contains("1.266 s of the recording are lost") == true)
        #expect(box.urls == [folder.appending(path: "s.mov")])
    }

    @Test func aFileThatIsFinalizedIsNotRead() async {
        let box = Reader.Box()
        let end = await screenEnd(state: .finalized).readingItsFile(in: folder, with: Reader(result: .success(0), read: box))
        #expect(end == screenEnd(state: .finalized))
        #expect(box.urls.isEmpty)
        let audio = await audioEnd(state: .finalized).readingItsFile(in: folder, with: Reader(result: .success(0), read: box))
        #expect(audio == audioEnd(state: .finalized))
        #expect(box.urls.isEmpty)
    }

    @Test func anUnreadableFailedFileEndsAtItsStart() async {
        let end = await screenEnd(state: .notFinalized)
            .readingItsFile(in: folder, with: Reader(result: .failure(NoUsableDuration(detail: "no moov"))))
        #expect(end.file.end == 1)
        #expect(end.lost?.contains("the file cannot be read (no moov)") == true)
        let audio = await audioEnd(state: .notFinalized).readingItsFile(in: folder, with: Reader(result: .failure(NoUsableDuration(detail: "no moov"))))
        #expect(audio.file.end == 1)
        #expect(audio.failureSeconds == 6.933)
    }

    @Test func aFailedAudioFileEndsWhereItReallyEnds() async {
        let end = await audioEnd(state: .notFinalized).readingItsFile(in: folder, with: Reader(result: .success(2)))
        #expect(end.file.end == 3)
        #expect(end.lost?.contains("3.933 s of the recording are lost") == true)
    }

    @Test func theEventAndProblemStayAtTheFailureAndAProblemTellsWhatIsLost() async {
        let end = await screenEnd(state: .notFinalized).readingItsFile(in: folder, with: Reader(result: .success(4.667)))
        let report = FileEndReport(reason: nil, end: end, source: "LG", at: 9_000_000_000)
        #expect(report.event?.at == 6.933)
        #expect(report.problem?.at == 6.933)
        #expect(report.lostProblem?.problem == "Screen file s.mov")
        #expect(report.lostProblem?.error?.contains("1.266 s of the recording are lost") == true)
        #expect(report.lostKind == .videoFileLost("s.mov"))
        var manifest = RecordingManifest(
            app: "x", started: Date(), timeZone: .gmt, settings: .defaults)
        var reports = CaptureEndReports()
        _ = reports.record(captureNumber: 1, reason: nil, end: end, source: "LG", at: 9_000_000_000, into: &manifest)
        #expect(manifest.files.first?.end == 5.667)
        #expect(manifest.problems.count == 2)
    }

    @Test func aRealFileOfTheWrongKindIsUnreadable() async throws {
        let file = FileManager.default.temporaryDirectory.appending(path: "msr-failed-file-\(UUID().uuidString).mov")
        try Data("not a movie".utf8).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        await #expect(throws: (any Error).self) { try await AssetDurationReader().duration(of: file) }
    }
}
