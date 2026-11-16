import Testing
@testable import RecorderLogic

@Suite struct ScreenNumberingTests {
    private func screen(_ name: String, main: Bool = false, x: Double, y: Double = 0) -> ScreenInfo {
        ScreenInfo(name: name, pixelSize: FrameSize(width: 1920, height: 1080), pointSize: FrameSize(width: 1920, height: 1080), isMain: main, originX: x, originY: y)
    }

    @Test func theMainScreenIsOneAndTheOthersGoLeftToRight() {
        let numbered = numberScreens([
            screen("Right", x: 3000),
            screen("Left", x: -1920),
            screen("Main", main: true, x: 0),
            screen("Middle", x: 1728),
        ])
        #expect(numbered.map(\.number) == [1, 2, 3, 4])
        #expect(numbered.map(\.screen.name) == ["Main", "Left", "Middle", "Right"])
    }

    @Test func screensAtTheSameLeftEdgeGoTopToBottom() {
        let numbered = numberScreens([
            screen("Main", main: true, x: 0),
            screen("Lower", x: 1920, y: 1080),
            screen("Upper", x: 1920, y: 0),
        ])
        #expect(numbered.map(\.screen.name) == ["Main", "Upper", "Lower"])
    }

    /// D55: the window and `msr list` number only what the recording
    /// records: a screen that mirrors another is not recorded.
    @Test func aMirroringScreenGetsNoNumberAndTheOthersAreNumberedAsTheRecordingDoes() {
        var mirror = screen("Mirror", x: -1920)
        mirror.isMirroring = true
        let infos = [screen("Right", x: 3000), mirror, screen("Main", main: true, x: 0), screen("Middle", x: 1728)]
        let numbered = numberScreens(infos)
        #expect(numbered.map(\.screen.name) == ["Main", "Middle", "Right"])
        #expect(numbered.map(\.number) == [1, 2, 3])
        let connected = infos.enumerated().map { index, info in
            ConnectedScreen(uuid: info.name, displayID: UInt32(index + 1), name: info.name, pointSize: info.pointSize,
                            bounds: ScreenRect(x: info.originX, y: info.originY, width: 1920, height: 1080), isMain: info.isMain,
                            mirrorsUUID: info.isMirroring ? "Main" : nil)
        }
        var tracker = ScreenTracker(resolution: .native)
        let started = tracker.begin(connected, at: 0).actions.compactMap { action -> String? in
            if case .start(_, _, _, let number, let name) = action { "\(number) \(name)" } else { nil }
        }
        #expect(started == numbered.map { "\($0.number) \($0.screen.name)" })
    }

    @Test func noScreensNoNumbers() {
        #expect(numberScreens([]).isEmpty)
    }
}

@Suite struct ListRenderingTests {
    static let designExample = """
        Screens
          1  Built-in Retina Display   looks like 1728×1117, drawn at 3456×2234  records at 1728×1116
          2  LG HDR 4K                 3840×2160                                 records at 3840×2160
        Audio inputs
          MacBook Pro Microphone (default), 1 channel
          RØDE Wireless GO II RX, 2 channels
        System audio: available

        """

    @Test func rendersExactlyAsTheDesign() {
        let rendered = renderList(
            screens: numberScreens(DesignExample.screens), resolution: Settings.defaults.effectiveResolution,
            audioInputs: DesignExample.audioInputs, systemAudioAvailable: true)
        #expect(rendered == Self.designExample)
    }

    @Test func anInputWhoseChannelsCannotBeReadIsListedWithTheReason() {
        let unreadable = AudioInputInfo(name: "X", channelCount: .failure(DeviceReadError("no format")), isDefault: false)
        let rendered = renderList(screens: [], resolution: .p1080, audioInputs: [unreadable], systemAudioAvailable: true)
        #expect(rendered.contains("\n  X, cannot be read (no format)\n"))
    }

    @Test func onlyARecordedInputThatCannotBeReadCounts() {
        let unreadable = AudioInputInfo(name: "X", channelCount: .failure(DeviceReadError("no format")), isDefault: false)
        let unreadableDefault = AudioInputInfo(name: "Y", channelCount: .failure(DeviceReadError("no format")), isDefault: true)
        #expect(unreadableRecordedInputs([unreadable], settings: .manual).isEmpty)
        #expect(unreadableRecordedInputs([unreadable, unreadableDefault], settings: .manual) == [unreadableDefault])
        var none = Settings.manual
        none.audioMode = .none
        #expect(unreadableRecordedInputs([unreadableDefault], settings: none).isEmpty)
    }

    @Test func theDesignShowsTheExample() throws {
        #expect(try repositoryFile("docs/design/recorder.md").contains("```\n\(Self.designExample)```\n"))
    }

    @Test func aScreenIsDescribedByWhatItLooksLikeAndItsPixels() {
        func screen(pixels: FrameSize, points: FrameSize) -> ScreenInfo {
            ScreenInfo(name: "D", pixelSize: pixels, pointSize: points, isMain: true, originX: 0, originY: 0)
        }
        #expect(screen(pixels: FrameSize(width: 3440, height: 1440), points: FrameSize(width: 3440, height: 1440))
            .sizeText == "3440×1440")
        #expect(screen(pixels: FrameSize(width: 6880, height: 2880), points: FrameSize(width: 3440, height: 1440))
            .sizeText == "looks like 3440×1440, drawn at 6880×2880")
    }

    @Test func theOwnersHiDPIScreensRecordAtTheirLooksLikeSize() {
        let screens = numberScreens([
            ScreenInfo(name: "DELL P3421W", pixelSize: FrameSize(width: 6880, height: 2880),
                        pointSize: FrameSize(width: 3440, height: 1440), isMain: true, originX: 0, originY: 0),
            ScreenInfo(name: "Wacom One 13T", pixelSize: FrameSize(width: 3840, height: 2160),
                        pointSize: FrameSize(width: 1920, height: 1080), isMain: false, originX: 3440, originY: 0),
        ])
        let lines = renderList(screens: screens, resolution: .p1080, audioInputs: [], systemAudioAvailable: true)
            .split(separator: "\n")
        #expect(lines[1] == "  1  DELL P3421W     looks like 3440×1440, drawn at 6880×2880  records at 1920×802")
        #expect(lines[2] == "  2  Wacom One 13T   looks like 1920×1080, drawn at 3840×2160  records at 1920×1080")
        let native = renderList(screens: screens, resolution: .native, audioInputs: [], systemAudioAvailable: true)
            .split(separator: "\n")
        #expect(lines.count == native.count)
        #expect(native[1].hasSuffix("records at 3440×1440"))
        #expect(native[2].hasSuffix("records at 1920×1080"))
    }

    @Test func rendersEmptySectionsAndUnavailableSystemAudio() {
        let expected = """
            Screens
              none
            Audio inputs
              none
            System audio: not available without the Screen & System Audio Recording permission

            """
        #expect(renderList(screens: [], resolution: .p1080, audioInputs: [], systemAudioAvailable: false) == expected)
    }
}
