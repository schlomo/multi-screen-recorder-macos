import Foundation
import Testing
@testable import RecorderLogic

/// The status window's table and line (D46).
@Suite struct RecordingStatusTableTests {
    private func screen(_ uuid: String, _ name: String, main: Bool = false, x: Double = 0) -> ConnectedScreen {
        ConnectedScreen(uuid: uuid, displayID: 1, name: name, pointSize: FrameSize(width: 1920, height: 1080),
                         bounds: ScreenRect(x: x, y: 0, width: 1920, height: 1080), isMain: main)
    }

    private func file(_ name: String, uuid: String, screen: String) -> RecordingManifest.ScreenFile {
        RecordingManifest.ScreenFile(name: name, screen: screen, screenUUID: uuid, frameSize: FrameSize(width: 1920, height: 1080),
                                      start: 0, timecode: "00:00:00:00")
    }

    @Test func eachScreenIsARowWithItsFilesBytesAndState() {
        var tracker = ScreenTracker(resolution: .native)
        let built = screen("A", "Built-in Retina Display", main: true)
        let lg = screen("B", "LG HDR 4K", x: 1920)
        _ = tracker.begin([built, lg], at: 0)
        tracker.fileStarted("A")
        _ = tracker.streamEnded("B", .diskFull, connected: [built, lg], at: 1)
        let files = [file("a1.mov", uuid: "A", screen: "Built-in Retina Display"), file("a2.mov", uuid: "A", screen: "Built-in Retina Display"),
                     file("b1.mov", uuid: "B", screen: "LG HDR 4K")]
        let rows = RecordingStatusTable.rows(
            sources: tracker.sources, files: files, bytes: ["a1.mov": 1_000_000_000, "a2.mov": 260_000_000, "b1.mov": 40_000_000])
        #expect(rows == [
            .init(source: .screen(1, name: "Built-in Retina Display"), recordsAt: "1920×1080", files: 2, written: "1.3 GB", state: "recording"),
            .init(source: .screen(2, name: "LG HDR 4K"), recordsAt: "1920×1080", files: 1, written: "40 MB", state: "disk full"),
        ])
        #expect(RecordingStatusTable.columns == ["Source", "Records at", "Files", "Written", "State"])
    }

    @Test func aScreenWaitingGoneOrFailingSaysSo() {
        var tracker = ScreenTracker(resolution: .native)
        let built = screen("A", "Built-in", main: true)
        let lg = screen("B", "LG", x: 1920)
        let wacom = screen("C", "Wacom", x: 3840)
        _ = tracker.begin([built, lg, wacom], at: 0)
        _ = tracker.streamEnded("A", .writerFailed("x"), connected: [built, lg, wacom], at: 1)
        _ = tracker.observe([built, wacom], at: 2)
        _ = tracker.streamEnded("C", .showsAnotherScreen, connected: [built, wacom], at: 3)
        let states = RecordingStatusTable.rows(sources: tracker.sources, files: [], bytes: [:]).map(\.state)
        #expect(states == ["failed, retrying", "disconnected", "shows another screen"])
    }

    /// The window sizes the State column from these, so each state a source can be in shows one of them.
    @Test func everyStateTextIsListed() {
        let screenStates: [ScreenTracker.Source.State] = [
            .recording(FrameSize(width: 1, height: 1)), .waiting, .failedRetrying, .showsAnotherScreen, .diskFull,
            .mirroring, .disconnected, .asleep,
        ]
        let audioStates: [AudioTracker.Source.State] = [
            .recording, .waiting, .failedRetrying, .diskFull, .disconnected, .notRecorded, .asleep,
        ]
        let texts = Set(RecordingStatusTable.StateText.allCases.map(\.rawValue))
        #expect(Set(screenStates.map { RecordingStatusTable.text($0) }).union(audioStates.map { RecordingStatusTable.text($0) })
            == texts)
        #expect(texts.contains("shows another screen"))
    }

    @Test func aScreenNotYetRecordingIsWaiting() {
        var tracker = ScreenTracker(resolution: .native)
        let built = screen("A", "Built-in", main: true)
        _ = tracker.begin([built], at: 0)
        _ = tracker.observe([built, screen("B", "LG", x: 1920)], at: 1)
        let rows = RecordingStatusTable.rows(sources: tracker.sources, files: [], bytes: [:])
        #expect(rows.map(\.state) == ["recording", "waiting"])
        #expect(rows[1].source == .screen(nil, name: "LG") && rows[1].recordsAt == "" && rows[1].files == 0)
    }

    @Test func eachAudioSourceIsARowUnderItsNumber() {
        var settings = Settings.defaults
        settings.auto = false
        settings.audioMode = .allInputs
        settings.systemAudio = true
        var tracker = AudioTracker(settings: settings)
        let usb = AudioInputInfo(name: "USB Audio", channelCount: 1, isDefault: true, transport: .usb, uid: "U1")
        let twin = AudioInputInfo(name: "USB Audio", channelCount: 2, isDefault: false, transport: .usb, uid: "U2")
        _ = tracker.begin(inputs: [usb, twin], mainDisplayID: 1, screens: [1], at: 0)
        let rows = RecordingStatusTable.audioRows(sources: tracker.sourcesShown, files: [], bytes: [:])
        #expect(rows.map(\.source) == [
            .audioInput(1, name: "USB Audio"), .audioInput(2, name: "USB Audio"), .systemAudio(isRecorded: true),
        ])
    }

    /// A size that cannot be read is not shown as nothing written.
    @Test func aFileSizeThatCannotBeReadIsAQuestionMark() {
        var tracker = ScreenTracker(resolution: .native)
        _ = tracker.begin([screen("A", "Built-in", main: true)], at: 0)
        let files = [file("a1.mov", uuid: "A", screen: "Built-in"), file("a2.mov", uuid: "A", screen: "Built-in")]
        let rows = RecordingStatusTable.rows(sources: tracker.sources, files: files, bytes: ["a1.mov": 1_000_000_000])
        #expect(rows.map(\.written) == ["?"])
        #expect(rows.map(\.files) == [2])
    }

    /// D47: the status window shows the elapsed time as h:mm:ss.
    @Test(arguments: [(0.0, "0:00:00"), (59.9, "0:00:59"), (65, "0:01:05"), (4020, "1:07:00"), (36_061, "10:01:01")])
    func theElapsedTimeIsHoursMinutesAndSeconds(seconds: Double, text: String) {
        #expect(RecordingStatusTable.elapsed(seconds) == text)
    }

    @Test func theLineSaysTimeDataFilesAndFreeSpace() {
        #expect(RecordingStatusTable.line(elapsedSeconds: 4020, bytesWritten: 1_260_000_000, files: 3, freeBytes: 120_400_000_000)
            == "Recording 1:07:00 · 1.3 GB in 3 files · 120.4 GB free")
        #expect(RecordingStatusTable.line(elapsedSeconds: 5, bytesWritten: 0, files: 1, freeBytes: nil)
            == "Recording 0:00:05 · 0 MB in 1 file")
        // Below 1 GB in MB, so the first minutes do not show 0.0 GB.
        #expect(RecordingStatusTable.line(elapsedSeconds: 90, bytesWritten: 350_400_000, files: 7, freeBytes: 800_000_000)
            == "Recording 0:01:30 · 350 MB in 7 files · 800 MB free")
        // A size that cannot be read: the data written is not undercounted.
        #expect(RecordingStatusTable.line(elapsedSeconds: 5, bytesWritten: nil, files: 2, freeBytes: 1_000_000_000)
            == "Recording 0:00:05 · ? GB in 2 files · 1.0 GB free")
    }
}
