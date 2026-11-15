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

    @Test func aWriterThatCouldNotBeCreatedIsAProblemWithoutAFile() {
        let report = FileEndReport(reason: .writerFailed("cannot create f.mov"), end: nil, display: "LG")
        #expect(report.problem == "Display LG: cannot create f.mov")
        // The tracker writes the event for this reason.
        #expect(report.event == nil)
    }

    @Test func aFullDiskIsAProblemFileOrNoFile() {
        #expect(FileEndReport(reason: .diskFull, end: nil, display: "LG").problem == "Display LG: the disk is full")
        #expect(FileEndReport(reason: .diskFull, end: end(error: "cannot write f.mov: full"), display: "LG").problem
            == "Display file f.mov: cannot write f.mov: full")
    }

    @Test func anErrorAtTheEndOfAFileIsAnEventAtTheFilesEnd() {
        let report = FileEndReport(reason: nil, end: end(error: "cannot finalize f.mov"), display: "LG")
        #expect(report.problem == "Display file f.mov: cannot finalize f.mov")
        #expect(report.event?.event == .displayFileWriterFailed)
        #expect(report.event?.at == 12.5)
        #expect(report.event?.error == "cannot finalize f.mov")
        #expect(report.event?.display == "LG")
    }

    @Test func aWriterErrorOfTheReasonHasItsEventAlready() {
        let report = FileEndReport(reason: .writerFailed("x"), end: end(error: "x"), display: "LG")
        #expect(report.event == nil)
        #expect(report.problem == "Display file f.mov: x")
    }

    @Test func aCleanEndIsNothingToTell() {
        let report = FileEndReport(reason: .streamFailed("-3815"), end: end(error: nil), display: "LG")
        #expect(report.event == nil)
        #expect(report.problem == nil)
    }
}

@Suite struct CaptureEndReportsTests {
    @Test func aCaptureEndingByItselfWhileStoppedIsToldOnce() {
        var reports = CaptureEndReports()
        let failed = DisplayTracker.StreamEnd.writerFailed("cannot create f.mov")
        // The stop path: no file, no reason, nothing to tell; it does not use up the capture's one telling.
        #expect(reports.report(captureNumber: 1, reason: nil, end: nil, display: "LG") == nil)
        #expect(reports.report(captureNumber: 1, reason: failed, end: nil, display: "LG")?.problem
            == "Display LG: cannot create f.mov")
        #expect(reports.report(captureNumber: 1, reason: failed, end: nil, display: "LG") == nil)
        #expect(reports.report(captureNumber: 2, reason: failed, end: nil, display: "LG") != nil)
    }
}
