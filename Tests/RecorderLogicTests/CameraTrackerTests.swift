import Testing
@testable import RecorderLogic

@Suite struct CameraModeTests {
    @Test func theFourStepsInSliderOrderWithTheirWords() {
        #expect(CameraMode.allCases.map(\.rawValue) == ["none", "default-camera", "real", "all-cameras"])
        #expect(CameraMode.allCases.map(\.shownName) == ["None", "Default camera", "All real", "All"])
    }

    @Test func theSliderIndexRoundTrips() {
        for (index, mode) in CameraMode.allCases.enumerated() {
            #expect(mode.sliderIndex == Double(index))
        }
        #expect(CameraMode.none.choosing(sliderPosition: 2) == .real)
        #expect(CameraMode.real.choosing(sliderPosition: 2) == nil)
    }

    @Test func autoModeRecordsAllRealCamerasAndIsTheSlidersDefault() {
        #expect(Settings.autoCameraMode == .real)
        #expect(Settings.defaults.cameraMode == .real)
        var settings = Settings.defaults
        settings.cameraMode = .none
        #expect(settings.effectiveCameraMode == .real)
        settings.auto = false
        #expect(settings.effectiveCameraMode == CameraMode.none)
    }

    private static let builtIn = camera("A", "FaceTime HD Camera", isDefault: true)
    private static let usb = camera("B", "Logitech BRIO")
    private static let obs = camera("C", "OBS Virtual Camera", isVirtual: true)
    private static let virtualDefault = camera("D", "Virtual Default", isDefault: true, isVirtual: true)

    @Test(arguments: [
        (CameraMode.none, [Bool]([false, false, false, false])),
        (.defaultCamera, [true, false, false, false]),
        (.real, [true, true, false, false]),
        (.allCameras, [true, true, true, true]),
    ])
    func theCameraModeChoosesTheCameras(mode: CameraMode, recorded: [Bool]) {
        var settings = Settings.defaults
        settings.auto = false
        settings.cameraMode = mode
        #expect([Self.builtIn, Self.usb, Self.obs, Self.virtualDefault].map(settings.cameraModeIncludes) == recorded)
    }

    @Test func theRecordingResolutionNoneRecordsNoCamera() {
        var settings = Settings.defaults
        settings.auto = false
        settings.resolution = .none
        settings.cameraMode = .allCameras
        #expect(!CameraTracker.records(Self.builtIn, settings: settings))
    }

    /// A suspended camera, such as a laptop's with its lid closed, delivers no picture (D74).
    @Test func aSuspendedCameraIsNotRecorded() {
        var camera = Self.builtIn
        camera.isSuspended = true
        #expect(!CameraTracker.records(camera, settings: .defaults))
    }

    @Test func aCameraWithoutAFormatIsNotRecorded() {
        var camera = Self.builtIn
        camera.formats = []
        #expect(!CameraTracker.records(camera, settings: .defaults))
        #expect(CameraTracker.records(Self.builtIn, settings: .defaults))
    }
}

@Suite struct CameraFormatTests {
    private func format(_ width: Int, _ height: Int, _ fps: Double) -> CameraFormat {
        CameraFormat(size: FrameSize(width: width, height: height), maxFramesPerSecond: fps)
    }

    private func camera(_ formats: [CameraFormat]) -> CameraInfo {
        CameraInfo(uniqueID: "X", name: "X", isDefault: true, isVirtual: false, formats: formats)
    }

    @Test func theLargestFormatThatDeliversThirtyFramesPerSecondIsChosen() {
        let formats = [format(640, 480, 30), format(3840, 2160, 15), format(1920, 1080, 30), format(1280, 720, 60)]
        #expect(camera(formats).chosenFormat == format(1920, 1080, 30))
    }

    @Test func aRateRoundingToThirtyCounts() {
        #expect(camera([format(1280, 720, 30), format(1920, 1080, 29.97)]).chosenFormat == format(1920, 1080, 29.97))
    }

    @Test func withoutAThirtyFramesFormatTheFastestIsChosenTheLargestOfThose() {
        let formats = [format(3840, 2160, 5), format(640, 480, 25), format(1280, 720, 25), format(1920, 1080, 15)]
        #expect(camera(formats).chosenFormat == format(1280, 720, 25))
        #expect(camera([]).chosenFormat == nil)
    }

    @Test func theRecordingResolutionCapsTheFrameSizeAsForAScreen() {
        let fourK = camera([format(3840, 2160, 30)])
        #expect(fourK.frameSize(resolution: .native) == FrameSize(width: 3840, height: 2160))
        #expect(fourK.frameSize(resolution: .p1080) == FrameSize(width: 1920, height: 1080))
        #expect(fourK.frameSize(resolution: .p720) == FrameSize(width: 1280, height: 720))
        #expect(camera([format(640, 480, 30)]).frameSize(resolution: .p1080) == FrameSize(width: 640, height: 480))
    }
}

@Suite struct CameraTrackerTests {
    private let second: Int64 = 1_000_000_000
    private static let builtIn = camera("A", "FaceTime HD Camera", isDefault: true)
    private static let usb = camera("B", "Logitech BRIO")
    private static let obs = camera("C", "OBS Virtual Camera", isVirtual: true)

    private func tracker(_ mode: CameraMode = .real, resolution: RecordingResolution = .native) -> CameraTracker {
        var settings = Settings.defaults
        settings.auto = false
        settings.resolution = resolution
        settings.cameraMode = mode
        return CameraTracker(settings: settings)
    }

    private func starts(_ step: CameraTracker.Step) -> [String] {
        step.actions.compactMap { if case .start(let uniqueID, _, _, _, _) = $0 { uniqueID } else { nil } }
    }

    @Test func atTheStartTheDefaultCameraIsOneAndTheVirtualOneIsLeftOut() {
        var cameras = tracker()
        let step = cameras.begin([Self.obs, Self.usb, Self.builtIn], at: 0)
        #expect(step.actions == [
            .start(uniqueID: "A", format: Self.builtIn.chosenFormat!, frameSize: FrameSize(width: 1920, height: 1080), number: 1,
                   name: "FaceTime HD Camera"),
            .start(uniqueID: "B", format: Self.usb.chosenFormat!, frameSize: FrameSize(width: 1920, height: 1080), number: 2,
                   name: "Logitech BRIO"),
        ])
        #expect(step.events.isEmpty)
        #expect(cameras.sources.map(\.name) == ["FaceTime HD Camera", "Logitech BRIO"])
    }

    @Test func underAllTheVirtualCameraIsRecordedToo() {
        var cameras = tracker(.allCameras)
        #expect(starts(cameras.begin([Self.builtIn, Self.obs], at: 0)) == ["A", "C"])
    }

    @Test func theFileIsCappedByTheRecordingResolution() {
        var cameras = tracker(resolution: .p720)
        let step = cameras.begin([Self.builtIn], at: 0)
        guard case .start(_, _, let frameSize, _, _) = step.actions.first else {
            Issue.record("no start")
            return
        }
        #expect(frameSize == FrameSize(width: 1280, height: 720))
    }

    @Test func aCameraThatGoesEndsItsFileAtOnceAndComesBackAfterTheSettleTimeWithItsNumber() {
        var cameras = tracker()
        _ = cameras.begin([Self.builtIn, Self.usb], at: 0)
        let gone = cameras.observe([Self.builtIn], at: 10 * second)
        #expect(gone.actions == [.stop(uniqueID: "B")])
        #expect(gone.events == [RecordingEvent(at: 10 * second, event: .cameraDisconnected, camera: "Logitech BRIO")])
        #expect(cameras.sources.map(\.state) == [.recording(FrameSize(width: 1920, height: 1080)), .disconnected])

        let back = cameras.observe([Self.builtIn, Self.usb], at: 20 * second)
        #expect(back.actions.isEmpty)
        #expect(back.events == [RecordingEvent(at: 20 * second, event: .cameraConnected, camera: "Logitech BRIO")])
        #expect(cameras.due(at: 20 * second + second / 2).actions.isEmpty)
        #expect(cameras.nextDueTime() == 21 * second)
        let started = cameras.due(at: 21 * second)
        guard case .start("B", _, _, let number, _) = started.actions.first else {
            Issue.record("B did not start")
            return
        }
        #expect(number == 2)
    }

    @Test func aNewCameraGetsAnEventAndTheNextNumberAfterTheSettleTime() {
        var cameras = tracker()
        _ = cameras.begin([Self.builtIn], at: 0)
        let step = cameras.observe([Self.builtIn, Self.usb], at: 5 * second)
        #expect(step.events == [RecordingEvent(at: 5 * second, event: .cameraConnected, camera: "Logitech BRIO")])
        #expect(step.actions.isEmpty)
        #expect(starts(cameras.due(at: 6 * second)) == ["B"])
    }

    @Test func aVirtualCameraThatAppearsUnderAllRealIsNotTracked() {
        var cameras = tracker()
        _ = cameras.begin([Self.builtIn], at: 0)
        #expect(cameras.observe([Self.builtIn, Self.obs], at: 5 * second) == CameraTracker.Step())
        #expect(cameras.sources.count == 1)
    }

    @Test func underDefaultCameraANewDefaultTakesOverWithAnEvent() {
        var cameras = tracker(.defaultCamera)
        #expect(starts(cameras.begin([Self.builtIn, Self.usb], at: 0)) == ["A"])
        var oldDefault = Self.builtIn
        oldDefault.isDefault = false
        var newDefault = Self.usb
        newDefault.isDefault = true
        let changed = cameras.observe([oldDefault, newDefault], at: 5 * second)
        #expect(changed.actions == [.stop(uniqueID: "A")])
        var event = RecordingEvent(at: 5 * second, event: .defaultCameraChanged)
        event.from = "FaceTime HD Camera"
        event.to = "Logitech BRIO"
        #expect(changed.events == [event])
        #expect(starts(cameras.due(at: 6 * second)) == ["B"])
        #expect(cameras.sources.map(\.state) == [.notRecorded, .recording(FrameSize(width: 1920, height: 1080))])
    }

    @Test func aFailedStreamIsAFailureEventAndRestartsAfterTheBackOff() {
        var cameras = tracker()
        _ = cameras.begin([Self.builtIn], at: 0)
        let failed = cameras.streamEnded("A", .streamFailed("the stand-in failed"), connected: [Self.builtIn], at: 3 * second)
        #expect(failed.events.map(\.event) == [.cameraStreamFailed])
        #expect(failed.events.first?.camera == "FaceTime HD Camera")
        #expect(failed.events.first?.event.isFailure == true)
        #expect(cameras.sources.first?.state == .failedRetrying)
        #expect(cameras.due(at: 3 * second).actions.isEmpty)
        #expect(starts(cameras.due(at: 3 * second + RecorderValues.firstRestartDelay.nanoseconds)) == ["A"])
    }

    @Test func aCameraGoneEndsItsStreamOnceWithoutAFailureThenAgainAsOne() {
        var cameras = tracker()
        _ = cameras.begin([Self.builtIn], at: 0)
        let first = cameras.streamEnded("A", .captureSourceGone, connected: [Self.builtIn], at: 2 * second)
        #expect(first.events.isEmpty)
        _ = cameras.due(at: 3 * second)
        let again = cameras.streamEnded("A", .captureSourceGone, connected: [Self.builtIn], at: 4 * second)
        #expect(again.events.map(\.event) == [.cameraStreamFailed])
        #expect(again.events.first?.errorDetail == CameraTracker.captureSourceGoneAgain)
    }

    @Test func aWriterThatFellBehindIsAFailureEvent() {
        var cameras = tracker()
        _ = cameras.begin([Self.builtIn], at: 0)
        let behind = cameras.streamEnded("A", .writerFellBehind, connected: [Self.builtIn], at: 2 * second)
        #expect(behind.events.map(\.event) == [.cameraFileWriterFellBehind])
        #expect(behind.events.first?.event.isFailure == true)
    }

    @Test func aFullDiskWaitsForRoom() {
        var cameras = tracker()
        _ = cameras.begin([Self.builtIn], at: 0)
        _ = cameras.streamEnded("A", .diskFull, connected: [Self.builtIn], at: 2 * second)
        #expect(cameras.isWaitingForRoom)
        #expect(cameras.due(at: 10 * second).actions.isEmpty)
        cameras.roomAgain()
        #expect(starts(cameras.due(at: 10 * second)) == ["A"])
    }

    @Test func sleepEndsEveryFileWithoutAnEventAndWakeStartsAgainAfterTheSettleTime() {
        var cameras = tracker()
        _ = cameras.begin([Self.builtIn], at: 0)
        #expect(cameras.sleep() == [.stop(uniqueID: "A")])
        #expect(cameras.sources.first?.state == .asleep)
        #expect(cameras.due(at: 5 * second).actions.isEmpty)
        let woke = cameras.wake([Self.builtIn], at: 10 * second)
        #expect(woke == CameraTracker.Step())
        #expect(cameras.due(at: 10 * second).actions.isEmpty)
        #expect(starts(cameras.due(at: 11 * second)) == ["A"])
    }

    @Test func stopEndsEveryFile() {
        var cameras = tracker()
        _ = cameras.begin([Self.builtIn, Self.usb], at: 0)
        #expect(cameras.stopAll() == [.stop(uniqueID: "A"), .stop(uniqueID: "B")])
        #expect(cameras.nextDueTime() == nil)
    }

    @Test func noCameraNoActionNoEvent() {
        var cameras = tracker()
        #expect(cameras.begin([], at: 0) == CameraTracker.Step())
        #expect(cameras.sources.isEmpty)
    }
}

/// A camera with a 1080p format at 30 fps and smaller ones.
func camera(_ uniqueID: String, _ name: String, isDefault: Bool = false, isVirtual: Bool = false) -> CameraInfo {
    CameraInfo(
        uniqueID: uniqueID, name: name, isDefault: isDefault, isVirtual: isVirtual,
        formats: [
            CameraFormat(size: FrameSize(width: 640, height: 480), maxFramesPerSecond: 30),
            CameraFormat(size: FrameSize(width: 1920, height: 1080), maxFramesPerSecond: 30),
        ])
}
