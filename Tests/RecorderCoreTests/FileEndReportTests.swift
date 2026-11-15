import RecorderLogic
import Testing
@testable import RecorderCore

/// What the manifest and the person are told when a display file, or a
/// capture without one, ends.
@Suite struct FileEndReportTests {
    private func end(error: String?, endsAt: Double = 12.5) -> DisplayFileEnd {
        var file = RecordingManifest.DisplayFile(
            name: "f.mov", display: "LG", displayUUID: "U", frameSize: FrameSize(width: 2, height: 2), start: 0,
            timecode: "00:00:00:00")
        file.end = endsAt
        return DisplayFileEnd(file: file, error: error)
    }

    private let second: Int64 = 1_000_000_000

    @Test func aWriterThatCouldNotBeCreatedIsAnEventNowAndAProblem() {
        let report = FileEndReport(reason: .writerFailed("cannot create f.mov"), end: nil, display: "LG", at: 3 * second)
        #expect(report.problem == "Display LG: cannot create f.mov")
        #expect(report.event == RecordingEvent.failed(at: 3, error: "cannot create f.mov"))
    }

    @Test func aFullDiskIsAnEventAndAProblemFileOrNoFile() {
        let noFile = FileEndReport(reason: .diskFull, end: nil, display: "LG", at: 3 * second)
        #expect(noFile.problem == "Display LG: the disk is full")
        #expect(noFile.event == RecordingEvent(at: 3 * second, event: .diskFull, display: "LG"))
        let withFile = FileEndReport(reason: .diskFull, end: end(error: "cannot write f.mov: full"), display: "LG", at: 13 * second)
        #expect(withFile.problem == "Display file f.mov: cannot write f.mov: full")
        #expect(withFile.event == RecordingEvent(at: 12_500_000_000, event: .diskFull, display: "LG"))
    }

    @Test func anErrorAtTheEndOfAFileIsAnEventAtTheFilesEnd() {
        let report = FileEndReport(reason: nil, end: end(error: "cannot finalize f.mov"), display: "LG", at: 13 * second)
        #expect(report.problem == "Display file f.mov: cannot finalize f.mov")
        #expect(report.event == RecordingEvent.failed(at: 12.5, error: "cannot finalize f.mov"))
    }

    @Test func aWriterFailureWithAFileIsOneEventWithTheFilesError() {
        let report = FileEndReport(reason: .writerFailed("x"), end: end(error: "cannot write f.mov"), display: "LG", at: 13 * second)
        #expect(report.event == RecordingEvent.failed(at: 12.5, error: "cannot write f.mov"))
        #expect(report.problem == "Display file f.mov: cannot write f.mov")
    }

    @Test func aCleanEndIsNothingToTell() {
        let report = FileEndReport(reason: .streamFailed("-3815"), end: end(error: nil), display: "LG", at: 13 * second)
        #expect(report.event == nil)
        #expect(report.problem == nil)
    }
}

extension RecordingEvent {
    static func failed(at seconds: Double, error: String) -> RecordingEvent {
        var event = RecordingEvent(at: Int64(seconds * 1_000_000_000), event: .displayFileWriterFailed, display: "LG")
        event.error = error
        return event
    }
}

/// A capture's end comes on two paths: the reason path (the capture
/// ended by itself, `reason` set) and the stop path (the recorder stopped
/// it, `reason` nil). Each end is one event and one problem, whichever
/// path comes first and whether or not the tracker still runs.
@Suite struct CaptureEndReportsTests {
    private let second: Int64 = 1_000_000_000
    private let failed = DisplayTracker.StreamEnd.writerFailed("cannot write f.mov")

    private func fileEnd() -> DisplayFileEnd {
        var file = RecordingManifest.DisplayFile(
            name: "f.mov", display: "LG", displayUUID: "U", frameSize: FrameSize(width: 2, height: 2), start: 0,
            timecode: "00:00:00:00")
        file.end = 4
        return DisplayFileEnd(file: file, error: "cannot write f.mov")
    }

    private func told(_ reports: [FileEndReport?]) -> (events: [RecordingEvent], problems: [String]) {
        (reports.compactMap { $0?.event }, reports.compactMap { $0?.problem })
    }

    @Test func theReasonPathFirstThenTheStopPathIsOneEventAndOneProblem() {
        var reports = CaptureEndReports()
        let told = told([
            reports.report(captureNumber: 1, reason: failed, end: fileEnd(), display: "LG", at: 5 * second),
            reports.report(captureNumber: 1, reason: nil, end: fileEnd(), display: "LG", at: 6 * second),
        ])
        #expect(told.events.map(\.event) == [.displayFileWriterFailed])
        #expect(told.problems.count == 1)
    }

    @Test func theStopPathFirstThenTheReasonPathIsOneEventAndOneProblem() {
        var reports = CaptureEndReports()
        let told = told([
            reports.report(captureNumber: 1, reason: nil, end: fileEnd(), display: "LG", at: 5 * second),
            reports.report(captureNumber: 1, reason: failed, end: nil, display: "LG", at: 6 * second),
        ])
        #expect(told.events.map(\.event) == [.displayFileWriterFailed])
        #expect(told.problems.count == 1)
    }

    @Test func aStaleCaptureIsOneEventAndOneProblemWithoutTheTracker() {
        // The recorder skips the tracker for a capture that is no longer
        // current; the reason path alone tells it.
        var reports = CaptureEndReports()
        let told = told([reports.report(captureNumber: 1, reason: .diskFull, end: nil, display: "LG", at: 5 * second)])
        #expect(told.events == [RecordingEvent(at: 5 * second, event: .diskFull, display: "LG")])
        #expect(told.problems == ["Display LG: the disk is full"])
    }

    @Test func aStopWithNothingToTellLeavesTheTellingToTheReasonPath() {
        var reports = CaptureEndReports()
        #expect(reports.report(captureNumber: 1, reason: nil, end: nil, display: "LG", at: 5 * second) == nil)
        let told = told([
            reports.report(captureNumber: 1, reason: failed, end: nil, display: "LG", at: 6 * second),
            reports.report(captureNumber: 1, reason: failed, end: nil, display: "LG", at: 7 * second),
            reports.report(captureNumber: 2, reason: failed, end: nil, display: "LG", at: 8 * second),
        ])
        #expect(told.events.count == 2)
        #expect(told.problems.count == 2)
    }
}
