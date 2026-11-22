import CoreMedia
import Foundation
import RecorderLogic
import Synchronization
import Testing
@testable import RecorderCore

extension GlobalRecordingLog {
    /// A recorder's wiring, audio only with one stand-in audio input and its
    /// stand-in input volume, or with stand-in cameras and the Camera
    /// permission: what reaches the observer, the recording manifest and the
    /// status window. Nested in `GlobalRecordingLog`: a recorder
    /// writes the one recording log of the process.
    @MainActor
    @Suite final class RecorderTests {
        final class Observer: RecorderObserver {
            var problems: [(problem: RecordingProblem, ofAnEvent: Bool)] = []
            var eventLines: [(line: String, isFailure: Bool)] = []

            func recorder(_ recorder: Recorder, lowDiskSpace: Bool) {}
            func recorder(_ recorder: Recorder, screenShowsAnotherScreensPicture screen: String?) {}
            func recorder(_ recorder: Recorder, problem: RecordingProblem, ofAnEvent: Bool) {
                problems.append((problem, ofAnEvent))
            }
            func recorder(_ recorder: Recorder, eventLine: String, isFailure: Bool) {
                eventLines.append((eventLine, isFailure))
            }
        }

        final class StandInVolume: InputVolumeControl, @unchecked Sendable {
            struct State {
                var volume = 0.42
                var isSettable = true
                var refusesToSet = false
                var set: [Double] = []
                var changed: (@Sendable () -> Void)?
                var cancelled = false
            }

            let state = Mutex(State())

            var isSettable: Bool { state.withLock { $0.isSettable } }
            func read() -> Double? { state.withLock { $0.volume } }

            func set(_ volume: Double) throws(InputVolumeError) {
                let refused = state.withLock { state in
                    guard !state.refusesToSet else { return true }
                    state.set.append(volume)
                    state.volume = volume
                    return false
                }
                if refused { throw InputVolumeError("Core Audio refused the input volume of the stand-in") }
            }

            func watch(_ changed: @escaping @Sendable () -> Void) throws(InputVolumeError) {
                state.withLock { $0.changed = changed }
            }

            func cancel() { state.withLock { $0.cancelled = true } }

            /// A knob or another app changed it: Core Audio calls back.
            func change(to volume: Double) {
                let changed = state.withLock { state in
                    state.volume = volume
                    return state.changed
                }
                changed?()
            }
        }

        private let uid = "StandInMicrophone"
        private let name = "Stand-in microphone"
        private let home: URL
        private let observer = Observer()
        private let volume = StandInVolume()
        /// Every source the recorder opened, in order: a restart opens a new one.
        final class OpenedSources: Sendable {
            let list = Mutex<[AudioCaptureTests.StandInSource]>([])
            var count: Int { list.withLock { $0.count } }
            var last: AudioCaptureTests.StandInSource { list.withLock { $0.last! } }
        }

        private let sources = OpenedSources()
        final class Switch: Sendable {
            let isOn = Mutex(true)
        }

        private let screensReadable = Switch()
        private var recorder: Recorder!

        /// A camera's frames, sent by the test with the host time of now.
        final class StandInCamera: CameraFrameSource, @unchecked Sendable {
            let frameSize: FrameSize
            private let state = Mutex<(
                queue: DispatchQueue?, deliver: (@Sendable (CMSampleBuffer) -> Void)?,
                ended: (@Sendable (VideoStreamEnd) -> Void)?, stopped: Bool
            )>((nil, nil, nil, false))

            init(frameSize: FrameSize) {
                self.frameSize = frameSize
            }

            var isStopped: Bool { state.withLock { $0.stopped } }

            func start(
                queue: DispatchQueue, deliver: @escaping @Sendable (CMSampleBuffer) -> Void,
                ended: @escaping @Sendable (VideoStreamEnd) -> Void
            ) {
                state.withLock { $0 = (queue, deliver, ended, false) }
            }

            func stop() async {
                state.withLock { $0.stopped = true }
            }

            /// A decoded frame captured `ago` before now, handed to the capture on its queue.
            func sendFrame(capturedAgo ago: Duration = .zero) throws {
                var pixelBuffer: CVPixelBuffer?
                CVPixelBufferCreate(
                    nil, frameSize.width, frameSize.height, kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
                    [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary, &pixelBuffer)
                let picture = try #require(pixelBuffer)
                var format: CMVideoFormatDescription?
                CMVideoFormatDescriptionCreateForImageBuffer(allocator: nil, imageBuffer: picture, formatDescriptionOut: &format)
                var timing = Self.timingNow(ago: ago)
                var buffer: CMSampleBuffer?
                CMSampleBufferCreateReadyWithImageBuffer(
                    allocator: nil, imageBuffer: picture, formatDescription: try #require(format), sampleTiming: &timing,
                    sampleBufferOut: &buffer)
                deliver(try #require(buffer))
            }

            /// A frame without a decoded picture, as a camera's compressed stream would come.
            func sendFrameWithoutPicture() throws {
                var timing = Self.timingNow()
                var buffer: CMSampleBuffer?
                CMSampleBufferCreate(
                    allocator: nil, dataBuffer: nil, dataReady: true, makeDataReadyCallback: nil, refcon: nil, formatDescription: nil,
                    sampleCount: 1, sampleTimingEntryCount: 1, sampleTimingArray: &timing, sampleSizeEntryCount: 0, sampleSizeArray: nil,
                    sampleBufferOut: &buffer)
                deliver(try #require(buffer))
            }

            func lose(_ end: VideoStreamEnd) {
                state.withLock { $0.ended }?(end)
            }

            private func deliver(_ buffer: CMSampleBuffer) {
                let (queue, deliver) = state.withLock { ($0.queue, $0.deliver) }
                queue?.sync { deliver?(buffer) }
            }

            private static func timingNow(ago: Duration = .zero) -> CMSampleTimingInfo {
                CMSampleTimingInfo(
                    duration: CMTime(value: 1, timescale: 30),
                    presentationTimeStamp: CMTime(value: CMTimeValue(readClocks().host) - ago.nanoseconds, timescale: 1_000_000_000),
                    decodeTimeStamp: .invalid)
            }
        }

        /// The cameras connected, the Camera permission and what the recorder asked of them.
        final class CameraStandIns: Sendable {
            let connected = Mutex<[CameraInfo]>([])
            let permission = Mutex(CameraPermission.granted)
            /// What the request answers: the permission after it.
            let answer = Mutex(CameraPermission.granted)
            let requests = Mutex(0)
            let reads = Mutex(0)
            let opened = Mutex<[StandInCamera]>([])
            var last: StandInCamera? { opened.withLock { $0.last } }
        }

        private let cameras = CameraStandIns()
        private static let camera = CameraInfo(
            uniqueID: "StandInCamera", name: "Stand-in camera", isDefault: true, isVirtual: false,
            formats: [CameraFormat(size: FrameSize(width: 320, height: 180), maxFramesPerSecond: 30)])
        private let samplesPerBuffer = 1600

        init() throws {
            home = FileManager.default.temporaryDirectory.appending(path: "RecorderTests-\(UUID().uuidString)", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        }

        deinit {
            try? FileManager.default.removeItem(at: home)
        }

        private func start(
            readsScreens: Bool = false, cameraMode: CameraMode = .none, cameraFrameWatch: CameraFrameWatch = CameraFrameWatch()
        ) throws {
            var settings = Settings.defaults
            settings.auto = false
            settings.resolution = readsScreens || cameraMode != .none ? .p1080 : RecordingResolution.none
            settings.cameraMode = cameraMode
            settings.audioMode = .defaultMicrophone
            settings.systemAudio = false
            settings.outputFolder = home.path(percentEncoded: false)
            let input = AudioInputInfo(name: name, channelCount: 1, isDefault: true, transport: .usb, uid: uid)
            let sources = sources
            let volume = volume
            let screensReadable = screensReadable
            let cameras = cameras
            let devices = RecorderDevices(
                screens: { () throws(DeviceReadError) -> [ConnectedScreen] in
                    if screensReadable.isOn.withLock({ $0 }) { return [] }
                    throw DeviceReadError("the stand-in's screens cannot be read")
                },
                audioInputs: { [input] },
                audioInputSource: { _ in
                    let source = AudioCaptureTests.StandInSource()
                    sources.list.withLock { $0.append(source) }
                    return source
                },
                inputVolume: { _, _ in volume },
                cameras: {
                    cameras.reads.withLock { $0 += 1 }
                    return cameras.connected.withLock { $0 }
                },
                cameraSource: { _, format, _ in
                    let camera = StandInCamera(frameSize: format.size)
                    cameras.opened.withLock { $0.append(camera) }
                    return camera
                },
                cameraPermission: { cameras.permission.withLock { $0 } },
                requestCameraPermission: {
                    cameras.requests.withLock { $0 += 1 }
                    let answer = cameras.answer.withLock { $0 }
                    cameras.permission.withLock { $0 = answer }
                    return answer == .granted
                })
            let facts = ReadyCheckFacts(
                screenRecording: nil, microphoneGranted: true, screens: .success([]), audioInputs: .success([input]),
                outputFolder: .unusable("not probed by the tests"))
            recorder = try Recorder(
                settings: settings, homeFolder: home, app: "Multi Screen Recorder (tests)", readyCheckFacts: facts, observer: observer,
                devices: devices, cameraFrameWatch: cameraFrameWatch)
        }

        private var source: AudioCaptureTests.StandInSource { sources.last }

        /// Buffers of `value` throughout, the first `start` buffers after now.
        private func send(_ value: Float, buffers: Int, after start: Int = 0) throws {
            let now = readClocks().host
            for index in 0..<buffers {
                let nanoseconds = Int64(start + index) * Int64(samplesPerBuffer) * 1_000_000_000 / Int64(RecorderValues.audioSampleRate)
                let samples = [[Float](repeating: value, count: samplesPerBuffer)]
                let time = CMTime(value: CMTimeValue(now) + nanoseconds, timescale: 1_000_000_000)
                source.send(try pcmSample(samples[...], format: pcmFormat(channels: 1), at: time))
            }
        }

        /// Waits on the main actor, so the recorder's tasks run, until `condition` holds, for at most 5 s.
        private func wait(_ what: String, until condition: () -> Bool) async throws {
            for _ in 0..<500 {
                if condition() { return }
                try await Task.sleep(for: .milliseconds(10))
            }
            Issue.record("timed out waiting for \(what)")
            throw CancellationError()
        }

        private func manifestOnDisk() throws -> RecordingManifest {
            try RecordingManifest(json: Data(contentsOf: recorder.folder.appending(path: RecordingNames.manifest)))
        }

        private func stop() async -> RecordingSummary {
            await recorder.stop()
        }

        // MARK: A failure told once (D65)

        @Test func aCaptureFailureIsToldOnceByItsEvent() async throws {
            try start()
            source.lose(.captureFailed("the stand-in failed"))
            try await wait("the problem") { !observer.problems.isEmpty }
            #expect(observer.problems.count == 1)
            #expect(observer.problems.first?.ofAnEvent == true)
            let failures = observer.eventLines.filter(\.isFailure)
            #expect(failures.count == 1)
            #expect(failures.first?.line.contains("audio input failed: \(name)") == true)
            let manifest = try manifestOnDisk()
            #expect(manifest.events.map(\.event) == [.audioInputFailed])
            #expect(manifest.problems.count == 1)
            _ = await stop()
        }

        @Test func aRepeatedFailureIsCountedAndTheCountToldAtStop() async throws {
            try start()
            source.lose(.captureFailed("the stand-in failed"))
            try await wait("the restart") { sources.count == 2 }
            source.lose(.captureFailed("the stand-in failed"))
            try await wait("the second failure") { (try? manifestOnDisk().events.count) == 2 }
            #expect(observer.eventLines.filter(\.isFailure).count == 1)
            #expect(observer.problems.count == 1)
            _ = await stop()
            let counted = observer.eventLines.filter { $0.line.contains("audio input failed repeated 1 time since") }
            #expect(counted.count == 1)
            #expect(counted.first?.isFailure == true)
        }

        // MARK: Sleep and wake

        @Test func theAudioInputsRestartAtAWakeWhoseScreensCannotBeRead() async throws {
            try start(readsScreens: true)
            #expect(sources.count == 1)
            recorder.willSleep()
            screensReadable.isOn.withLock { $0 = false }
            recorder.didWake()
            try await wait("the audio input's restart") { sources.count == 2 }
            #expect(observer.problems.map(\.problem.problem) == ["The screens cannot be read"])
            #expect(try manifestOnDisk().events.map(\.event) == [.sleep, .wake])
            _ = await stop()
        }

        // MARK: Cameras (D74)

        /// Sends a frame every 30 ms until `condition` holds, for at most 5 s.
        private func sendFrames(_ camera: StandInCamera, until what: String, _ condition: () -> Bool) async throws {
            try await wait(what) {
                try? camera.sendFrame()
                return condition()
            }
        }

        @Test func aCameraThatAppearsAndVanishesStartsAndEndsItsCameraFileWithEvents() async throws {
            try start(cameraMode: .real)
            #expect(cameras.opened.withLock { $0.isEmpty })
            cameras.connected.withLock { $0 = [Self.camera] }
            recorder.camerasChanged()
            try await wait("the camera's start after the settle time") { cameras.last != nil }
            let camera = try #require(cameras.last)
            try await sendFrames(camera, until: "the camera file") { (try? manifestOnDisk().cameraFiles.count) == 1 }
            let started = try #require(try manifestOnDisk().cameraFiles.first)
            #expect(started.name.hasSuffix(" Camera 1 - Stand-in camera.mov"))
            #expect(started.camera == "Stand-in camera")
            #expect(started.cameraUniqueID == "StandInCamera")
            #expect(started.frameSize == [320, 180])
            #expect(started.guideTracks == ["Audio inputs"])
            #expect(started.state == .recording)
            #expect(recorder.status().rows.contains { $0.source == .camera(1, name: "Stand-in camera") && $0.state == "recording" })

            cameras.connected.withLock { $0 = [] }
            recorder.camerasChanged()
            try await wait("the camera file's end") { (try? manifestOnDisk().cameraFiles.first?.state) == .finalized }
            #expect(camera.isStopped)
            let summary = await stop()
            #expect(summary.manifest.events.map(\.event) == [.cameraConnected, .cameraDisconnected])
            #expect(summary.manifest.events.map(\.camera) == ["Stand-in camera", "Stand-in camera"])
            #expect(summary.manifest.settings.cameraMode == "real")
            #expect(summary.manifest.result == .ok)
            #expect(FileManager.default.fileExists(atPath: recorder.folder.appending(path: started.name).path(percentEncoded: false)))
            let timeline = try String(contentsOf: recorder.folder.appending(
                path: ResolveTimeline.fileName(forFolder: recorder.folder.lastPathComponent)), encoding: .utf8)
            #expect(timeline.contains(#""name": "Camera 1 - Stand-in camera""#))
        }

        @Test func aCameraThatFailsIsAFailureToldOnceAndStartsAgain() async throws {
            cameras.connected.withLock { $0 = [Self.camera] }
            try start(cameraMode: .real)
            let first = try #require(cameras.last)
            try await sendFrames(first, until: "the camera file") { (try? manifestOnDisk().cameraFiles.count) == 1 }
            first.lose(.streamFailed("the stand-in failed"))
            try await wait("the problem") { !observer.problems.isEmpty }
            #expect(observer.problems.count == 1)
            #expect(observer.problems.first?.ofAnEvent == true)
            #expect(observer.problems.first?.problem.problem == "Camera Stand-in camera")
            #expect(try manifestOnDisk().events.map(\.event) == [.cameraStreamFailed])
            try await wait("the restart") { cameras.opened.withLock { $0.count } == 2 }
            let summary = await stop()
            #expect(summary.manifest.result == .problems)
            #expect(summary.manifest.cameraFiles.map(\.state) == [.finalized])
        }

        @Test func stopFinalizesTheCameraFileItRecords() async throws {
            cameras.connected.withLock { $0 = [Self.camera] }
            try start(cameraMode: .real)
            let camera = try #require(cameras.last)
            try await sendFrames(camera, until: "the camera file") { (try? manifestOnDisk().cameraFiles.count) == 1 }
            let summary = await stop()
            #expect(camera.isStopped)
            #expect(summary.manifest.cameraFiles.map(\.state) == [.finalized])
            #expect(summary.manifest.cameraFiles.first?.end != nil)
            #expect(summary.manifest.result == .ok)
        }

        @Test func atSleepTheCameraFileEndsAndAtWakeANewOneStarts() async throws {
            cameras.connected.withLock { $0 = [Self.camera] }
            try start(cameraMode: .real)
            let first = try #require(cameras.last)
            try await sendFrames(first, until: "the camera file") { (try? manifestOnDisk().cameraFiles.count) == 1 }
            recorder.willSleep()
            try await wait("the file's end at sleep") { (try? manifestOnDisk().cameraFiles.first?.state) == .finalized }
            #expect(first.isStopped)
            recorder.didWake()
            try await wait("the camera's start after the settle time") { cameras.opened.withLock { $0.count } == 2 }
            let second = try #require(cameras.last)
            try await sendFrames(second, until: "the second camera file") { (try? manifestOnDisk().cameraFiles.count) == 2 }
            let summary = await stop()
            #expect(summary.manifest.events.map(\.event) == [.sleep, .wake])
            #expect(summary.manifest.cameraFiles.map(\.state) == [.finalized, .finalized])
            #expect(Set(summary.manifest.cameraFiles.map(\.name)).count == 2)
            #expect(summary.manifest.result == .ok)
        }

        /// A camera frame that arrives within the decision delay is not late;
        /// one that arrives after its tick was decided is placed late and counted.
        @Test func aCameraFrameArrivingAfterTheDecisionDelayIsCountedInTheRecordingLog() async throws {
            cameras.connected.withLock { $0 = [Self.camera] }
            try start(cameraMode: .real)
            let camera = try #require(cameras.last)
            try await sendFrames(camera, until: "the camera file") { (try? manifestOnDisk().cameraFiles.count) == 1 }
            try await Task.sleep(for: .milliseconds(900))
            try camera.sendFrame(capturedAgo: .milliseconds(800))
            try camera.sendFrame(capturedAgo: .milliseconds(100))
            let summary = await stop()
            let name = try #require(summary.manifest.cameraFiles.first?.name)
            let log = try String(contentsOf: recorder.folder.appending(path: RecordingNames.recordingLog), encoding: .utf8)
            #expect(log.contains("\(name): 1 frame arrived after its tick was decided and was placed late, the latest "))
        }

        /// Limits short enough for a test.
        private static let quickFrameWatch = CameraFrameWatch(firstFrameLimit: .milliseconds(300), frameGapLimit: .milliseconds(200))

        /// A camera that delivers nothing is failing, not showing a still picture.
        @Test func aCameraThatDeliversNoFirstFrameIsAFailingStreamAndStartsAgain() async throws {
            cameras.connected.withLock { $0 = [Self.camera] }
            try start(cameraMode: .real, cameraFrameWatch: Self.quickFrameWatch)
            try await wait("the failure") { (try? manifestOnDisk().events.first?.event) == .cameraStreamFailed }
            let failure = try #require(try manifestOnDisk().events.first)
            #expect(failure.errorDetail == "the camera delivered no frame within 0.3 s of its start")
            #expect(failure.camera == "Stand-in camera")
            #expect(observer.problems.map(\.problem.problem) == ["Camera Stand-in camera"])
            #expect(cameras.opened.withLock { $0.first?.isStopped } == true)
            try await wait("the restart") { cameras.opened.withLock { $0.count } >= 2 }
            let summary = await stop()
            #expect(summary.manifest.cameraFiles.isEmpty)
        }

        @Test func aCameraThatStopsDeliveringFramesEndsItsFileAsAFailingStream() async throws {
            cameras.connected.withLock { $0 = [Self.camera] }
            try start(cameraMode: .real, cameraFrameWatch: Self.quickFrameWatch)
            let camera = try #require(cameras.last)
            try await sendFrames(camera, until: "the camera file") { (try? manifestOnDisk().cameraFiles.count) == 1 }
            try await wait("the failure") { (try? manifestOnDisk().events.first?.event) == .cameraStreamFailed }
            #expect(try manifestOnDisk().events.first?.errorDetail == "the camera delivered no frame for 0.2 s")
            try await wait("the file's end") { (try? manifestOnDisk().cameraFiles.first?.state) == .finalized }
            #expect(camera.isStopped)
            let summary = await stop()
            #expect(summary.manifest.result == .problems)
        }

        /// The writer takes only decoded pictures; a frame without one ends the capture, never silently.
        @Test func aFrameWithoutAPictureEndsTheCaptureAsAFailure() async throws {
            cameras.connected.withLock { $0 = [Self.camera] }
            try start(cameraMode: .real)
            let camera = try #require(cameras.last)
            try camera.sendFrameWithoutPicture()
            try await wait("the failure") { (try? manifestOnDisk().events.map(\.event)) == [.cameraStreamFailed] }
            #expect(try manifestOnDisk().events.first?.errorDetail == CameraCapture.frameWithoutPicture)
            _ = await stop()
        }

        @Test func theCameraPermissionNeverAskedIsAskedOnceAndTheCameraRecordedOnceGranted() async throws {
            cameras.connected.withLock { $0 = [Self.camera] }
            cameras.permission.withLock { $0 = .notAsked }
            try start(cameraMode: .real)
            try await wait("the request") { cameras.requests.withLock { $0 } == 1 }
            try await wait("the camera's start") { cameras.last != nil }
            #expect(cameras.requests.withLock { $0 } == 1)
            #expect(observer.problems.isEmpty)
            _ = await stop()
        }

        @Test func aDeniedCameraPermissionIsAProblemToldOnce() async throws {
            cameras.connected.withLock { $0 = [Self.camera] }
            cameras.permission.withLock { $0 = .denied }
            try start(cameraMode: .real)
            recorder.camerasChanged()
            recorder.camerasChanged()
            #expect(observer.problems.map(\.problem.problem) == ["The Camera permission is missing"])
            #expect(cameras.requests.withLock { $0 } == 0)
            #expect(cameras.opened.withLock { $0.isEmpty })
            #expect(recorder.status().rows.contains {
                $0.source == .camera(nil, name: "Stand-in camera") && $0.state == "no Camera permission"
            })
            let summary = await stop()
            #expect(summary.manifest.problems.count == 1)
        }

        @Test func aDenialAtTheRequestIsAProblem() async throws {
            cameras.connected.withLock { $0 = [Self.camera] }
            cameras.permission.withLock { $0 = .notAsked }
            cameras.answer.withLock { $0 = .denied }
            try start(cameraMode: .real)
            try await wait("the problem") { !observer.problems.isEmpty }
            #expect(observer.problems.map(\.problem.problem) == ["The Camera permission is missing"])
            #expect(cameras.opened.withLock { $0.isEmpty })
            _ = await stop()
        }

        /// As in the test VM: no camera, no request, no problem, no camera file.
        @Test func withoutACameraNothingIsAskedOrTold() async throws {
            cameras.permission.withLock { $0 = .notAsked }
            try start(cameraMode: .real)
            recorder.camerasChanged()
            let summary = await stop()
            #expect(cameras.requests.withLock { $0 } == 0)
            #expect(summary.manifest.cameraFiles.isEmpty)
            #expect(summary.manifest.problems.isEmpty)
            #expect(summary.manifest.events.isEmpty)
        }

        @Test func theCameraModeNoneNeverReadsTheCameras() async throws {
            cameras.connected.withLock { $0 = [Self.camera] }
            try start(readsScreens: true)
            recorder.camerasChanged()
            _ = await stop()
            #expect(cameras.reads.withLock { $0 } == 0)
            #expect(cameras.opened.withLock { $0.isEmpty })
        }

        // MARK: Input volume (D69)

        @Test func anAudioInputsFileHasItsInputVolumeAtItsStart() async throws {
            try start()
            try send(0.25, buffers: 20)
            try await wait("the file") { (try? manifestOnDisk().audioFiles.count) == 1 }
            let summary = await stop()
            #expect(summary.manifest.audioFiles.map(\.inputVolume) == [0.42])
            #expect(summary.manifest.audioFiles.map(\.state) == [.finalized])
        }

        @Test func aChangeOfTheInputVolumeIsAnEventOnceItHeldStill() async throws {
            try start()
            volume.change(to: 0.5)
            volume.change(to: 0.6)
            try await wait("the event") { (try? manifestOnDisk().events.count) == 1 }
            let event = try #require(try manifestOnDisk().events.first)
            #expect(event.event == .audioInputVolumeChanged)
            #expect(event.audioSource == name)
            #expect(event.from == .volume(0.42))
            #expect(event.to == .volume(0.6))
            #expect(observer.eventLines.map(\.line).contains { $0.hasSuffix("audio input volume changed: \(name) 0.42 → 0.6") })
            #expect(observer.eventLines.allSatisfy { !$0.isFailure })
            #expect(observer.problems.isEmpty)
            _ = await stop()
        }

        /// A knob that Core Audio does not report to the listener is read all the same.
        @Test func aChangeCoreAudioDoesNotReportIsReadAllTheSame() async throws {
            try start()
            volume.state.withLock { $0.volume = 0.8 }
            try await wait("the event") { (try? manifestOnDisk().events.count) == 1 }
            #expect(try manifestOnDisk().events.first?.to == .volume(0.8))
            _ = await stop()
        }

        @Test func theSliderSetsTheInputVolumeAndAChangeNotHeldStillIsToldAtStop() async throws {
            try start()
            #expect(recorder.meters().inputVolumes == [.input(uid): 0.42])
            recorder.setInputVolume(.input(uid), to: 0.3)
            #expect(volume.state.withLock { $0.set } == [0.3])
            #expect(recorder.meters().inputVolumes == [.input(uid): 0.3])
            let summary = await stop()
            #expect(summary.manifest.events.map(\.event) == [.audioInputVolumeChanged])
            #expect(summary.manifest.events.first?.to == .volume(0.3))
            #expect(volume.state.withLock { $0.cancelled })
            // Not reset at Stop.
            #expect(volume.state.withLock { $0.set } == [0.3])
        }

        @Test func anInputVolumeThatCannotBeSetIsAProblem() async throws {
            try start()
            volume.state.withLock { $0.refusesToSet = true }
            recorder.setInputVolume(.input(uid), to: 0.3)
            #expect(observer.problems.count == 1)
            #expect(observer.problems.first?.ofAnEvent == false)
            #expect(observer.problems.first?.problem.text.contains("The input volume of \(name) cannot be set") == true)
            _ = await stop()
        }

        @Test func anInputVolumeThatCannotBeSetHasNoSlider() async throws {
            volume.state.withLock { $0.isSettable = false }
            try start()
            #expect(recorder.meters().inputVolumes.isEmpty)
            recorder.setInputVolume(.input(uid), to: 0.3)
            #expect(volume.state.withLock { $0.set }.isEmpty)
            _ = await stop()
        }

        // MARK: Level meters and no audio (D69)

        @Test func theLevelMeterReadsEachRunningCapture() async throws {
            try start()
            try send(0.5, buffers: 2)
            let level = try #require(recorder.meters().levels[.input(uid)])
            #expect(level.peak == 0.5)
            _ = await stop()
            #expect(recorder.meters().levels.isEmpty)
        }

        @Test func noAudioIsShownAndToldButIsNoProblem() async throws {
            try start()
            let buffersOfNoAudio = Int(RecorderValues.noAudioTime.nanoseconds * Int64(RecorderValues.audioSampleRate) / 1_000_000_000)
                / samplesPerBuffer
            try send(0, buffers: buffersOfNoAudio + 10)
            try await wait("no audio") { recorder.status().rows.first?.state == "no audio" }
            #expect(try manifestOnDisk().events.map(\.event) == [.noAudioStarted])
            try send(0.25, buffers: 10, after: buffersOfNoAudio + 10)
            try await wait("the sound") { recorder.status().rows.first?.state == "recording" }
            let summary = await stop()
            #expect(summary.manifest.events.map(\.event) == [.noAudioStarted, .noAudioStopped])
            #expect(summary.manifest.audioFiles.count == 1)
            #expect(summary.manifest.problems.isEmpty)
            #expect(summary.manifest.result == .ok)
            #expect(observer.problems.isEmpty)
            #expect(observer.eventLines.allSatisfy { !$0.isFailure })
        }
    }
}
