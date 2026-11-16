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
        failed.error = "-3811"
        #expect(EventLine.text(failed, started: start, timeZone: berlin) == "22:15:32 +61.3s screen stream failed: LG (-3811)")
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

    @Test func aDebugLineCarriesTheTimeSinceTheStartAsAnEventLineDoes() {
        #expect(EventLine.debugText("start Screen 3 - LG", category: "recorder", seconds: 27.94)
            == "debug recorder: +27.9s start Screen 3 - LG")
        #expect(EventLine.debugText("probe", category: "ready check", seconds: nil) == "debug ready check: probe")
    }
}
