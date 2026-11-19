import Testing
@testable import RecorderLogic

/// The facts a capture tells of its frames, and of its writer's inputs (D66).
@Suite struct FrameFactsTests {
    private let facts = FrameFacts(
        width: 1280, height: 720, pixelFormat: "420v", primaries: "ITU_R_709_2", transferFunction: "ITU_R_709_2",
        yCbCrMatrix: "ITU_R_709_2", iccProfile: "none", contentRect: "(0,0,1280,720)", scaleFactor: 1,
        screenCheck: "passes")

    @Test func theFirstFrameIsOneLineOfFacts() {
        #expect(facts.text == "1280×720 420v, primaries ITU_R_709_2, transfer function ITU_R_709_2, matrix ITU_R_709_2, "
            + "ICC profile none, content rect (0,0,1280,720), scale factor 1.0, screen check passes")
    }

    @Test func aFrameLikeTheBeforeChangesNothing() {
        #expect(facts.changes(from: facts) == nil)
    }

    @Test func onlyWhatChangedIsTold() {
        var next = facts
        next.width = 1600
        next.height = 900
        next.yCbCrMatrix = "none"
        next.contentRect = nil
        next.iccProfile = "attached"
        next.screenCheck = "fails"
        #expect(next.changes(from: facts) == "size 1280×720 → 1600×900, matrix ITU_R_709_2 → none, ICC profile none → attached, "
            + "content rect (0,0,1280,720) → none, screen check passes → fails")
    }

    @Test func aPixelFormatIsItsFourCharacterCode() {
        #expect(FrameFacts.fourCharacterCode(0x34323076) == "420v")
        #expect(FrameFacts.fourCharacterCode(7) == "0x7")
    }

    @Test func theEncodersOfACodecAreOneLine() {
        let list = [EncoderListText.Encoder(name: "Apple HEVC", id: "ave.hevc", isHardwareAccelerated: true),
                    EncoderListText.Encoder(name: "Soft", id: "soft.hevc", isHardwareAccelerated: false)]
        #expect(EncoderListText.text(codec: "hvc1", list)
            == "video encoders for hvc1: Apple HEVC (ave.hevc, hardware accelerated), Soft (soft.hevc, software)")
        #expect(EncoderListText.text(codec: "hvc1", []) == "video encoders for hvc1: none listed")
    }

    @Test func settingsAreOneLineWithSortedKeys() {
        let settings: [String: Any] = ["b": ["y": 2, "x": [1, 2]], "a": "hvc1", "c": true]
        #expect(SettingsText.text(settings) == "{a=hvc1, b={x=[1, 2], y=2}, c=true}")
    }

    @Test func aWriterToldInputsByTheirSamplesAndTheFirstRefusal() {
        var appends = InputAppends(inputs: ["video", "guide track Audio inputs", "timecode"])
        appends.appended("timecode", at: 1.266)
        appends.appended("video", at: 1.266)
        appends.appended("video", at: 1.3)
        #expect(appends.text == "video: 2 samples, last at 1.300 s; guide track Audio inputs: 0 samples; "
            + "timecode: 1 sample, last at 1.266 s; no append returned false")
        appends.refused("guide track Audio inputs")
        appends.refused("video")
        #expect(appends.firstRefused == "guide track Audio inputs")
        #expect(appends.text.hasSuffix("the first append that returned false: guide track Audio inputs"))
    }
}
