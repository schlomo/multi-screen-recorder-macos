import Testing
@testable import RecorderLogic

/// The status line `msr record` redraws on a terminal.
@Suite struct StatusLineTests {
    private func row(_ source: SourceCell, state: String = "recording") -> RecordingStatusTable.Row {
        .init(source: source, recordsAt: "", files: 1, written: "1 MB", state: state)
    }

    private let line = "Recording 0:01:07 · 1.3 GB in 3 files · 120.4 GB free"

    @Test func theLineThenCPUThenSourcesThenProblemsJoinedByCommas() {
        let rows = [row(.screen(1, name: "A")), row(.screen(2, name: "B")), row(.systemAudio(isRecorded: true)), row(.audioInput(1, name: "Mic"))]
        #expect(StatusLine.text(line: line, cpu: "CPU 23 %", rows: rows, problems: 2)
            == "\(line), CPU 23 %, 2 screens, 2 audio sources, 2 problems")
    }

    @Test func withoutCPUTheLineLeavesItOut() {
        #expect(StatusLine.text(line: line, cpu: nil, rows: [row(.screen(1, name: "A"))], problems: 0)
            == "\(line), 1 screen, 0 audio sources, no problems")
    }

    @Test func oneProblemIsSingular() {
        #expect(StatusLine.text(line: line, cpu: nil, rows: [], problems: 1).hasSuffix(", 1 problem"))
    }

    @Test func onlySourcesBeingRecordedAreCounted() {
        let rows = [row(.screen(1, name: "A")), row(.screen(2, name: "B"), state: "disconnected"),
                    row(.audioInput(1, name: "Mic"), state: "waiting"), row(.audioInput(2, name: "Mic 2"))]
        #expect(StatusLine.text(line: line, cpu: nil, rows: rows, problems: 0).contains(", 1 screen, 1 audio source, "))
    }

    @Test func aNarrowTerminalCutsTheLineToItsWidth() {
        #expect(StatusLine.fit("Recording 0:01:07", width: 9) == "Recording")
        #expect(StatusLine.fit("Recording", width: 9) == "Recording")
        #expect(StatusLine.fit("Recording", width: 20) == "Recording")
        #expect(StatusLine.fit("Recording", width: 0) == "")
    }

    @Test func anUnknownWidthCutsNothing() {
        #expect(StatusLine.fit("Recording 0:01:07", width: nil) == "Recording 0:01:07")
    }
}
