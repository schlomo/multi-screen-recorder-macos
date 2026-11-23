import Testing
@testable import RecorderLogic

/// Detail lines read as sentences, not as Swift's description of a struct.
@Suite struct DetailLineTests {
    private let dell = ScreenInfo(name: "DELL P3421W", pixelSize: FrameSize(width: 3440, height: 1440),
                                   pointSize: FrameSize(width: 3440, height: 1440), isMain: true, originX: 0, originY: 0)
    private let retina = ScreenInfo(name: "Built-in Retina Display", pixelSize: FrameSize(width: 3456, height: 2234),
                                     pointSize: FrameSize(width: 1728, height: 1117), isMain: false, originX: 3440, originY: 0)

    @Test func theReadyCheckFactsAreOneLine() {
        let facts = ReadyCheckFacts(
            screenRecording: .granted, microphoneGranted: true, screens: .success([dell, retina]),
            audioInputs: .success([AudioInputInfo(name: "MacBook Pro Microphone", channelCount: 1, isDefault: true)]),
            outputFolder: .usable(.bytes(120_400_000_000)))
        #expect(DetailLine.facts(facts, resolution: .native, limitCameras: true) == "screen recording granted; microphone granted; camera not asked; "
            + "screens: DELL P3421W 3440×1440 at (0,0) main, Built-in Retina Display looks like 1728×1117, drawn at 3456×2234 at (3440,0); "
            + "audio inputs: MacBook Pro Microphone (default) 1 channel; cameras: none; output folder usable, 120.4 GB free")
    }

    @Test func theCamerasAndTheCameraPermissionAreInTheFacts() {
        let facts = ReadyCheckFacts(
            screenRecording: .granted, microphoneGranted: nil, screens: .success([]), audioInputs: .success([]),
            outputFolder: .unusable("read-only"), cameraGranted: false,
            cameras: [
                CameraInfo(uniqueID: "A", name: "FaceTime HD Camera", isDefault: true, isVirtual: false,
                           formats: [CameraFormat(size: FrameSize(width: 1920, height: 1080), maxFramesPerSecond: 30)]),
                CameraInfo(uniqueID: "C", name: "OBS Virtual Camera", isDefault: false, isVirtual: true, formats: []),
            ])
        #expect(DetailLine.facts(facts, resolution: .native, limitCameras: true) == "screen recording granted; microphone not asked; camera not granted; screens: none; "
            + "audio inputs: none; cameras: FaceTime HD Camera (default) 1920×1080 at 30 fps, OBS Virtual Camera virtual no format; "
            + "output folder unusable (read-only)")
    }

    @Test func eachCameraIsListedWithItsKindAndTheFormatItIsOpenedWithAtTheResolution() {
        let formats = [CameraFormat(size: FrameSize(width: 1280, height: 720), maxFramesPerSecond: 30),
                       CameraFormat(size: FrameSize(width: 1920, height: 1080), maxFramesPerSecond: 30)]
        let cameras = [
            CameraInfo(uniqueID: "A", name: "FaceTime HD Camera", isDefault: true, isVirtual: false, formats: formats, isSuspended: true),
            CameraInfo(uniqueID: "B", name: "iPhone Camera", isDefault: false, isVirtual: false, isContinuity: true, formats: formats),
        ]
        #expect(DetailLine.cameras(cameras, resolution: .native, limitCameras: true)
            == "FaceTime HD Camera (default) suspended 1920×1080 at 30 fps, iPhone Camera Continuity Camera 1920×1080 at 30 fps")
        #expect(DetailLine.cameras(cameras, resolution: .p720, limitCameras: true)
            == "FaceTime HD Camera (default) suspended 1280×720 at 30 fps, iPhone Camera Continuity Camera 1280×720 at 30 fps")
        #expect(DetailLine.cameras(cameras, resolution: .none, limitCameras: true) == "FaceTime HD Camera (default) suspended, iPhone Camera Continuity Camera")
    }

    @Test func theFramesPlacedLateAreCountedWithTheLatestArrival() {
        #expect(DetailLine.framesPlacedLate(file: "Camera 1 - BRIO.mov", count: 222, largestLateArrival: 1_492_400_000)
            == "Camera 1 - BRIO.mov: 222 frames arrived after their tick was decided and were placed late, the latest 1492 ms after its capture")
        #expect(DetailLine.framesPlacedLate(file: "c.mov", count: 1, largestLateArrival: 600_000_000)
            == "c.mov: 1 frame arrived after its tick was decided and was placed late, the latest 600 ms after its capture")
    }

    @Test func whatCouldNotBeReadSaysWhy() {
        let facts = ReadyCheckFacts(
            screenRecording: .failed("-3801"), microphoneGranted: nil, screens: .failure(DeviceReadError("no list")),
            audioInputs: .success([]), outputFolder: .unusable("read-only"))
        #expect(DetailLine.facts(facts, resolution: .native, limitCameras: true) == "screen recording failed (-3801); microphone not asked; camera not asked; "
            + "screens cannot be read (no list); audio inputs: none; cameras: none; output folder unusable (read-only)")
    }

    /// Audio only with the microphone alone: the screen permission was not asked.
    @Test func aScreenPermissionNotAskedSaysSo() {
        let facts = ReadyCheckFacts(
            screenRecording: nil, microphoneGranted: true, screens: .success([]),
            audioInputs: .success([]), outputFolder: .unusable("read-only"))
        #expect(DetailLine.facts(facts, resolution: .native, limitCameras: true).hasPrefix("screen recording not asked; microphone granted; "))
    }

    /// The clock drift lines of all audio sources come together, in number order: the system audio (0) first.
    @Test func theClockDriftBlockListsTheSourcesInNumberOrder() {
        let measured = ClockDriftCorrection.Status(clockDriftPpm: -116.12, applied: 0.03494, remaining: 0.00004)
        let notYet = ClockDriftCorrection.Status(clockDriftPpm: nil, applied: 0, remaining: nil)
        let block = DetailLine.clockDriftBlock([
            (number: 4, label: "Audio 4 - MacBook Pro Microphone", status: notYet),
            (number: 1, label: "Audio 1 - CalDigit", status: measured),
            (number: 0, label: "Audio 0 - System", status: notYet),
            (number: 2, label: "Audio 2 - Razer", status: notYet),
        ])
        #expect(block == [
            DetailLine.clockDrift(of: "Audio 0 - System", notYet),
            DetailLine.clockDrift(of: "Audio 1 - CalDigit", measured),
            DetailLine.clockDrift(of: "Audio 2 - Razer", notYet),
            DetailLine.clockDrift(of: "Audio 4 - MacBook Pro Microphone", notYet),
        ])
        #expect(block[0] == "Audio 0 - System: clock drift not measured yet, corrected 0 ms so far")
        #expect(DetailLine.clockDriftBlock([]).isEmpty)
    }

    @Test func anActionNamesTheScreen() {
        let start = ScreenTracker.Action.start(
            uuid: "037036FB-1234-5678-9ABC-DEF012345678", displayID: 2, frameSize: FrameSize(width: 1920, height: 1080),
            number: 2, name: "Wacom One 13T")
        #expect(DetailLine.action(start, names: [:])
            == "start Screen 2 Wacom One 13T (UUID 037036FB…, display ID 2) at 1920×1080")
        #expect(DetailLine.action(.stop(uuid: "037036FB-1234", ending: .disconnected), names: ["037036FB-1234": "Screen 2 Wacom One 13T"])
            == "stop Screen 2 Wacom One 13T (disconnected)")
    }

    @Test func theScreensAsReadAreOneLine() {
        let screens = [
            ConnectedScreen(uuid: "A", displayID: 1, name: "DELL P3421W", pointSize: FrameSize(width: 3440, height: 1440),
                             bounds: ScreenRect(x: 0, y: 0, width: 3440, height: 1440), isMain: true),
            ConnectedScreen(uuid: "B", displayID: 3, name: nil, pointSize: FrameSize(width: 1920, height: 1080),
                             bounds: ScreenRect(x: 3440, y: 0, width: 1920, height: 1080), isMain: false, mirrorsUUID: "A"),
        ]
        #expect(DetailLine.screens(screens)
            == "DELL P3421W 3440×1440 at (0,0) main (display ID 1), unnamed 1920×1080 at (3440,0) mirrors A (display ID 3)")
    }

    @Test func theClockDriftLineSaysWhatTheCorrectionDoes() {
        let label = "Audio 1 - Razer Seiren V3 Mini"
        #expect(DetailLine.clockDrift(of: label, .init(clockDriftPpm: -116.12, applied: 0.034_94, remaining: -0.000_04))
            == "Audio 1 - Razer Seiren V3 Mini: clock drift -116.1 ppm, corrected +34.94 ms so far, 0.04 ms off")
        #expect(DetailLine.clockDrift(of: label, .init(clockDriftPpm: nil, applied: 0.000_2, remaining: 0.000_5))
            == "Audio 1 - Razer Seiren V3 Mini: clock drift not measured yet, corrected +0.20 ms so far, 0.50 ms off")
        #expect(DetailLine.clockDrift(of: "Audio 0 - System", .init(clockDriftPpm: nil, applied: 0, remaining: nil))
            == "Audio 0 - System: clock drift not measured yet, corrected 0 ms so far")
        // Zero is 0, never +0.0 or -0.0.
        #expect(DetailLine.clockDrift(of: "Audio 0 - System", .init(clockDriftPpm: -0.04, applied: -0.000_001, remaining: -0.000_001))
            == "Audio 0 - System: clock drift 0 ppm, corrected 0 ms so far, 0 ms off")
    }

    @Test func aGapLineSaysWhatTheCorrectionKnew() {
        let gap = ClockDriftCorrection.Gap(length: 100_000_000, applied: 0.003_45, drift: 0.000_011_6, latenessBefore: 0.012_3, latenessAfter: 0.012_41)
        #expect(DetailLine.clockDriftGap(of: "Audio 2 - Razer Seiren V3 Mini", gap)
            == "Audio 2 - Razer Seiren V3 Mini: gap of 100.0 ms, clock drift corrected +3.45 ms so far, +0.012 ms for the gap, "
            + "lateness 12.30 ms before, 12.41 ms after")
        let before = ClockDriftCorrection.Gap(length: 50_000_000, applied: 0, drift: 0, latenessBefore: 0.01, latenessAfter: 0.01)
        #expect(DetailLine.clockDriftGap(of: "Audio 0 - System", before)
            == "Audio 0 - System: gap of 50.0 ms, clock drift corrected 0 ms so far, 0 ms for the gap, lateness 10.00 ms before, 10.00 ms after")
    }
}
