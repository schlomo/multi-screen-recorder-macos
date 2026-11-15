import Foundation
import Testing
@testable import RecorderLogic

/// The status window's table and line (D46).
@Suite struct RecordingStatusTableTests {
    private func display(_ uuid: String, _ name: String, main: Bool = false, x: Double = 0) -> ConnectedDisplay {
        ConnectedDisplay(uuid: uuid, displayID: 1, name: name, pointSize: FrameSize(width: 1920, height: 1080),
                         bounds: ScreenRect(x: x, y: 0, width: 1920, height: 1080), isMain: main)
    }

    private func file(_ name: String, uuid: String, display: String) -> RecordingManifest.DisplayFile {
        RecordingManifest.DisplayFile(name: name, display: display, displayUUID: uuid, frameSize: FrameSize(width: 1920, height: 1080),
                                      start: 0, timecode: "00:00:00:00")
    }

    @Test func eachDisplayIsARowWithItsFilesBytesAndState() {
        var tracker = DisplayTracker(resolution: .native)
        let built = display("A", "Built-in Retina Display", main: true)
        let lg = display("B", "LG HDR 4K", x: 1920)
        _ = tracker.begin([built, lg], at: 0)
        tracker.fileStarted("A")
        _ = tracker.streamEnded("B", .diskFull, connected: [built, lg], at: 1)
        let files = [file("a1.mov", uuid: "A", display: "Built-in Retina Display"), file("a2.mov", uuid: "A", display: "Built-in Retina Display"),
                     file("b1.mov", uuid: "B", display: "LG HDR 4K")]
        let rows = RecordingStatusTable.rows(
            sources: tracker.sources, files: files, bytes: ["a1.mov": 1_000_000_000, "a2.mov": 260_000_000, "b1.mov": 40_000_000])
        #expect(rows == [
            .init(source: "1 Built-in Retina Display", recordsAt: "1920×1080", files: 2, gigabytesWritten: "1.3", state: "recording"),
            .init(source: "2 LG HDR 4K", recordsAt: "1920×1080", files: 1, gigabytesWritten: "0.0", state: "disk full"),
        ])
        #expect(RecordingStatusTable.columns == ["Source", "Records at", "Files", "GB written", "State"])
    }

    @Test func aDisplayWaitingGoneOrFailingSaysSo() {
        var tracker = DisplayTracker(resolution: .native)
        let built = display("A", "Built-in", main: true)
        let lg = display("B", "LG", x: 1920)
        let wacom = display("C", "Wacom", x: 3840)
        _ = tracker.begin([built, lg, wacom], at: 0)
        _ = tracker.streamEnded("A", .writerFailed("x"), connected: [built, lg, wacom], at: 1)
        _ = tracker.observe([built, wacom], at: 2)
        _ = tracker.streamEnded("C", .showsAnotherDisplay, connected: [built, wacom], at: 3)
        let states = RecordingStatusTable.rows(sources: tracker.sources, files: [], bytes: [:]).map(\.state)
        #expect(states == ["failed, retrying", "disconnected", "shows another display"])
    }

    @Test func aDisplayNotYetRecordingIsWaiting() {
        var tracker = DisplayTracker(resolution: .native)
        let built = display("A", "Built-in", main: true)
        _ = tracker.begin([built], at: 0)
        _ = tracker.observe([built, display("B", "LG", x: 1920)], at: 1)
        let rows = RecordingStatusTable.rows(sources: tracker.sources, files: [], bytes: [:])
        #expect(rows.map(\.state) == ["recording", "waiting"])
        #expect(rows[1].source == "LG" && rows[1].recordsAt == "" && rows[1].files == 0)
    }

    /// A size that cannot be read is not shown as nothing written.
    @Test func aFileSizeThatCannotBeReadIsAQuestionMark() {
        var tracker = DisplayTracker(resolution: .native)
        _ = tracker.begin([display("A", "Built-in", main: true)], at: 0)
        let files = [file("a1.mov", uuid: "A", display: "Built-in"), file("a2.mov", uuid: "A", display: "Built-in")]
        let rows = RecordingStatusTable.rows(sources: tracker.sources, files: files, bytes: ["a1.mov": 1_000_000_000])
        #expect(rows.map(\.gigabytesWritten) == ["?"])
        #expect(rows.map(\.files) == [2])
    }

    @Test func theLineSaysTimeDataFilesAndFreeSpace() {
        #expect(RecordingStatusTable.line(elapsedSeconds: 4020, bytesWritten: 1_260_000_000, files: 3, freeBytes: 120_400_000_000)
            == "Recording 1:07 · 1.3 GB in 3 files · 120.4 GB free")
        #expect(RecordingStatusTable.line(elapsedSeconds: 5, bytesWritten: 0, files: 1, freeBytes: nil)
            == "Recording 0:00 · 0.0 GB in 1 file")
        // A size that cannot be read: the data written is not undercounted.
        #expect(RecordingStatusTable.line(elapsedSeconds: 5, bytesWritten: nil, files: 2, freeBytes: 1_000_000_000)
            == "Recording 0:00 · ? GB in 2 files · 1.0 GB free")
    }
}
