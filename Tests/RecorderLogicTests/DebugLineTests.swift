import Testing
@testable import RecorderLogic

/// `--debug` lines read as sentences, not as Swift's description of a struct.
@Suite struct DebugLineTests {
    private let dell = DisplayInfo(name: "DELL P3421W", pixelSize: FrameSize(width: 3440, height: 1440),
                                   pointSize: FrameSize(width: 3440, height: 1440), isMain: true, originX: 0, originY: 0)
    private let retina = DisplayInfo(name: "Built-in Retina Display", pixelSize: FrameSize(width: 3456, height: 2234),
                                     pointSize: FrameSize(width: 1728, height: 1117), isMain: false, originX: 3440, originY: 0)

    @Test func theReadyCheckFactsAreOneLine() {
        let facts = ReadyCheckFacts(
            screenRecording: .granted, microphoneGranted: true, displays: .success([dell, retina]),
            audioInputs: .success([AudioInputInfo(name: "MacBook Pro Microphone", channelCount: 1, isDefault: true)]),
            outputFolder: .usable(.bytes(120_400_000_000)))
        #expect(DebugLine.facts(facts) == "screen recording granted; microphone granted; "
            + "displays: DELL P3421W 3440×1440 at (0,0) main, Built-in Retina Display looks like 1728×1117, drawn at 3456×2234 at (3440,0); "
            + "audio inputs: MacBook Pro Microphone (default) 1 channel; output folder usable, 120.4 GB free")
    }

    @Test func whatCouldNotBeReadSaysWhy() {
        let facts = ReadyCheckFacts(
            screenRecording: .failed("-3801"), microphoneGranted: nil, displays: .failure(DeviceReadError("no list")),
            audioInputs: .success([]), outputFolder: .unusable("read-only"))
        #expect(DebugLine.facts(facts) == "screen recording failed (-3801); microphone not asked; displays cannot be read (no list); "
            + "audio inputs: none; output folder unusable (read-only)")
    }

    @Test func anActionNamesTheDisplay() {
        let start = DisplayTracker.Action.start(
            uuid: "037036FB-1234-5678-9ABC-DEF012345678", displayID: 2, frameSize: FrameSize(width: 1920, height: 1080),
            number: 2, name: "Wacom One 13T")
        #expect(DebugLine.action(start, names: [:])
            == "start Display 2 Wacom One 13T (UUID 037036FB…, display ID 2) at 1920×1080")
        #expect(DebugLine.action(.stop(uuid: "037036FB-1234", ending: .disconnected), names: ["037036FB-1234": "Display 2 Wacom One 13T"])
            == "stop Display 2 Wacom One 13T (disconnected)")
    }

    @Test func theDisplaysAsReadAreOneLine() {
        let displays = [
            ConnectedDisplay(uuid: "A", displayID: 1, name: "DELL P3421W", pointSize: FrameSize(width: 3440, height: 1440),
                             bounds: ScreenRect(x: 0, y: 0, width: 3440, height: 1440), isMain: true),
            ConnectedDisplay(uuid: "B", displayID: 3, name: nil, pointSize: FrameSize(width: 1920, height: 1080),
                             bounds: ScreenRect(x: 3440, y: 0, width: 1920, height: 1080), isMain: false, mirrorsUUID: "A"),
        ]
        #expect(DebugLine.displays(displays)
            == "DELL P3421W 3440×1440 at (0,0) main (display ID 1), unnamed 1920×1080 at (3440,0) mirrors A (display ID 3)")
    }
}
