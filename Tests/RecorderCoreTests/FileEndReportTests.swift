import RecorderLogic
import Testing
@testable import RecorderCore

private let second: Int64 = 1_000_000_000

private func fileEnd(_ error: ScreenFileWriterError?, endsAt: Double = 12.5) -> ScreenFileEnd {
    var file = RecordingManifest.ScreenFile(
        name: "f.mov", screen: "LG", screenUUID: "U", frameSize: FrameSize(width: 2, height: 2), start: 0,
        timecode: "00:00:00:00")
    file.end = endsAt
    return ScreenFileEnd(file: file, error: error)
}

private func writerError(_ text: String) -> ScreenFileWriterError { ScreenFileWriterError(description: text, isDiskFull: false) }
private let fullDisk = ScreenFileWriterError(description: "cannot write f.mov: full", isDiskFull: true)

private func failedEvent(at seconds: Double, error: String) -> RecordingEvent {
    var event = RecordingEvent(at: Int64(seconds * 1_000_000_000), event: .screenFileWriterFailed, screen: "LG")
    event.error = error
    return event
}

/// What the manifest and the person are told when a screen file, or a
/// capture without one, ends.
@Suite struct FileEndReportTests {
    @Test func guideTracksCutAtTheEndAreAProblemWithoutAnEvent() {
        var end = fileEnd(nil)
        end.guideTracksCut = [GuideTrackCut(guide: .microphones, why: .samplesGone), GuideTrackCut(guide: .systemAudio, why: .writerTimedOut)]
        let report = FileEndReport(reason: nil, end: end, screen: "LG", at: 3 * second)
        #expect(report.event == nil)
        #expect(report.problem == RecordingProblem(
            at: 12_500_000_000, problem: "Screen file f.mov",
            error: "the guide track \"Microphones\" ends before the video: the samples of its last mix were no longer there; "
                + "the guide track \"System audio\" ends before the video: the writer did not take its last samples in time"))
        // A writer's error says more and wins.
        var failed = fileEnd(writerError("cannot write f.mov: no luck"))
        failed.guideTracksCut = [GuideTrackCut(guide: .microphones, why: .samplesGone)]
        #expect(FileEndReport(reason: nil, end: failed, screen: "LG", at: 3 * second).problem?.error == "cannot write f.mov: no luck")
    }

    @Test func aWriterThatCouldNotBeCreatedIsAnEventNowAndAProblem() {
        let report = FileEndReport(reason: .writerFailed("cannot create f.mov"), end: nil, screen: "LG", at: 3 * second)
        #expect(report.problem == RecordingProblem(at: 3 * second, problem: "Screen LG", error: "cannot create f.mov"))
        #expect(report.event == failedEvent(at: 3, error: "cannot create f.mov"))
    }

    @Test func aFullDiskIsAnEventAndAProblemFileOrNoFile() {
        let noFile = FileEndReport(reason: .diskFull, end: nil, screen: "LG", at: 3 * second)
        #expect(noFile.problem == RecordingProblem(at: 3 * second, problem: "Screen LG", error: "the disk is full"))
        #expect(noFile.event == RecordingEvent(at: 3 * second, event: .diskFull, screen: "LG"))
        let withFile = FileEndReport(reason: .diskFull, end: fileEnd(fullDisk), screen: "LG", at: 13 * second)
        #expect(withFile.problem?.text == "Screen file f.mov: cannot write f.mov: full")
        #expect(withFile.event == RecordingEvent(at: 12_500_000_000, event: .diskFull, screen: "LG"))
    }

    /// The stop path has no reason; the file's own error says the disk is full.
    @Test func aFullDiskReportedByTheStopIsAFullDisk() {
        let report = FileEndReport(reason: nil, end: fileEnd(fullDisk), screen: "LG", at: 13 * second)
        #expect(report.event == RecordingEvent(at: 12_500_000_000, event: .diskFull, screen: "LG"))
    }

    @Test func anErrorAtTheEndOfAFileIsAnEventAtTheFilesEnd() {
        let report = FileEndReport(reason: nil, end: fileEnd(writerError("cannot finalize f.mov")), screen: "LG", at: 13 * second)
        #expect(report.problem == RecordingProblem(at: 12_500_000_000, problem: "Screen file f.mov", error: "cannot finalize f.mov"))
        #expect(report.event == failedEvent(at: 12.5, error: "cannot finalize f.mov"))
    }

    @Test func aWriterFailureWithAFileIsOneEventWithTheFilesError() {
        let report = FileEndReport(reason: .writerFailed("x"), end: fileEnd(writerError("cannot write f.mov")), screen: "LG", at: 13 * second)
        #expect(report.event == failedEvent(at: 12.5, error: "cannot write f.mov"))
        #expect(report.problem?.text == "Screen file f.mov: cannot write f.mov")
    }

    @Test func aCleanEndIsNothingToTell() {
        let report = FileEndReport(reason: .streamFailed("-3811"), end: fileEnd(nil), screen: "LG", at: 13 * second)
        #expect(report.event == nil)
        #expect(report.problem == nil)
    }
}

/// A capture's end comes on two paths: the reason path (the capture
/// ended by itself, `reason` set) and the stop path (the recorder stopped
/// it, `reason` nil). Each end is one event and one problem in the
/// manifest, whichever path comes first and whether or not the tracker
/// still runs; the recorder tells the person the problem returned.
@Suite struct CaptureEndReportsTests {
    private let failed = ScreenTracker.StreamEnd.writerFailed("cannot write f.mov")

    private func manifest() -> RecordingManifest {
        RecordingManifest(app: "x", started: .now, timeZone: .current, settings: .defaults)
    }

    @Test func theReasonPathFirstThenTheStopPathIsOneEventAndOneProblem() {
        var reports = CaptureEndReports()
        var manifest = manifest()
        let told = [
            reports.record(captureNumber: 1, reason: failed, end: fileEnd(writerError("cannot write f.mov")), screen: "LG", at: 5 * second, into: &manifest),
            reports.record(captureNumber: 1, reason: nil, end: fileEnd(writerError("cannot write f.mov")), screen: "LG", at: 6 * second, into: &manifest),
        ].compactMap(\.self)
        #expect(manifest.events == [failedEvent(at: 12.5, error: "cannot write f.mov")])
        #expect(manifest.problems.count == 1)
        #expect(told == manifest.problems)
        #expect(manifest.files.map(\.name) == ["f.mov"])
    }

    @Test func theStopPathFirstThenTheReasonPathIsOneEventAndOneProblem() {
        var reports = CaptureEndReports()
        var manifest = manifest()
        let told = [
            reports.record(captureNumber: 1, reason: nil, end: fileEnd(fullDisk), screen: "LG", at: 5 * second, into: &manifest),
            reports.record(captureNumber: 1, reason: .diskFull, end: nil, screen: "LG", at: 6 * second, into: &manifest),
        ].compactMap(\.self)
        #expect(manifest.events.map(\.event) == [.diskFull])
        #expect(manifest.problems.count == 1)
        #expect(told == manifest.problems)
    }

    @Test func aStaleCaptureIsOneEventAndOneProblemWithoutTheTracker() {
        // The recorder skips the tracker for a capture that is no longer
        // current; the reason path alone tells it.
        var reports = CaptureEndReports()
        var manifest = manifest()
        let told = reports.record(captureNumber: 1, reason: .diskFull, end: nil, screen: "LG", at: 5 * second, into: &manifest)
        #expect(manifest.events == [RecordingEvent(at: 5 * second, event: .diskFull, screen: "LG")])
        #expect(manifest.problems == [RecordingProblem(at: 5 * second, problem: "Screen LG", error: "the disk is full")])
        #expect(told == manifest.problems.first)
    }

    @Test func aStopWithNothingToTellLeavesTheTellingToTheReasonPath() {
        var reports = CaptureEndReports()
        var manifest = manifest()
        #expect(reports.record(captureNumber: 1, reason: nil, end: nil, screen: "LG", at: 5 * second, into: &manifest) == nil)
        for (capture, time) in [(1, 6), (1, 7), (2, 8)] {
            _ = reports.record(captureNumber: capture, reason: failed, end: nil, screen: "LG", at: Int64(time) * second, into: &manifest)
        }
        #expect(manifest.events.count == 2)
        #expect(manifest.problems.count == 2)
    }

    @Test func aFileEndUpdatesItsEntry() {
        var reports = CaptureEndReports()
        var manifest = manifest()
        var started = fileEnd(nil).file
        started.end = nil
        manifest.files = [started]
        _ = reports.record(captureNumber: 1, reason: nil, end: fileEnd(nil), screen: "LG", at: 13 * second, into: &manifest)
        #expect(manifest.files.map(\.end) == [12.5])
        #expect(manifest.events.isEmpty && manifest.problems.isEmpty)
    }
}
