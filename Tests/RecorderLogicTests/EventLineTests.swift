import Foundation
import Testing
@testable import RecorderLogic

/// `msr record` prints every manifest event as one line on standard error (D46).
@Suite struct EventLineTests {
    private let berlin = TimeZone(identifier: "Europe/Berlin")!
    private let start = Date(timeIntervalSince1970: 1_794_777_271)  // 2026-11-15 22:14:31 in Berlin

    @Test func anEventIsItsLocalTimeItsOffsetAndItsScreen() {
        let event = RecordingEvent(at: 9_200_000_000, event: .screenConnected, screen: "Wacom One 13T")
        #expect(EventLine.text(event, started: start, timeZone: berlin) == "22:14:40 +9.2s screen connected: Wacom One 13T")
    }

    @Test func anEventWithoutAScreenAndWithAnError() {
        #expect(EventLine.text(RecordingEvent(at: 0, event: .sleep), started: start, timeZone: berlin) == "22:14:31 +0.0s sleep")
        var failed = RecordingEvent(at: 61_300_000_000, event: .screenStreamFailed, screen: "LG")
        failed.errorDetail = "-3811"
        #expect(EventLine.text(failed, started: start, timeZone: berlin) == "22:15:32 +61.3s screen stream failed: LG (-3811)")
    }

    /// An input that left the guide track, in a recording made before D90, says its offset; written and read back as
    /// `offset` (D79).
    @Test func anInputThatLeftTheGuideTrackSaysItsOffset() throws {
        var left = RecordingEvent(at: 0, event: .audioInputLeftTheGuideTrack, audioSource: "Razer")
        left.offset = 0.5
        #expect(EventLine.text(left, started: start, timeZone: berlin).hasSuffix("audio input left the guide track: Razer 500 ms late"))
        #expect(try JSONDecoder().decode(RecordingEvent.self, from: JSONEncoder().encode(left)) == left)
        #expect(!RecordingEvent.Kind.audioInputLeftTheGuideTrack.isFailure)
    }

    @Test func aFrameSizeChangeAndAMirrorSayWhat() {
        var changed = RecordingEvent(at: 0, event: .screenFrameSizeChanged, screen: "LG")
        changed.from = [1670, 1080]
        changed.to = [1662, 1080]
        #expect(EventLine.text(changed, started: start, timeZone: berlin).hasSuffix("screen frame size changed: LG 1670x1080 → 1662x1080"))
        var mirroring = RecordingEvent(at: 0, event: .screenMirroringStarted, screen: "LG")
        mirroring.mirrors = "Built-in Retina Display"
        #expect(EventLine.text(mirroring, started: start, timeZone: berlin).hasSuffix("screen mirroring started: LG mirrors Built-in Retina Display"))
    }

    @Test func anAudioSourcesEventNamesTheSource() {
        var gap = RecordingEvent(at: 0, event: .audioInputGap, audioSource: "Razer Seiren V3 Mini")
        gap.length = 0.25
        #expect(EventLine.text(gap, started: start, timeZone: berlin).hasSuffix("audio input gap: Razer Seiren V3 Mini 0.250s"))
    }

    /// The recording log's lines (D64) start, as an event's, with the local time and the offset.
    @Test func theRecordingLogsDetailAndProblemLines() {
        #expect(DetailLine.recordingLogText("start Screen 3 - LG", category: "recorder", seconds: 27.94, started: start, timeZone: berlin)
            == "22:14:58 +27.9s detail recorder: start Screen 3 - LG")
        let problem = RecordingProblem(at: 61_300_000_000, problem: "Screen file a.mov", error: "cannot write a.mov")
        #expect(EventLine.problemText(problem, started: start, timeZone: berlin)
            == "22:15:32 +61.3s problem: Screen file a.mov: cannot write a.mov")
    }

    @Test func aDetailLineCarriesTheTimeSinceTheStartAsAnEventLineDoes() {
        #expect(DetailLine.standardErrorText("start Screen 3 - LG", category: "recorder", seconds: 27.94)
            == "detail recorder: +27.9s start Screen 3 - LG")
        #expect(DetailLine.standardErrorText("probe", category: "ready check", seconds: nil) == "detail ready check: probe")
    }
}
