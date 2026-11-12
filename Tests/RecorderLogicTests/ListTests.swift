import Testing
@testable import RecorderLogic

@Suite struct DisplayNumberingTests {
    private func display(_ name: String, main: Bool = false, x: Double, y: Double = 0) -> DisplayInfo {
        DisplayInfo(name: name, pixelSize: FrameSize(width: 1920, height: 1080), isMain: main, originX: x, originY: y)
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
    @Test func rendersExactlyAsTheDesign() {
        let displays = numberDisplays([
            DisplayInfo(name: "LG HDR 4K", pixelSize: FrameSize(width: 3840, height: 2160), isMain: false, originX: 1728, originY: 0),
            DisplayInfo(name: "Built-in Retina Display", pixelSize: FrameSize(width: 3456, height: 2234), isMain: true, originX: 0, originY: 0),
        ])
        let inputs = [
            AudioInputInfo(name: "MacBook Pro Microphone", channelCount: 1, isDefault: true),
            AudioInputInfo(name: "RØDE Wireless GO II RX", channelCount: 2, isDefault: false),
        ]
        let expected = """
            Displays
              1  Built-in Retina Display   3456×2234  records at 1670×1080
              2  LG HDR 4K                 3840×2160  records at 1920×1080
            Audio inputs
              MacBook Pro Microphone (default), 1 channel
              RØDE Wireless GO II RX, 2 channels
            System audio: available

            """
        #expect(renderList(displays: displays, resolution: .p1080, audioInputs: inputs, systemAudioAvailable: true) == expected)
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
