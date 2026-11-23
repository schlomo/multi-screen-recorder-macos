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
    private static let iPhone = camera("E", "Anna's iPhone Camera", isContinuity: true)
    private static let iPhoneDefault = camera("F", "Anna's iPhone Desk View Camera", isDefault: true, isContinuity: true)

    /// An iPhone's camera (Continuity Camera, Desk View) is recorded only under All, as a virtual one (D74).
    @Test(arguments: [
        (CameraMode.none, [Bool]([false, false, false, false, false, false])),
        (.defaultCamera, [true, false, false, false, false, false]),
        (.real, [true, true, false, false, false, false]),
        (.allCameras, [true, true, true, true, true, true]),
    ])
    func theCameraModeChoosesTheCameras(mode: CameraMode, recorded: [Bool]) {
        var settings = Settings.defaults
        settings.auto = false
        settings.cameraMode = mode
        #expect([Self.builtIn, Self.usb, Self.obs, Self.virtualDefault, Self.iPhone, Self.iPhoneDefault]
            .map(settings.cameraModeIncludes) == recorded)
    }

    @Test func theNoteUnderTheSliderNamesVirtualAndIPhoneCameras() {
        #expect(CameraMode.leftOutNote == "Virtual cameras and iPhone cameras (Continuity Camera, Desk View) are recorded only"
            + " under All: a virtual camera often carries a copy of a screen or of another camera.")
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
        #expect(camera(formats).chosenFormat(resolution: .native) == format(1920, 1080, 30))
    }

    @Test func aRateRoundingToThirtyCounts() {
        #expect(camera([format(1280, 720, 30), format(1920, 1080, 29.97)]).chosenFormat(resolution: .native) == format(1920, 1080, 29.97))
    }

    @Test func withoutAThirtyFramesFormatTheFastestIsChosenTheLargestOfThose() {
        let formats = [format(3840, 2160, 5), format(640, 480, 25), format(1280, 720, 25), format(1920, 1080, 15)]
        #expect(camera(formats).chosenFormat(resolution: .native) == format(1280, 720, 25))
        #expect(camera([]).chosenFormat(resolution: .native) == nil)
    }

    /// At Native a camera records at most 1920×1080, or 1080×1920 upright: the
    /// owner's BRIO and DJI Osmo Pocket overloaded the USB bus at 4K (D74).
    @Test func atNativeACameraRecordsAtMostFullHD() {
        #expect(RecorderValues.cameraLargestSize == FrameSize(width: 1920, height: 1080))
        let brio = camera([format(4096, 2160, 30), format(3840, 2160, 30), format(1920, 1080, 30), format(1280, 720, 30)])
        #expect(brio.chosenFormat(resolution: .native) == format(1920, 1080, 30))
        #expect(brio.frameSize(resolution: .native) == FrameSize(width: 1920, height: 1080))
        // In its 9:16 mode the Osmo lists the upright picture and a pillarboxed landscape one.
        let osmo = camera([format(1920, 1080, 30), format(1080, 1920, 30), format(3840, 2160, 30)])
        #expect(osmo.chosenFormat(resolution: .native) == format(1080, 1920, 30))
        #expect(osmo.frameSize(resolution: .native) == FrameSize(width: 1080, height: 1920))
        #expect(osmo.chosenFormat(resolution: .p1080) == format(1080, 1920, 30))
        #expect(camera([format(1552, 1552, 30), format(1920, 1080, 30)]).chosenFormat(resolution: .native) == format(1920, 1080, 30))
        #expect(camera([format(2160, 1440, 30)]).frameSize(resolution: .native) == FrameSize(width: 1620, height: 1080))
    }

    /// Each format is fitted into the box as a screen's picture is (a portrait one against the box
    /// turned upright, never enlarged); the largest recorded size wins (D74).
    @Test func theFormatWithTheLargestRecordedSizeIsChosenWhateverItsAspectRatio() {
        let threeByTwo = camera([format(2160, 1440, 30), format(1440, 1080, 30)])
        #expect(threeByTwo.chosenFormat(resolution: .p1080) == format(2160, 1440, 30))
        #expect(threeByTwo.frameSize(resolution: .p1080) == FrameSize(width: 1620, height: 1080))
        let square = camera([format(1552, 1552, 30), format(1080, 1080, 30), format(1920, 1080, 30)])
        #expect(square.chosenFormat(resolution: .p1080) == format(1920, 1080, 30))
        #expect(camera([format(1552, 1552, 30), format(1080, 1080, 30)]).chosenFormat(resolution: .uhd4k) == format(1080, 1080, 30))
        let portrait = camera([format(1080, 1920, 30), format(1280, 720, 30)])
        #expect(portrait.chosenFormat(resolution: .p1080) == format(1080, 1920, 30))
        #expect(portrait.frameSize(resolution: .p1080) == FrameSize(width: 1080, height: 1920))
    }

    /// A small format that fits is not chosen over a larger one that records more once scaled.
    @Test func aLargerFormatScaledIntoTheBoxBeatsASmallerOneThatFits() {
        let faceTime = camera([format(640, 480, 30), format(1920, 1080, 30)])
        #expect(faceTime.chosenFormat(resolution: .p720) == format(1920, 1080, 30))
        #expect(faceTime.frameSize(resolution: .p720) == FrameSize(width: 1280, height: 720))
        let threeByTwo = camera([format(3840, 2160, 30), format(2160, 1440, 30)])
        #expect(threeByTwo.chosenFormat(resolution: .p720) == format(3840, 2160, 30))
        #expect(threeByTwo.frameSize(resolution: .p720) == FrameSize(width: 1280, height: 720))
    }

    /// Of formats that record the same size, the smallest, the least to decode.
    @Test func ofFormatsRecordingTheSameSizeTheSmallestIsChosen() {
        let brio = camera([format(4096, 2160, 30), format(3840, 2160, 30), format(1920, 1080, 30), format(1280, 720, 30)])
        #expect(brio.chosenFormat(resolution: .p1080) == format(1920, 1080, 30))
        #expect(brio.frameSize(resolution: .p1080) == FrameSize(width: 1920, height: 1080))
        #expect(brio.chosenFormat(resolution: .p1440) == format(1920, 1080, 30))
        #expect(brio.frameSize(resolution: .p1440) == FrameSize(width: 1920, height: 1080))
        #expect(brio.chosenFormat(resolution: .uhd4k) == format(1920, 1080, 30))
        let large = camera([format(3840, 2160, 30), format(1920, 1080, 30)])
        #expect(large.chosenFormat(resolution: .p720) == format(1920, 1080, 30))
    }

    /// Of a frame size's variants the slowest that still delivers 30 fps, else the fastest (D74).
    @Test func eachSizeKeepsItsSlowestVariantThatDeliversThirtyFramesPerSecond() {
        let listed = [format(1920, 1080, 60), format(1920, 1080, 30), format(1920, 1080, 29.97), format(1920, 1080, 15),
                      format(3840, 2160, 15), format(3840, 2160, 24), format(1280, 720, 60)]
        #expect(CameraFormat.preferred(listed) == [format(1280, 720, 60), format(1920, 1080, 29.97), format(3840, 2160, 24)])
    }

    @Test func sizesOfTheSamePixelCountAreInAFixedOrder() {
        let landscape = format(1280, 720, 30)
        let portrait = format(720, 1280, 30)
        #expect(CameraFormat.preferred([landscape, portrait]) == [portrait, landscape])
        #expect(CameraFormat.preferred([portrait, landscape]) == [portrait, landscape])
    }

    /// A bound of a range is set as the range's own duration, a rate inside one as 1/30 s.
    @Test func theFrameDurationIsARangesBoundOrOneOverThirty() {
        #expect(CameraFormat.frameDuration(closestTo: 30, in: [5...60]) == .oneOver(30))
        #expect(CameraFormat.frameDuration(closestTo: 30, in: [60...60, 15...30]) == .shortestOf(range: 1))
        #expect(CameraFormat.frameDuration(closestTo: 30, in: [29.97...29.97]) == .shortestOf(range: 0))
        #expect(CameraFormat.frameDuration(closestTo: 30, in: [50...60]) == .longestOf(range: 0))
        #expect(CameraFormat.frameDuration(closestTo: 30, in: [15...25, 50...60]) == .shortestOf(range: 0))
        #expect(CameraFormat.frameDuration(closestTo: 30, in: []) == nil)
    }

    @Test func theFrameRateIsThirtyWhereARangeAllowsItOtherwiseTheClosest() {
        #expect(CameraFormat.frameRate(closestTo: 30, in: [5...60]) == 30)
        #expect(CameraFormat.frameRate(closestTo: 30, in: [30...30, 60...60]) == 30)
        #expect(CameraFormat.frameRate(closestTo: 30, in: [24...24, 60...60]) == 24)
        #expect(CameraFormat.frameRate(closestTo: 30, in: [29.97...29.97]) == 29.97)
        #expect(CameraFormat.frameRate(closestTo: 30, in: [50...60, 15...25]) == 25)
        #expect(CameraFormat.frameRate(closestTo: 30, in: []) == nil)
    }

    @Test func theCamerasBoxIsTheRecordingResolutionsLimitedToFullHD() {
        let fourK = camera([format(3840, 2160, 30)])
        #expect(fourK.frameSize(resolution: .native) == FrameSize(width: 1920, height: 1080))
        #expect(fourK.frameSize(resolution: .uhd4k) == FrameSize(width: 1920, height: 1080))
        #expect(fourK.frameSize(resolution: .p1200) == FrameSize(width: 1920, height: 1080))
        #expect(camera([format(2160, 3840, 30)]).frameSize(resolution: .native) == FrameSize(width: 1080, height: 1920))
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
        step.actions.compactMap { if case .start(let uniqueID, _, _, _, _, _, _) = $0 { uniqueID } else { nil } }
    }

    @Test func atTheStartTheDefaultCameraIsOneAndTheVirtualOneIsLeftOut() {
        var cameras = tracker()
        let step = cameras.begin([Self.obs, Self.usb, Self.builtIn], at: 0)
        #expect(step.actions == [
            .start(uniqueID: "A", format: Self.builtIn.chosenFormat(resolution: .native)!, setsFormat: true, frameSize: FrameSize(width: 1920, height: 1080), number: 1,
                   name: "FaceTime HD Camera", isContinuity: false),
            .start(uniqueID: "B", format: Self.usb.chosenFormat(resolution: .native)!, setsFormat: true, frameSize: FrameSize(width: 1920, height: 1080), number: 2,
                   name: "Logitech BRIO", isContinuity: false),
        ])
        #expect(step.events.isEmpty)
        #expect(cameras.sources.map(\.name) == ["FaceTime HD Camera", "Logitech BRIO"])
    }

    @Test func underAllTheVirtualCameraIsRecordedToo() {
        var cameras = tracker(.allCameras)
        #expect(starts(cameras.begin([Self.builtIn, Self.obs], at: 0)) == ["A", "C"])
    }

    /// The format that records the most at the recording resolution is opened, scaled into its box.
    @Test func theFormatAndTheFileFollowTheRecordingResolution() {
        var cameras = tracker(resolution: .p720)
        var large = Self.builtIn
        large.uniqueID = "L"
        large.isDefault = false
        large.formats = [CameraFormat(size: FrameSize(width: 1920, height: 1080), maxFramesPerSecond: 30)]
        let starts = cameras.begin([Self.builtIn, large], at: 0).actions.compactMap { action -> (CameraFormat, FrameSize)? in
            guard case .start(_, let format, _, let frameSize, _, _, _) = action else { return nil }
            return (format, frameSize)
        }
        #expect(starts.map(\.0.size) == [FrameSize(width: 1920, height: 1080), FrameSize(width: 1920, height: 1080)])
        #expect(starts.map(\.1) == [FrameSize(width: 1280, height: 720), FrameSize(width: 1280, height: 720)])
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
        guard case .start("B", _, _, _, let number, _, _) = started.actions.first else {
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

    @Test func aStallIsAnEventOnceAndItsEndAnotherWithItsLengthWhileTheFileGoesOn() {
        var cameras = tracker()
        _ = cameras.begin([Self.builtIn], at: 0)
        let stalled = cameras.stalled("A", at: 5 * second)
        var stalledEvent = RecordingEvent(at: 5 * second, event: .cameraStalled, camera: "FaceTime HD Camera")
        stalledEvent.errorDetail = CameraTracker.stalledError
        #expect(stalled == CameraTracker.Step(events: [stalledEvent]))
        // A stall loses picture: a failure (D47).
        #expect(stalledEvent.event.isFailure)
        #expect(cameras.sources.first?.state == .stalled(FrameSize(width: 1920, height: 1080)))
        #expect(cameras.stalled("A", at: 6 * second) == CameraTracker.Step())
        let ended = cameras.stallEnded("A", length: 2_950_400_000, at: 6 * second)
        #expect(ended.actions.isEmpty)
        #expect(ended.events.map(\.event) == [.cameraStallEnded])
        #expect(ended.events.first?.length == 2.95)
        #expect(cameras.sources.first?.state == .recording(FrameSize(width: 1920, height: 1080)))
        #expect(cameras.stallEnded("A", length: second, at: 7 * second) == CameraTracker.Step())
    }

    @Test func aStallEndsWithItsStream() {
        var cameras = tracker()
        _ = cameras.begin([Self.builtIn], at: 0)
        _ = cameras.stalled("A", at: 5 * second)
        _ = cameras.streamEnded("A", .streamFailed("no frame for 10 s"), connected: [Self.builtIn], at: 13 * second)
        #expect(cameras.stallEnded("A", length: second, at: 14 * second) == CameraTracker.Step())
        _ = cameras.due(at: 20 * second)
        #expect(cameras.sources.first?.state == .recording(FrameSize(width: 1920, height: 1080)))
    }

    @Test func anIPhoneCameraStartsAsSuch() {
        var cameras = tracker(.allCameras)
        let step = cameras.begin([camera("I", "iPhone Camera", isContinuity: true)], at: 0)
        guard case .start(_, _, _, _, _, _, let isContinuity) = step.actions.first else {
            Issue.record("the iPhone camera did not start")
            return
        }
        #expect(isContinuity)
    }

    /// A suspended camera, such as a laptop's with its lid closed, ends its
    /// file; resumed, it starts after the settle time, never as a newly connected camera.
    @Test func aSuspendedCameraEndsItsFileAndStartsAgainAfterTheSettleTimeWhenResumed() {
        var cameras = tracker()
        _ = cameras.begin([Self.builtIn], at: 0)
        var suspended = Self.builtIn
        suspended.isSuspended = true
        let off = cameras.observe([suspended], at: 10 * second)
        #expect(off.actions == [.stop(uniqueID: "A")])
        #expect(off.events.isEmpty)
        #expect(cameras.sources.first?.state == .notRecorded)
        let on = cameras.observe([Self.builtIn], at: 20 * second)
        #expect(on == CameraTracker.Step())
        #expect(cameras.due(at: 20 * second + second / 2).actions.isEmpty)
        #expect(starts(cameras.due(at: 21 * second)) == ["A"])
    }

    /// A camera another app uses keeps its active format, fitted into the camera's box (D74).
    @Test func aCameraAnotherAppUsesIsRecordedInItsActiveFormatUnchanged() {
        var cameras = tracker()
        var inUse = Self.usb
        inUse.isInUseByAnotherApplication = true
        inUse.activeFormat = CameraFormat(size: FrameSize(width: 640, height: 480), maxFramesPerSecond: 30)
        let step = cameras.begin([inUse], at: 0)
        #expect(step.actions == [.start(
            uniqueID: "B", format: CameraFormat(size: FrameSize(width: 640, height: 480), maxFramesPerSecond: 30), setsFormat: false,
            frameSize: FrameSize(width: 640, height: 480), number: 1, name: "Logitech BRIO", isContinuity: false)])
    }

    /// Another app changing the format to another frame size ends the file and starts one at
    /// the new size, never setting it back, as a screen's frame size change (D30, D74).
    @Test func anotherAppChangingTheFrameSizeStartsANewFile() {
        var cameras = tracker()
        _ = cameras.begin([Self.usb], at: 0)
        var takenOver = Self.usb
        takenOver.isInUseByAnotherApplication = true
        takenOver.activeFormat = CameraFormat(size: FrameSize(width: 1280, height: 720), maxFramesPerSecond: 30)
        let step = cameras.observe([takenOver], at: 5 * second)
        var changed = RecordingEvent(at: 5 * second, event: .cameraFrameSizeChanged, camera: "Logitech BRIO")
        changed.from = [1920, 1080]
        changed.to = [1280, 720]
        #expect(step.events == [changed])
        #expect(step.actions == [
            .stop(uniqueID: "B"),
            .start(uniqueID: "B", format: takenOver.activeFormat!, setsFormat: false, frameSize: FrameSize(width: 1280, height: 720),
                   number: 1, name: "Logitech BRIO", isContinuity: false),
        ])
        #expect(cameras.observe([takenOver], at: 6 * second) == CameraTracker.Step())
    }

    /// Our own format, not yet set when read, and a format of the same frame size change nothing.
    @Test func anActiveFormatOfNoOtherAppOrOfTheSameFrameSizeChangesNothing() {
        var cameras = tracker()
        _ = cameras.begin([Self.usb], at: 0)
        var notYetOpened = Self.usb
        notYetOpened.activeFormat = CameraFormat(size: FrameSize(width: 640, height: 480), maxFramesPerSecond: 30)
        #expect(cameras.observe([notYetOpened], at: 5 * second) == CameraTracker.Step())
        var sameSize = Self.usb
        sameSize.isInUseByAnotherApplication = true
        sameSize.activeFormat = CameraFormat(size: FrameSize(width: 3840, height: 2160), maxFramesPerSecond: 30)
        #expect(cameras.observe([sameSize], at: 6 * second) == CameraTracker.Step())
    }

    @Test func noCameraNoActionNoEvent() {
        var cameras = tracker()
        #expect(cameras.begin([], at: 0) == CameraTracker.Step())
        #expect(cameras.sources.isEmpty)
    }
}

/// A camera with a 1080p format at 30 fps and smaller ones.
func camera(
    _ uniqueID: String, _ name: String, isDefault: Bool = false, isVirtual: Bool = false, isContinuity: Bool = false
) -> CameraInfo {
    CameraInfo(
        uniqueID: uniqueID, name: name, isDefault: isDefault, isVirtual: isVirtual, isContinuity: isContinuity,
        formats: [
            CameraFormat(size: FrameSize(width: 640, height: 480), maxFramesPerSecond: 30),
            CameraFormat(size: FrameSize(width: 1920, height: 1080), maxFramesPerSecond: 30),
        ])
}
