import Testing
@testable import RecorderLogic

@Suite struct SourceDetailsTests {
    static func settings(_ resolution: RecordingResolution, limitCameras: Bool = true) -> Settings {
        var settings = Settings.defaults
        settings.auto = false
        settings.resolution = resolution
        settings.cameraMode = .real
        settings.limitCameras = limitCameras
        return settings
    }

    static let brio = CameraInfo(
        uniqueID: "0x20522000046d085e", name: "Logitech BRIO", isDefault: false, isVirtual: false,
        formats: [
            CameraFormat(size: FrameSize(width: 1920, height: 1080), maxFramesPerSecond: 30, minFramesPerSecond: 5),
            CameraFormat(size: FrameSize(width: 4096, height: 2160), maxFramesPerSecond: 30, minFramesPerSecond: 5),
        ],
        activeFormat: CameraFormat(size: FrameSize(width: 1920, height: 1080), maxFramesPerSecond: 30, minFramesPerSecond: 5),
        transport: .usb,
        offeredFormats: [
            CameraFormat(size: FrameSize(width: 1920, height: 1080), maxFramesPerSecond: 60, minFramesPerSecond: 5),
            CameraFormat(size: FrameSize(width: 4096, height: 2160), maxFramesPerSecond: 30, minFramesPerSecond: 5),
        ],
        usbSpeed: .superSpeed)

    @Test func aCameraTellsItsKindFormatsAndWhyItsFormat() {
        #expect(SourceDetails.camera(label: "Camera 1 - Logitech BRIO", Self.brio, settings: Self.settings(.native)) == """
            Camera 1 - Logitech BRIO
            Kind: USB, unique ID 0x20522000046d085e
            USB link: 5 Gb/s (USB 3)
            Offers: 1920×1080 5–60 fps, 4096×2160 5–30 fps
            Format: 1920×1080 at 30 fps, the largest recorded size, limited to 1080p
            Records at: 1920×1080
            Frame rate: 30 fps, set by the recorder
            In use by another app: no
            Suspended: no
            """)
    }

    @Test func withoutTheLimitAUSB2CameraAboveTheLimitGetsANote() {
        var camera = Self.brio
        camera.usbSpeed = .high
        let text = SourceDetails.camera(label: "Camera 1 - Logitech BRIO", camera, settings: Self.settings(.native, limitCameras: false))
        #expect(text.contains("Format: 4096×2160 at 30 fps, the largest recorded size, 1080p limit off"))
        #expect(text.contains("USB link: 480 Mb/s (USB 2)"))
        #expect(text.hasSuffix("Note: more than 1080p over a USB 2 link (480 Mb/s): the USB bus may overload and the camera stall"))
    }

    @Test func aCameraAnotherAppUsesKeepsItsFormatWithANote() {
        var camera = Self.brio
        camera.isRunningElsewhere = true
        camera.activeFrameRates = 24...30
        let text = SourceDetails.camera(label: "Camera 1 - Logitech BRIO", camera, settings: Self.settings(.native))
        #expect(text.contains("Format: 1920×1080 at 30 fps, kept: another app uses it"))
        #expect(text.contains("Frame rate: as another app set it, now 24–30 fps"))
        #expect(text.contains("In use by another app: yes"))
        #expect(text.hasSuffix("Note: another app uses it: its format and frame rate are that app's, not the recorder's"))
    }

    @Test func aCameraBelowThirtyFramesASecondGetsANote() {
        let slow = CameraInfo(
            uniqueID: "slow", name: "Old Cam", isDefault: false, isVirtual: true,
            formats: [CameraFormat(size: FrameSize(width: 640, height: 480), maxFramesPerSecond: 24, minFramesPerSecond: 24)])
        let text = SourceDetails.camera(label: "Old Cam", slow, settings: Self.settings(.p1080))
        #expect(text.contains("Kind: virtual, unique ID slow"))
        #expect(!text.contains("USB link"))
        #expect(text.contains("Format: 640×480 at 24 fps, the fastest, as no format reaches 30 fps"))
        #expect(text.hasSuffix("Note: runs at 24 fps, below the file's 30: 6 of every 30 frames repeat the one before"))
    }

    @Test func aCameraTiedByOrientationSaysSo() {
        let osmo = CameraInfo(
            uniqueID: "osmo", name: "Osmo", isDefault: false, isVirtual: false,
            formats: [
                CameraFormat(size: FrameSize(width: 1920, height: 1080), maxFramesPerSecond: 30),
                CameraFormat(size: FrameSize(width: 1080, height: 1920), maxFramesPerSecond: 30),
            ],
            activeFormat: CameraFormat(size: FrameSize(width: 1080, height: 1920), maxFramesPerSecond: 30), transport: .usb)
        let text = SourceDetails.camera(label: "Camera 2 - Osmo", osmo, settings: Self.settings(.p1080))
        #expect(text.contains("Format: 1080×1920 at 30 fps, the largest recorded size, turned as the camera's active format"))
        #expect(text.contains("USB link: cannot be read"))
    }

    @Test func atNoneACameraHasNoFormatLines() {
        let text = SourceDetails.camera(label: "Logitech BRIO", Self.brio, settings: Self.settings(.none))
        #expect(!text.contains("Format:"))
        #expect(!text.contains("Records at:"))
    }

    @Test func aScreenTellsItsSizesRefreshRateAndDisplay() {
        #expect(SourceDetails.screen(
            label: "Screen 1 - Built-in Retina Display", looksLike: FrameSize(width: 1728, height: 1117),
            drawnAt: FrameSize(width: 3456, height: 2234), recordsAt: FrameSize(width: 1728, height: 1116), refreshRate: 120,
            displayID: 1, isMain: true) == """
            Screen 1 - Built-in Retina Display
            Looks like: 1728×1117
            Drawn at: 3456×2234
            Records at: 1728×1116
            Refresh rate: 120 Hz
            Colour: recorded as BT.709 (SDR), HEVC 8-bit
            Display ID: 1
            Main screen: yes
            """)
    }

    @Test func anAudioInputTellsItsFormatVolumeAndUID() {
        let input = AudioInputInfo(
            name: "Razer Seiren V3 Mini", channelCount: .success(1), isDefault: true, transport: .usb, uid: "AppleUSBAudioEngine:Razer:1",
            sampleRate: 48_000, inputVolume: InputVolumeReading(value: 0.75, isSettable: true))
        #expect(SourceDetails.audioInput(label: "Audio 1 - Razer Seiren V3 Mini (default)", input) == """
            Audio 1 - Razer Seiren V3 Mini (default)
            Channels: 1
            Sample rate: 48 kHz, recorded at 48 kHz
            Connection: USB
            Input volume: 75 %, can be set
            Default microphone: yes
            UID: AppleUSBAudioEngine:Razer:1
            Records as: a mono AAC-LC track per channel, 128 kbit/s each
            """)
    }

    @Test func anAudioInputWithoutVolumeOrReadableFactsSaysSo() {
        let input = AudioInputInfo(
            name: "Mystery", channelCount: .failure(DeviceReadError("no answer")), isDefault: false, transport: .unreadable)
        let text = SourceDetails.audioInput(label: "Mystery", input)
        #expect(text.contains("Channels: cannot be read (no answer)"))
        #expect(text.contains("Sample rate: cannot be read, recorded at 48 kHz"))
        #expect(text.contains("Connection: cannot be read"))
        #expect(text.contains("Input volume: none"))
        #expect(text.contains("UID: cannot be read"))
    }

    @Test func theSystemAudioTellsWhatItCaptures() {
        #expect(SourceDetails.systemAudio(label: "Audio 0 - System") == """
            Audio 0 - System
            Captures: the sound the Mac plays, Multi Screen Recorder's own left out, through ScreenCaptureKit on the main screen
            Records as: a stereo AAC-LC track, 48 kHz, 192 kbit/s
            """)
    }

    @Test func theLiveFactsTellLatenessStallAndClockDrift() {
        #expect(SourceDetails.live(lateness: (repeated: 3, placedLate: 1), isStalled: false) == [
            "This file so far: 3 frames repeated for lateness, 1 placed late", "Stalled: no",
        ])
        #expect(SourceDetails.live(clockDrift: ClockDriftCorrection.Status(clockDriftPpm: -116.1, applied: 0.03494, remaining: nil)) == [
            "Clock drift: -116.1 ppm, corrected +34.94 ms so far",
        ])
    }

    @Test func everyRowsDetailsStartWithItsLabel() {
        let shown = WhatWillBeRecorded(
            settings: Self.settings(.native), screens: .success(DesignExample.screens),
            audioInputs: .success([AudioInputInfo(name: "Mic", channelCount: 1, isDefault: true, uid: "mic")]),
            cameras: [Self.brio], outputFolder: nil)
        let rows = shown.screenRows + shown.cameraRows + shown.audioRows
        #expect(rows.count == 5)
        for row in rows { #expect(row.details.hasPrefix(row.source!.text + "\n")) }
    }
}
