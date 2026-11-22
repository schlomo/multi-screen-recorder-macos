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

    @Test func noScreensNoNumbers() {
        #expect(numberScreens([]).isEmpty)
    }
}

/// `msr list` prints the same "What will be recorded" table as `msr check`, without the ready check.
@Suite struct ListRenderingTests {
    private func rendered(
        screens: [ScreenInfo] = DesignExample.screens, audioInputs: [AudioInputInfo] = DesignExample.audioInputs,
        cameras: [CameraInfo] = [], settings: Settings = .defaults, systemAudioAvailable: Bool = true
    ) -> String {
        renderList(settings: settings, screens: screens, audioInputs: audioInputs, cameras: cameras, systemAudioAvailable: systemAudioAvailable)
    }

    static let designExample = """
        What will be recorded
          Settings: Auto (resolution Native, audio mode Wired, camera mode All real), system audio on
          Source                                      Looks like  Drawn at   Records at  GB/h max
          ───────────────────────────────────────────────────────────────────────────────────────
          Screen 1 - Built-in Retina Display          1728×1117   3456×2234  1728×1116        1.0
          Screen 2 - LG HDR 4K                        3840×2160   3840×2160  3840×2160        4.1
          ───────────────────────────────────────────────────────────────────────────────────────
          Camera 1 - FaceTime HD Camera (default)                            1920×1080        1.1
          ───────────────────────────────────────────────────────────────────────────────────────
          Audio 0 - System                                                   stereo           0.1
          Audio 1 - MacBook Pro Microphone (default)                         1 channel        0.1
          Audio 2 - RØDE Wireless GO II RX                                   2 channels       0.1
          ───────────────────────────────────────────────────────────────────────────────────────
          Total                                                                               6.4
          2 hours need 12.8 GB.
          Files go to ~/Movies/Multi Screen Recorder
        System audio: available

        """

    @Test func rendersTheSameTableAsMSRCheckAndTheSystemAudioLine() {
        #expect(rendered(cameras: DesignExample.cameras) == Self.designExample)
        let check = WhatWillBeRecorded(settings: .defaults, screens: .success(DesignExample.screens),
                                       audioInputs: .success(DesignExample.audioInputs), cameras: DesignExample.cameras,
                                       outputFolder: nil).text
        #expect(rendered(cameras: DesignExample.cameras).hasPrefix(check))
    }

    /// `msr list` shows a camera without the Camera permission as not recorded, saying why (D74).
    @Test func aCameraWithoutTheCameraPermissionIsListedWithTheReason() {
        let listed = renderList(
            settings: .defaults, screens: [], audioInputs: [], cameras: DesignExample.cameras, cameraPermissionDenied: true,
            systemAudioAvailable: true)
        #expect(listed.contains("FaceTime HD Camera (default) (no Camera permission)"))
        #expect(!listed.contains("Camera 1 - "))
    }

    @Test func theDesignShowsTheExample() throws {
        #expect(try repositoryFile("docs/design/recorder.md").contains("```\n\(Self.designExample)```\n"))
    }

    @Test func anInputWhoseChannelsCannotBeReadIsListedWithTheReason() {
        let unreadable = AudioInputInfo(name: "X", channelCount: .failure(DeviceReadError("no format")), isDefault: false)
        let row = rendered(screens: [], audioInputs: [unreadable]).split(separator: "\n").first { $0.contains("X ") }
        let blank = { (count: Int) in String(repeating: " ", count: count) }
        #expect(row == Substring("  " + blank(10) + "X (no device ID)" + "  " + blank(10) + "  " + blank(8) + "  "
            + "cannot be read (no format)" + "  " + blank(7) + "-"))
    }

    @Test func onlyARecordedInputThatCannotBeReadCounts() {
        let unreadable = AudioInputInfo(name: "X", channelCount: .failure(DeviceReadError("no format")), isDefault: false, uid: "X")
        let unreadableDefault = AudioInputInfo(name: "Y", channelCount: .failure(DeviceReadError("no format")), isDefault: true, uid: "Y")
        #expect(unreadableRecordedInputs([unreadable], settings: .manual).isEmpty)
        #expect(unreadableRecordedInputs([unreadable, unreadableDefault], settings: .manual) == [unreadableDefault])
        var none = Settings.manual
        none.audioMode = .none
        #expect(unreadableRecordedInputs([unreadableDefault], settings: none).isEmpty)
    }

    /// One that cannot be opened is not recorded, so it is not judged.
    @Test func aRecordedInputWithoutAUIDThatCannotBeReadDoesNotCount() {
        let noUID = AudioInputInfo(name: "Y", channelCount: .failure(DeviceReadError("no format")), isDefault: true)
        #expect(unreadableRecordedInputs([noUID], settings: .manual).isEmpty)
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
        let screens = [
            ScreenInfo(name: "Wacom One 13T", pixelSize: FrameSize(width: 3840, height: 2160),
                        pointSize: FrameSize(width: 1920, height: 1080), isMain: false, originX: 3440, originY: 0),
            ScreenInfo(name: "DELL P3421W", pixelSize: FrameSize(width: 6880, height: 2880),
                        pointSize: FrameSize(width: 3440, height: 1440), isMain: true, originX: 0, originY: 0),
        ]
        var p1080 = Settings.manual
        p1080.resolution = .p1080
        let lines = rendered(screens: screens, audioInputs: [], settings: p1080).split(separator: "\n")
        #expect(lines.contains { $0.hasPrefix("  Screen 1 - DELL P3421W") && $0.contains("3440×1440") && $0.contains("6880×2880") && $0.contains("1920×802") })
        #expect(lines.contains { $0.hasPrefix("  Screen 2 - Wacom One 13T") && $0.contains("1920×1080") && $0.contains("3840×2160") })
    }

    @Test func theSystemAudioLineSaysWhichProgramLacksThePermission() {
        #expect(rendered(systemAudioAvailable: true).hasSuffix("System audio: available\n"))
        #expect(rendered(systemAudioAvailable: false).hasSuffix(
            "System audio: not available, the program running msr (a terminal app) lacks the Screen & System Audio Recording permission\n"))
    }

    @Test func noScreensAndNoInputsStillGiveTheTable() {
        let text = rendered(screens: [], audioInputs: [])
        #expect(text.contains("Audio 0 - System"))
        #expect(text.hasPrefix("What will be recorded\n  Settings: "))
    }
}
