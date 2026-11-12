import Testing
@testable import RecorderLogic

@Suite struct DisplayNumberingTests {
    private func display(_ name: String, main: Bool = false, x: Double, y: Double = 0) -> DisplayInfo {
        DisplayInfo(name: name, pixelSize: FrameSize(width: 1920, height: 1080), pointSize: FrameSize(width: 1920, height: 1080), isMain: main, originX: x, originY: y)
    }

    @Test func theMainDisplayIsOneAndTheOthersGoLeftToRight() {
        let numbered = numberDisplays([
            display("Right", x: 3000),
            display("Left", x: -1920),
            display("Main", main: true, x: 0),
            display("Middle", x: 1728),
        ])
        #expect(numbered.map(\.number) == [1, 2, 3, 4])
        #expect(numbered.map(\.display.name) == ["Main", "Left", "Middle", "Right"])
    }

    @Test func displaysAtTheSameLeftEdgeGoTopToBottom() {
        let numbered = numberDisplays([
            display("Main", main: true, x: 0),
            display("Lower", x: 1920, y: 1080),
            display("Upper", x: 1920, y: 0),
        ])
        #expect(numbered.map(\.display.name) == ["Main", "Upper", "Lower"])
    }

    @Test func noDisplaysNoNumbers() {
        #expect(numberDisplays([]).isEmpty)
    }
}

@Suite struct ListRenderingTests {
    static let designExample = """
        Displays
          1  Built-in Retina Display   looks like 1728×1117, drawn at 3456×2234  records at 1670×1080
          2  LG HDR 4K                 3840×2160                                 records at 1920×1080
        Audio inputs
          MacBook Pro Microphone (default), 1 channel
          RØDE Wireless GO II RX, 2 channels
        System audio: available

        """

    @Test func rendersExactlyAsTheDesign() {
        let rendered = renderList(
            displays: numberDisplays(DesignExample.displays), resolution: .p1080,
            audioInputs: DesignExample.audioInputs, systemAudioAvailable: true)
        #expect(rendered == Self.designExample)
    }

    @Test func theDesignShowsTheExample() throws {
        #expect(try repositoryFile("docs/design/recorder.md").contains("```\n\(Self.designExample)```\n"))
    }

    @Test func aDisplayIsDescribedByWhatItLooksLikeAndItsPixels() {
        func display(pixels: FrameSize, points: FrameSize) -> DisplayInfo {
            DisplayInfo(name: "D", pixelSize: pixels, pointSize: points, isMain: true, originX: 0, originY: 0)
        }
        #expect(display(pixels: FrameSize(width: 3440, height: 1440), points: FrameSize(width: 3440, height: 1440))
            .sizeText == "3440×1440")
        #expect(display(pixels: FrameSize(width: 6880, height: 2880), points: FrameSize(width: 3440, height: 1440))
            .sizeText == "looks like 3440×1440, drawn at 6880×2880")
    }

    @Test func theOwnersHiDPIDisplaysRecordAtTheirPixelSize() {
        let displays = numberDisplays([
            DisplayInfo(name: "DELL P3421W", pixelSize: FrameSize(width: 6880, height: 2880),
                        pointSize: FrameSize(width: 3440, height: 1440), isMain: true, originX: 0, originY: 0),
            DisplayInfo(name: "Wacom One 13T", pixelSize: FrameSize(width: 3840, height: 2160),
                        pointSize: FrameSize(width: 1920, height: 1080), isMain: false, originX: 3440, originY: 0),
        ])
        let lines = renderList(displays: displays, resolution: .p1080, audioInputs: [], systemAudioAvailable: true)
            .split(separator: "\n")
        #expect(lines[1] == "  1  DELL P3421W     looks like 3440×1440, drawn at 6880×2880  records at 1920×802")
        #expect(lines[2] == "  2  Wacom One 13T   looks like 1920×1080, drawn at 3840×2160  records at 1920×1080")
    }

    @Test func rendersEmptySectionsAndUnavailableSystemAudio() {
        let expected = """
            Displays
              none
            Audio inputs
              none
            System audio: not available without the Screen & System Audio Recording permission

            """
        #expect(renderList(displays: [], resolution: .p1080, audioInputs: [], systemAudioAvailable: false) == expected)
    }
}
