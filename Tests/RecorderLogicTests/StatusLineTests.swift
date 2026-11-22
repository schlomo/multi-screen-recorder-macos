import Testing
@testable import RecorderLogic

/// The status line `msr record` redraws on a terminal.
@Suite struct StatusLineTests {
    private func row(_ source: SourceCell, state: String = "recording") -> RecordingStatusTable.Row {
        .init(source: source, recordsAt: "", files: 1, written: "1 MB", state: state)
    }

    private func status(problems: Int, isLowOnDisk: Bool = false) -> RecordingStatus {
        var status = RecordingStatus()
        status.problems = Array(repeating: "problem", count: problems)
        status.isLowOnDisk = isLowOnDisk
        return status
    }

    /// The count is the problems', as the glossary defines them; low disk space is not one.
    @Test func theCountIsTheProblemsEvenWhileLowDiskSpaceIsSet() {
        #expect(StatusLine.text(line: line, cpu: nil, rows: [], status: status(problems: 1, isLowOnDisk: true)).hasPrefix("1 problem · Recording"))
        #expect(StatusLine.text(line: line, cpu: nil, rows: [], status: status(problems: 0, isLowOnDisk: true)).hasPrefix("Recording"))
    }

    private let line = "Recording 0:12:34 · 1.2 GB in 7 files · 143.8 GB free"

    @Test func problemsComeFirstThenTheLineThenCPUThenSources() {
        let rows = [row(.screen(1, name: "A")), row(.screen(2, name: "B")), row(.systemAudio(isRecorded: true)), row(.audioInput(1, name: "Mic"))]
        #expect(StatusLine.text(line: line, cpu: "CPU 23 %", rows: rows, status: status(problems: 2))
            == "2 problems · \(line) · CPU 23 % · 2 screens, 2 audio")
        #expect(StatusLine.text(line: line, cpu: "CPU 23 %", rows: rows, status: status(problems: 1)).hasPrefix("1 problem · Recording"))
    }

    @Test func camerasBeingRecordedAreCountedOnlyWhenThereAreAny() {
        let rows = [row(.screen(1, name: "A")), row(.camera(1, name: "FaceTime")), row(.camera(2, name: "BRIO")),
                    row(.audioInput(1, name: "Mic"))]
        #expect(StatusLine.text(line: line, cpu: nil, rows: rows, status: status(problems: 0)).hasSuffix(" · 1 screen, 2 cameras, 1 audio"))
    }

    @Test func noProblemsSaysNothingAboutProblems() {
        #expect(StatusLine.text(line: line, cpu: nil, rows: [row(.screen(1, name: "A"))], status: status(problems: 0))
            == "\(line) · 1 screen, 0 audio")
    }

    @Test func onlySourcesBeingRecordedAreCounted() {
        let rows = [row(.screen(1, name: "A")), row(.screen(2, name: "B"), state: "disconnected"),
                    row(.audioInput(1, name: "Mic"), state: "waiting"), row(.audioInput(2, name: "Mic 2"))]
        #expect(StatusLine.text(line: line, cpu: nil, rows: rows, status: status(problems: 0)).hasSuffix(" · 1 screen, 1 audio"))
    }

    @Test func theLineIsCutToTheWidthMinusOneSoItNeverWraps() {
        #expect(StatusLine.fit("Recording 0:01:07", width: 10) == "Recording")
        #expect(StatusLine.fit("Recording", width: 10) == "Recording")
        #expect(StatusLine.fit("Rec", width: 10) == "Rec")
        #expect(StatusLine.fit("Recording", width: 1) == "")
    }

    @Test func anUnknownWidthIsTakenAs80Columns() {
        let long = String(repeating: "x", count: 200)
        #expect(StatusLine.fit(long, width: nil).count == 79)
        #expect(StatusLine.fit(long, width: 0).count == 79)
    }
}

@Suite struct RecordingStatusBadgeTests {
    @Test func lowDiskSpaceAScreenShowingAnotherPictureAndProblemsEachSetTheBadge() {
        #expect(RecordingStatus().badge == nil)
        var status = RecordingStatus()
        status.isLowOnDisk = true
        #expect(status.badge == "!")
        status = RecordingStatus()
        status.screenShowingAnotherScreensPicture = "Screen 2"
        #expect(status.badge == "!")
        status = RecordingStatus()
        status.problems = ["a"]
        #expect(status.badge == "!")
    }
}
