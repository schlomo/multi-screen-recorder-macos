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
            /// The sources opened per audio input, by its UID.
            let byUID = Mutex<[String: [AudioCaptureTests.StandInSource]]>([:])
            func last(of uid: String) -> AudioCaptureTests.StandInSource? { byUID.withLock { $0[uid]?.last } }
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
            /// The format the recorder sets, nil to keep the camera's.
            let format: CameraFormat?
            private let state = Mutex<(
                queue: DispatchQueue?, deliver: (@Sendable (CMSampleBuffer) -> Void)?,
                ended: (@Sendable (VideoStreamEnd) -> Void)?, formatTakenOver: (@Sendable () -> Void)?, stopped: Bool
            )>((nil, nil, nil, nil, false))

            init(frameSize: FrameSize, format: CameraFormat?) {
                self.frameSize = frameSize
                self.format = format
            }

            var isStopped: Bool { state.withLock { $0.stopped } }
            /// How long `stop` takes, as `stopRunning` of a suspended camera blocked for 2.6 s.
            let stopTakes = Mutex(Duration.zero)

            func start(
                queue: DispatchQueue, deliver: @escaping @Sendable (CMSampleBuffer) -> Void,
                ended: @escaping @Sendable (VideoStreamEnd) -> Void, formatTakenOver: @escaping @Sendable () -> Void
            ) {
                state.withLock { $0 = (queue, deliver, ended, formatTakenOver, false) }
            }

            /// Another app changes the open camera's format, as `CameraSource` sees it.
            func formatChangedByAnotherApp() {
                state.withLock { $0.formatTakenOver }?()
            }

            func stop() async {
                try? await Task.sleep(for: stopTakes.withLock { $0 })
                state.withLock { $0.stopped = true }
            }

            /// A decoded frame captured `ago` before now, handed to the capture on its queue; `pillarboxed`,
            /// a portrait picture between black bars in a landscape frame, as the DJI Osmo Pocket delivers it.
            func sendFrame(capturedAgo ago: Duration = .zero, pillarboxed: Bool = false) throws {
                var pixelBuffer: CVPixelBuffer?
                CVPixelBufferCreate(
                    nil, frameSize.width, frameSize.height, kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
                    [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary, &pixelBuffer)
                let picture = try #require(pixelBuffer)
                Self.paint(picture, pillarboxed: pillarboxed)
                var format: CMVideoFormatDescription?
                CMVideoFormatDescriptionCreateForImageBuffer(allocator: nil, imageBuffer: picture, formatDescriptionOut: &format)
                var timing = Self.timingNow(ago: ago)
                var buffer: CMSampleBuffer?
                CMSampleBufferCreateReadyWithImageBuffer(
                    allocator: nil, imageBuffer: picture, formatDescription: try #require(format), sampleTiming: &timing,
                    sampleBufferOut: &buffer)
                deliver(try #require(buffer))
            }

            /// Grey luma with a pattern; with `pillarboxed` only in the middle, black at the sides.
            private static func paint(_ picture: CVPixelBuffer, pillarboxed: Bool) {
                CVPixelBufferLockBaseAddress(picture, [])
                defer { CVPixelBufferUnlockBaseAddress(picture, []) }
                let width = CVPixelBufferGetWidthOfPlane(picture, 0), height = CVPixelBufferGetHeightOfPlane(picture, 0)
                let bytesPerRow = CVPixelBufferGetBytesPerRowOfPlane(picture, 0)
                let luma = CVPixelBufferGetBaseAddressOfPlane(picture, 0)!.assumingMemoryBound(to: UInt8.self)
                let pictureWidth = pillarboxed ? height * height / width : width
                let left = (width - pictureWidth) / 2
                for y in 0..<height {
                    for x in 0..<width {
                        let inside = x >= left && x < left + pictureWidth
                        luma[y * bytesPerRow + x] = inside ? UInt8(60 + (x * 7 + y * 3) % 120) : 16
                    }
                }
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
            readsScreens: Bool = false, cameraMode: CameraMode = .none, cameraFrameWatch: CameraFrameWatch = CameraFrameWatch(),
            inputs: [AudioInputInfo]? = nil, audioInputsFollowed: Bool = true
        ) throws {
            var settings = Settings.defaults
            settings.auto = false
            settings.resolution = readsScreens || cameraMode != .none ? .p1080 : RecordingResolution.none
            settings.cameraMode = cameraMode
            settings.audioMode = inputs == nil ? .defaultMicrophone : .allInputs
            settings.systemAudio = false
            settings.outputFolder = home.path(percentEncoded: false)
            let input = AudioInputInfo(name: name, channelCount: 1, isDefault: true, transport: .usb, uid: uid)
            let inputs = inputs ?? [input]
            let sources = sources
            let volume = volume
            let screensReadable = screensReadable
            let cameras = cameras
            let devices = RecorderDevices(
                screens: { () throws(DeviceReadError) -> [ConnectedScreen] in
                    if screensReadable.isOn.withLock({ $0 }) { return [] }
                    throw DeviceReadError("the stand-in's screens cannot be read")
                },
                audioInputs: { inputs },
                audioInputSource: { uid in
                    let source = AudioCaptureTests.StandInSource()
                    sources.list.withLock { $0.append(source) }
                    sources.byUID.withLock { $0[uid, default: []].append(source) }
                    return source
                },
                inputVolume: { _, _ in volume },
                cameras: {
                    cameras.reads.withLock { $0 += 1 }
                    return cameras.connected.withLock { $0 }
                },
                cameraSource: { _, format, frameSize in
                    let camera = StandInCamera(frameSize: frameSize, format: format)
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
            var devicesUsed = devices
            if !audioInputsFollowed {
                devicesUsed.watchAudioInputs = { _ throws(DeviceReadError) in throw DeviceReadError("the stand-in's listener failed") }
            }
            let facts = ReadyCheckFacts(
                screenRecording: nil, microphoneGranted: true, screens: .success([]), audioInputs: .success(inputs),
                outputFolder: .unusable("not probed by the tests"))
            recorder = try Recorder(
                settings: settings, homeFolder: home, app: "Multi Screen Recorder (tests)", readyCheckFacts: facts, observer: observer,
                devices: devicesUsed, cameraFrameWatch: cameraFrameWatch)
        }

        private var source: AudioCaptureTests.StandInSource { sources.last }

        /// Buffers of `value` throughout, the first `start` buffers after now.
        private func send(_ value: Float, buffers: Int, after start: Int = 0, to source: AudioCaptureTests.StandInSource? = nil) throws {
            let source = source ?? self.source
            let now = readClocks().host
            for index in 0..<buffers {
                let nanoseconds = Int64(start + index) * Int64(samplesPerBuffer) * 1_000_000_000 / Int64(RecorderValues.audioSampleRate)
                let samples = [[Float](repeating: value, count: samplesPerBuffer)]
                let time = CMTime(value: CMTimeValue(now) + nanoseconds, timescale: 1_000_000_000)
                source.send(try pcmSample(samples[...], format: pcmFormat(channels: 1), at: time))
            }
        }

        /// Waits on the main actor, so the recorder's tasks run, until `condition` holds, for at most `seconds`.
        private func wait(_ what: String, seconds: Int = 5, until condition: () -> Bool) async throws {
            for _ in 0..<(seconds * 100) {
                if condition() { return }
                try await Task.sleep(for: .milliseconds(10))
            }
            Issue.record("timed out waiting for \(what)")
            throw CancellationError()
        }

        /// Sends a buffer to each input's latest capture at each of `wait`'s checks until the recording
        /// has `count` audio files, as a single buffer now and then starts none.
        private func startAudioFiles(_ uids: [String], _ what: String = "the audio files", count: Int? = nil) async throws {
            try await wait(what) {
                for uid in uids { try? send(0.1, buffers: 1, to: sources.last(of: uid)) }
                return (try? manifestOnDisk().audioFiles.count) == count ?? uids.count
            }
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

        /// Sends a frame at each of `wait`'s checks, about every 10 ms, until `condition` holds.
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

        /// A camera that offers its size in both orientations, as the DJI Osmo Pocket.
        static let osmo = CameraInfo(
            uniqueID: "Osmo", name: "OsmoPocket4P", isDefault: true, isVirtual: false,
            formats: [
                CameraFormat(size: FrameSize(width: 320, height: 180), maxFramesPerSecond: 30),
                CameraFormat(size: FrameSize(width: 180, height: 320), maxFramesPerSecond: 30),
            ],
            activeFormat: CameraFormat(size: FrameSize(width: 320, height: 180), maxFramesPerSecond: 30))

        /// A camera that offers its size in both orientations and delivers a portrait picture pillarboxed in
        /// its landscape format turns to the portrait format before its file starts (D76).
        @Test func aCameraWhosePictureIsBoxedInTheOtherOrientationTurnsBeforeItsFile() async throws {
            cameras.connected.withLock { $0 = [Self.osmo] }
            try start(cameraMode: .real)
            let landscape = try #require(cameras.last)
            #expect(landscape.frameSize == FrameSize(width: 320, height: 180))
            try await wait("the turned camera") {
                try? landscape.sendFrame(pillarboxed: true)
                return cameras.opened.withLock { $0.count } == 2
            }
            let portrait = try #require(cameras.last)
            #expect(portrait.frameSize == FrameSize(width: 180, height: 320))
            #expect(portrait.format?.size == FrameSize(width: 180, height: 320))
            try await sendFrames(portrait, until: "the camera file") { (try? manifestOnDisk().cameraFiles.count) == 1 }
            let summary = await stop()
            #expect(landscape.isStopped)
            #expect(summary.manifest.cameraFiles.map(\.frameSize) == [[180, 320]])
            #expect(summary.manifest.events.isEmpty)
        }

        /// The audio inputs' changes that cannot be followed: told, red for the whole recording (D78).
        @Test func audioInputChangesThatCannotBeFollowedAreARedLine() async throws {
            try start(audioInputsFollowed: false)
            #expect(observer.problems.map(\.problem.problem) == ["Changes of the audio inputs cannot be followed"])
            let line = try #require(recorder.problemLines().first)
            #expect(line.text == "Changes of the audio inputs not followed since 0:00: the stand-in's listener failed")
            #expect(line.isRed)
            _ = await stop()
        }

        /// Three microphones' sound, the reference R and A 0.5 s earlier, B 0.2 s later, placed straight into the
        /// delay measurement's rings from 1 s to 13 s of the recording, so every window is there at once.
        private func feedDelayedNoise(_ uids: [String: Double]) {
            let rate = RecorderValues.audioSampleRate
            var seed: UInt64 = 7
            let noise = (0..<(15 * rate)).map { _ -> Float in
                seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
                return Float(Int64(bitPattern: seed >> 11) % 2001 - 1000) / 2000
            }
            for (uid, lag) in uids {
                for chunk in stride(from: rate, to: 13 * rate, by: rate / 10) {
                    let shift = Int((lag * Double(rate)).rounded())
                    let samples = Array(noise[(chunk - shift + rate)..<(chunk - shift + rate + rate / 10)])
                    recorder.audioDelays.receive([samples], from: uid, at: Int64(chunk) * 1_000_000_000 / Int64(rate))
                }
            }
        }

        /// The delays are normalized over every file measured against the reference's file, ended ones
        /// included, and written into the manifest: an input that was the earliest ending and starting
        /// again leaves the others' delays as they were (D77).
        @Test func theDelaysStayNormalizedWhenTheEarliestInputsFileEnds() async throws {
            let inputs = ["R", "A", "B"].map { AudioInputInfo(name: "Mic \($0)", channelCount: 1, isDefault: $0 == "R", transport: .usb, uid: $0) }
            try start(inputs: inputs)
            try await wait("the audio inputs' captures") { sources.byUID.withLock { $0.count } == 3 }
            try await startAudioFiles(["R", "A", "B"])
            feedDelayedNoise(["R": 0, "A": -0.5, "B": 0.2])
            for _ in 0..<3 { await recorder.measureAudioDelays() }
            func delays() throws -> [String: Double?] {
                Dictionary(try manifestOnDisk().audioFiles.map { ($0.audioSource, $0.measuredDelay) }, uniquingKeysWith: { _, last in last })
            }
            let measured = try delays()
            #expect(abs((measured["Mic A"] ?? nil) ?? 1) < 0.002)
            #expect(abs(((measured["Mic B"] ?? nil) ?? 0) - 0.7) < 0.002)
            #expect(abs(((measured["Mic R"] ?? nil) ?? 0) - 0.5) < 0.002)
            // A's file ends, and A starts again in a new file without a measurement yet.
            try #require(sources.last(of: "A")).lose(.captureFailed("the stand-in failed"))
            try await wait("A's restart") { sources.byUID.withLock { $0["A"]?.count } == 2 }
            try await startAudioFiles(["A"], "A's new file", count: 4)
            feedDelayedNoise(["R": 0, "B": 0.2])
            await recorder.measureAudioDelays()
            #expect(abs(((try delays()["Mic B"] ?? nil) ?? 0) - 0.7) < 0.002)
            _ = await stop()
        }

        /// An audio input whose first clear window says it is 0.5 s late leaves the "Audio inputs" guide track at
        /// once, with its event and an orange line; its own file goes on, and its next file joins again (D79).
        @Test func anAudioInputClearlyLateLeavesTheGuideTrackUntilItsNextFile() async throws {
            cameras.connected.withLock { $0 = [Self.camera] }
            let inputs = ["R", "A"].map { AudioInputInfo(name: "Mic \($0)", channelCount: 1, isDefault: $0 == "R", transport: .usb, uid: $0) }
            try start(cameraMode: .real, inputs: inputs)
            try await wait("the audio inputs' captures") { sources.byUID.withLock { $0.count } == 2 }
            try await startAudioFiles(["R", "A"])
            let a = SourceLabel.audioInput(2, name: "Mic A"), r = SourceLabel.audioInput(1, name: "Mic R")
            #expect(recorder.guides.contains(source: a, in: .audioInputs))
            feedDelayedNoise(["R": 0, "A": 0.5])
            await recorder.measureAudioDelays()
            // More of its sound changes nothing: it stays out for the rest of its file.
            try await wait("A out of the guide track") {
                try? send(0.1, buffers: 1, to: sources.last(of: "A"))
                return !recorder.guides.contains(source: a, in: .audioInputs)
            }
            try send(0.1, buffers: 3, to: sources.last(of: "A"))
            try await Task.sleep(for: .milliseconds(50))
            #expect(!recorder.guides.contains(source: a, in: .audioInputs))
            #expect(recorder.guides.contains(source: r, in: .audioInputs))
            let left = try manifestOnDisk().events.filter { $0.event == .audioInputLeftTheGuideTrack }
            #expect(left.count == 1)
            let event = try #require(left.first)
            #expect(event.audioSource == "Mic A")
            #expect(abs(try #require(event.delay) - 0.5) < 0.002)
            let line = try #require(recorder.problemLines().first)
            #expect(line.text == "Audio 2 Mic A 500 ms late, not in the guide track; its own audio track is recorded")
            #expect(!line.isRed)
            #expect(try manifestOnDisk().problems.map(\.problem) == ["Audio source Mic A"])
            #expect(try manifestOnDisk().audioFiles.allSatisfy { $0.end == nil })

            try #require(sources.last(of: "A")).lose(.captureFailed("the stand-in failed"))
            try await wait("A's restart") { sources.byUID.withLock { $0["A"]?.count } == 2 }
            try await startAudioFiles(["A"], "A's new file", count: 3)
            try await wait("A back in the guide track") {
                try? send(0.1, buffers: 1, to: sources.last(of: "A"))
                return recorder.guides.contains(source: a, in: .audioInputs)
            }
            // The line stays as it was; the new file, once measured late too, leaves again and is told again.
            #expect(recorder.problemLines().contains(line))
            feedDelayedNoise(["R": 0, "A": 0.5])
            await recorder.measureAudioDelays()
            try await wait("A out of the guide track again") { !recorder.guides.contains(source: a, in: .audioInputs) }
            let leftTwice = try manifestOnDisk().problems.filter { $0.error?.hasPrefix("audio input left the guide track") == true }
            #expect(leftTwice.map(\.problem) == ["Audio source Mic A", "Audio source Mic A"])
            #expect(recorder.problemLines().filter { $0.text.hasPrefix("Audio 2 Mic A") } == [line])
            _ = await stop()
        }

        /// A file that left the guide track and ends while its capture goes on, here as no audio: the input
        /// joins the guide track again for its next file (D79).
        @Test func anAudioInputThatLeftTheGuideTrackJoinsAgainWhenItsFileEnds() async throws {
            cameras.connected.withLock { $0 = [Self.camera] }
            let inputs = ["R", "A"].map { AudioInputInfo(name: "Mic \($0)", channelCount: 1, isDefault: $0 == "R", transport: .usb, uid: $0) }
            try start(cameraMode: .real, inputs: inputs)
            try await wait("the audio inputs' captures") { sources.byUID.withLock { $0.count } == 2 }
            try await startAudioFiles(["R", "A"])
            let a = SourceLabel.audioInput(2, name: "Mic A")
            feedDelayedNoise(["R": 0, "A": 0.5])
            await recorder.measureAudioDelays()
            try await wait("A out of the guide track") { !recorder.guides.contains(source: a, in: .audioInputs) }
            let buffersOfNoAudio = Int(RecorderValues.noAudioTime.nanoseconds * Int64(RecorderValues.audioSampleRate) / 1_000_000_000)
                / samplesPerBuffer
            try send(0, buffers: buffersOfNoAudio + 10, after: 5, to: sources.last(of: "A"))
            try await wait("A's file's end") { (try? manifestOnDisk().audioFiles.first { $0.audioSource == "Mic A" }?.end) != nil }
            try send(0, buffers: 1, after: buffersOfNoAudio + 15, to: sources.last(of: "A"))
            try await wait("A back in the guide track") { recorder.guides.contains(source: a, in: .audioInputs) }
            #expect(sources.byUID.withLock { $0["A"]?.count } == 1)
            _ = await stop()
        }

        /// A measurement during Stop, while a camera's stream still stops, changes the recording no more (D77).
        @Test func noAudioDelayIsMeasuredOnceStopBegan() async throws {
            cameras.connected.withLock { $0 = [Self.camera] }
            let inputs = ["R", "A"].map { AudioInputInfo(name: "Mic \($0)", channelCount: 1, isDefault: $0 == "R", transport: .usb, uid: $0) }
            try start(cameraMode: .real, inputs: inputs)
            let camera = try #require(cameras.last)
            camera.stopTakes.withLock { $0 = .seconds(2) }
            try await wait("the audio inputs' captures") { sources.byUID.withLock { $0.count } == 2 }
            try await startAudioFiles(["R", "A"])
            feedDelayedNoise(["R": 0, "A": 0.2])
            let stopping = Task { await recorder.stop() }
            try await Task.sleep(for: .milliseconds(200))
            for _ in 0..<3 { await recorder.measureAudioDelays() }
            let summary = await stopping.value
            #expect(summary.manifest.audioFiles.allSatisfy { $0.measuredDelay == nil })
        }

        /// A measurement already running when Stop begins changes the recording no more (D77): the
        /// measuring task reaches its wait for the windows before the stopping task starts, both queued
        /// on the main actor in this order.
        @Test func anAudioDelayMeasuredWhileStopBeginsIsNotRecorded() async throws {
            cameras.connected.withLock { $0 = [Self.camera] }
            let inputs = ["R", "A"].map { AudioInputInfo(name: "Mic \($0)", channelCount: 1, isDefault: $0 == "R", transport: .usb, uid: $0) }
            try start(cameraMode: .real, inputs: inputs)
            let camera = try #require(cameras.last)
            camera.stopTakes.withLock { $0 = .seconds(1) }
            try await wait("the audio inputs' captures") { sources.byUID.withLock { $0.count } == 2 }
            try await startAudioFiles(["R", "A"])
            feedDelayedNoise(["R": 0, "A": 0.2])
            for _ in 0..<2 { await recorder.measureAudioDelays() }
            let measuring = Task { await recorder.measureAudioDelays() }
            let stopping = Task { await recorder.stop() }
            await measuring.value
            let summary = await stopping.value
            #expect(summary.manifest.audioFiles.allSatisfy { $0.measuredDelay == nil })
        }

        /// A video file's writer failure and a full disk reach the window's lines, red until a new file of the
        /// camera starts or there is room (D78).
        @Test(arguments: [
            (VideoStreamEnd.writerFailed("cannot write c.mov"), "Camera 1 Stand-in camera not captured since "),
            (.diskFull, "Disk full since "),
        ])
        func aCameraFileEndedByItsWriterOrAFullDiskIsARedLine(end: VideoStreamEnd, line: String) async throws {
            cameras.connected.withLock { $0 = [Self.camera] }
            try start(cameraMode: .real)
            let camera = try #require(cameras.last)
            try await sendFrames(camera, until: "the camera file") { (try? manifestOnDisk().cameraFiles.count) == 1 }
            camera.lose(end)
            try await wait("the line") { recorder.problemLines().first?.text.hasPrefix(line) == true }
            #expect(recorder.problemLines().first?.isRed == true)
            _ = await stop()
        }

        /// A camera another app took over is never turned: a boxed picture after the takeover leaves
        /// nothing due, so the recorder does not wait for it again and again (D76).
        @Test func aTakenOverCameraWhosePictureIsBoxedIsNotTurnedAndNothingIsDue() async throws {
            cameras.connected.withLock { $0 = [Self.osmo] }
            try start(cameraMode: .real)
            let camera = try #require(cameras.last)
            try await sendFrames(camera, until: "the camera file") { (try? manifestOnDisk().cameraFiles.count) == 1 }
            camera.formatChangedByAnotherApp()
            // Past the next check (5 s) and its confirmation (2 s).
            let end = ContinuousClock.now + .seconds(8)
            while ContinuousClock.now < end {
                try camera.sendFrame(pillarboxed: true)
                try await Task.sleep(for: .milliseconds(30))
            }
            #expect(recorder.cameraTracker.nextDueTime() == nil)
            let summary = await stop()
            #expect(cameras.opened.withLock { $0.count } == 1)
            #expect(!summary.manifest.events.contains { $0.event == .cameraOrientationChanged })
        }

        /// A camera whose stream takes long to stop: its file ends where the stop was asked, not
        /// after the stream stopped, with no ticks of its last frame repeated for the wait.
        @Test func aCameraFileEndsWhereTheStopWasAskedThoughItsStreamStopsLate() async throws {
            cameras.connected.withLock { $0 = [Self.camera] }
            try start(cameraMode: .real)
            let camera = try #require(cameras.last)
            camera.stopTakes.withLock { $0 = .seconds(1) }
            try await sendFrames(camera, until: "the camera file") { (try? manifestOnDisk().cameraFiles.count) == 1 }
            let asked = recorder.elapsedSeconds
            let summary = await stop()
            #expect(recorder.elapsedSeconds - asked >= 1)
            let end = try #require(summary.manifest.cameraFiles.first?.end)
            #expect(end <= asked + 1.0 / 30)
            #expect(end > asked - 0.2)
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
        private static let quickFrameWatch = CameraFrameWatch(
            firstFrameLimit: .milliseconds(300), continuityFirstFrameLimit: .milliseconds(300), stallLimit: .milliseconds(200),
            frameGapLimit: .milliseconds(600))

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
            try await wait("the failure") { (try? manifestOnDisk().events.last?.event) == .cameraStreamFailed }
            let events = try manifestOnDisk().events
            #expect(events.map(\.event) == [.cameraStalled, .cameraStreamFailed])
            #expect(events.last?.errorDetail == "the camera delivered no frame for 0.6 s")
            try await wait("the file's end") { (try? manifestOnDisk().cameraFiles.first?.state) == .finalized }
            #expect(camera.isStopped)
            let summary = await stop()
            #expect(summary.manifest.result == .problems)
        }

        /// A camera running elsewhere at the start is opened without changing its format (D74).
        @Test func aCameraRunningElsewhereKeepsItsFormat() async throws {
            var inUse = Self.camera
            inUse.isRunningElsewhere = true
            inUse.activeFormat = Self.camera.formats.first
            cameras.connected.withLock { $0 = [inUse] }
            try start(cameraMode: .real)
            let camera = try #require(cameras.last)
            #expect(camera.format == nil)
            #expect(camera.frameSize == FrameSize(width: 320, height: 180))
            _ = await stop()
        }

        /// Another app changing the open camera's format, as the source sees
        /// it, makes one new camera file after the settle time at the format
        /// the camera then runs in, never setting it back (D74).
        @Test func aFormatChangeByAnotherAppStartsANewFileKeepingItsFormat() async throws {
            cameras.connected.withLock { $0 = [Self.camera] }
            try start(cameraMode: .real)
            let first = try #require(cameras.last)
            #expect(first.format != nil)
            try await sendFrames(first, until: "the camera file") { (try? manifestOnDisk().cameraFiles.count) == 1 }
            var takenOver = Self.camera
            takenOver.isRunningElsewhere = true
            takenOver.activeFormat = CameraFormat(size: FrameSize(width: 160, height: 90), maxFramesPerSecond: 30)
            cameras.connected.withLock { $0 = [takenOver] }
            first.formatChangedByAnotherApp()
            first.formatChangedByAnotherApp()
            try await wait("the second camera") { cameras.opened.withLock { $0.count } == 2 }
            let second = try #require(cameras.last)
            #expect(second.format == nil)
            #expect(second.frameSize == FrameSize(width: 160, height: 90))
            try await sendFrames(second, until: "the second camera file") { (try? manifestOnDisk().cameraFiles.count) == 2 }
            #expect(first.isStopped)
            let summary = await stop()
            #expect(cameras.opened.withLock { $0.count } == 2)
            #expect(summary.manifest.events.map(\.event) == [.cameraFrameSizeChanged])
            #expect(summary.manifest.events.first?.to == [160, 90])
            #expect(summary.manifest.cameraFiles.map(\.frameSize) == [[320, 180], [160, 90]])
            #expect(summary.manifest.result == .ok)
        }

        /// A camera that pauses is stalled: its file goes on, the stall is
        /// told once, and its end comes with its length; no restart.
        @Test func aCameraThatPausesIsStalledAndItsFileGoesOn() async throws {
            cameras.connected.withLock { $0 = [Self.camera] }
            try start(cameraMode: .real, cameraFrameWatch: Self.quickFrameWatch)
            let camera = try #require(cameras.last)
            try await sendFrames(camera, until: "the camera file") { (try? manifestOnDisk().cameraFiles.count) == 1 }
            try await wait("the stall") { (try? manifestOnDisk().events.map(\.event)) == [.cameraStalled] }
            #expect(recorder.status().rows.contains { $0.source == .camera(1, name: "Stand-in camera") && $0.state == "stalled" })
            let stalledRow = try #require(recorder.status().rows.first { $0.source == .camera(1, name: "Stand-in camera") })
            #expect(stalledRow.details.hasPrefix("Camera 1 - Stand-in camera\n"))
            #expect(stalledRow.details.contains("\nStalled: yes"))
            #expect(stalledRow.details.contains("\nThis file so far: "))
            #expect(recorder.status().rows.allSatisfy { $0.details.hasPrefix($0.source.text) })
            #expect(observer.problems.map(\.problem.text) == ["Camera Stand-in camera: camera stalled: \(CameraTracker.stalledError.text)"])
            try await sendFrames(camera, until: "the stall's end") { (try? manifestOnDisk().events.count) == 2 }
            let ended = try #require(try manifestOnDisk().events.last)
            #expect(ended.event == .cameraStallEnded)
            #expect(try #require(ended.length) >= 0.2)
            #expect(recorder.status().rows.contains { $0.source == .camera(1, name: "Stand-in camera") && $0.state == "recording" })
            let summary = await stop()
            #expect(cameras.opened.withLock { $0.count } == 1)
            #expect(summary.manifest.cameraFiles.map(\.state) == [.finalized])
            #expect(summary.manifest.problems.count == 1)
            // A stall loses picture (D47).
            #expect(summary.manifest.result == .problems)
        }

        /// A stalled camera unplugged: its stall ends there, then disconnected, orange (D78).
        @Test func aStalledCameraUnpluggedEndsItsStallLine() async throws {
            cameras.connected.withLock { $0 = [Self.camera] }
            try start(cameraMode: .real, cameraFrameWatch: Self.quickFrameWatch)
            let camera = try #require(cameras.last)
            try await sendFrames(camera, until: "the camera file") { (try? manifestOnDisk().cameraFiles.count) == 1 }
            try await wait("the stall") { (try? manifestOnDisk().events.map(\.event)) == [.cameraStalled] }
            #expect(recorder.problemLines().map(\.text) == ["Camera 1 Stand-in camera stalled since 0:00"])
            cameras.connected.withLock { $0 = [] }
            recorder.camerasChanged()
            let line = try #require(recorder.problemLines().first)
            #expect(line.text.hasPrefix("Camera 1 Stand-in camera stalled "))
            #expect(line.text.hasSuffix(" s at 0:00, then disconnected"))
            #expect(!line.isRed)
            _ = await stop()
        }

        /// The camera's file, recorded until the camera is suspended or unplugged.
        private func recordThenStop(_ reading: CameraInfo?) async throws -> StandInCamera {
            cameras.connected.withLock { $0 = [Self.camera] }
            try start(cameraMode: .real)
            let camera = try #require(cameras.last)
            try await sendFrames(camera, until: "the camera file") { (try? manifestOnDisk().cameraFiles.count) == 1 }
            cameras.connected.withLock { $0 = reading.map { [$0] } ?? [] }
            recorder.camerasChanged()
            return camera
        }

        private static var suspended: CameraInfo {
            var camera = camera
            camera.isSuspended = true
            return camera
        }

        private static var runningElsewhere: CameraInfo {
            var camera = camera
            camera.isRunningElsewhere = true
            camera.activeFormat = camera.formats.first
            return camera
        }

        /// Once our capture's end is reported, a reading counts another app's use again: the camera, used
        /// elsewhere after we stopped it, starts again keeping its format (D74, D76).
        @Test func aCameraUsedElsewhereAfterOurCaptureEndedKeepsItsFormat() async throws {
            _ = try await recordThenStop(Self.suspended)
            try await wait("the file's end") { (try? manifestOnDisk().cameraFiles.first?.state) == .finalized }
            cameras.connected.withLock { $0 = [Self.runningElsewhere] }
            recorder.camerasChanged()
            try await wait("the camera's start after the settle time") { cameras.opened.withLock { $0.count } == 2 }
            #expect(cameras.last?.format == nil)
            _ = await stop()
        }

        /// A reading while our capture still stops is not taken; its end report reads the cameras again (D74).
        @Test func aCameraUsedElsewhereWhileOurCaptureStopsKeepsItsFormat() async throws {
            cameras.connected.withLock { $0 = [Self.camera] }
            try start(cameraMode: .real)
            let first = try #require(cameras.last)
            first.stopTakes.withLock { $0 = .milliseconds(300) }
            try await sendFrames(first, until: "the camera file") { (try? manifestOnDisk().cameraFiles.count) == 1 }
            cameras.connected.withLock { $0 = [Self.suspended] }
            recorder.camerasChanged()
            cameras.connected.withLock { $0 = [Self.runningElsewhere] }
            recorder.camerasChanged()
            #expect(!first.isStopped)
            try await wait("the camera's start after the settle time") { cameras.opened.withLock { $0.count } == 2 }
            #expect(cameras.last?.format == nil)
            _ = await stop()
        }

        /// The cameras are read again only once a failed capture's end is handled: a camera whose fresh
        /// reading says suspended still has its stream failure (D74).
        @Test func aStreamFailureOfACameraNowSuspendedIsStillAFailure() async throws {
            cameras.connected.withLock { $0 = [Self.camera] }
            try start(cameraMode: .real)
            let camera = try #require(cameras.last)
            try await sendFrames(camera, until: "the camera file") { (try? manifestOnDisk().cameraFiles.count) == 1 }
            cameras.connected.withLock { $0 = [Self.suspended] }
            camera.lose(.streamFailed("the stand-in failed"))
            try await wait("the file's end") { (try? manifestOnDisk().cameraFiles.first?.state) == .finalized }
            let summary = await stop()
            #expect(summary.manifest.events.map(\.event).contains(.cameraStreamFailed))
        }

        /// A capture the recorder stops that ends by itself at the same moment, its own end reported
        /// first: that report reads the cameras again, as the stop path's comes too late to (D74).
        @Test func aCaptureEndingByItselfAsItIsStoppedReadsTheCamerasAgain() async throws {
            cameras.connected.withLock { $0 = [Self.camera] }
            try start(cameraMode: .real)
            let first = try #require(cameras.last)
            first.stopTakes.withLock { $0 = .milliseconds(300) }
            try await sendFrames(first, until: "the camera file") { (try? manifestOnDisk().cameraFiles.count) == 1 }
            cameras.connected.withLock { $0 = [Self.suspended] }
            recorder.camerasChanged()
            cameras.connected.withLock { $0 = [Self.runningElsewhere] }
            recorder.camerasChanged()
            recorder.cameraCaptureEnded(
                uniqueID: "StandInCamera", captureNumber: 1, camera: "Stand-in camera", reason: .streamFailed("the stand-in failed"),
                file: nil)
            try await wait("the camera's start after the settle time") { cameras.opened.withLock { $0.count } == 2 }
            #expect(cameras.last?.format == nil)
            _ = await stop()
        }

        /// A failed end of a camera's file, `lost` part of it, as `CameraCapture` reports it late.
        private func failedEnd(of file: RecordingManifest.CameraFile, lost: String? = nil) -> VideoFileEnd<RecordingManifest.CameraFile> {
            var file = file
            file.state = .notFinalized
            return VideoFileEnd(file: file, error: VideoFileWriterError(description: "cannot write \(file.name)", isDiskFull: false), lost: lost)
        }

        /// A failure of a camera's file, reported after a newer file of the camera started, is over when
        /// told: orange at once (D78).
        @Test func aCameraFileFailureReportedAfterANewerFileIsOverAtOnce() async throws {
            cameras.connected.withLock { $0 = [Self.camera] }
            try start(cameraMode: .real)
            let first = try #require(cameras.last)
            try await sendFrames(first, until: "the camera file") { (try? manifestOnDisk().cameraFiles.count) == 1 }
            first.lose(.streamFailed("the stand-in failed"))
            try await wait("the restart") { cameras.opened.withLock { $0.count } == 2 }
            let second = try #require(cameras.last)
            try await sendFrames(second, until: "the second camera file") { (try? manifestOnDisk().cameraFiles.count) == 2 }
            let file = try #require(try manifestOnDisk().cameraFiles.first)
            recorder.cameraCaptureEnded(
                uniqueID: "StandInCamera", captureNumber: 1, camera: "Stand-in camera", reason: .writerFailed("cannot write"),
                file: failedEnd(of: file))
            let line = try #require(recorder.problemLines().first { $0.text.hasPrefix("Camera 1 Stand-in camera not captured") })
            #expect(line.text.contains(", recovered: "))
            #expect(!line.isRed)
            _ = await stop()
        }

        /// A failure of a camera's file reported after the camera was unplugged ends at once, then disconnected;
        /// the part of the file lost is a red line of its own (D78).
        @Test func aCameraFileFailureReportedAfterItsCameraWentIsOverAndItsLostPartRed() async throws {
            _ = try await recordThenStop(nil)
            try await wait("the file's end") { (try? manifestOnDisk().cameraFiles.first?.state) == .finalized }
            let file = try #require(try manifestOnDisk().cameraFiles.first)
            recorder.cameraCaptureEnded(
                uniqueID: "StandInCamera", captureNumber: 1, camera: "Stand-in camera", reason: .writerFailed("cannot write"),
                file: failedEnd(of: file, lost: "its last 2 s"))
            let lines = recorder.problemLines()
            let lost = try #require(lines.first { $0.text.hasPrefix("File \(file.name) incomplete since ") })
            #expect(lost.isRed)
            let failure = try #require(lines.first { $0.text.hasPrefix("Camera 1 Stand-in camera not captured") })
            #expect(failure.text.contains(", then disconnected: "))
            #expect(!failure.isRed)
            _ = await stop()
        }

        /// A full disk is red until the free space check finds room (D78).
        @Test func aFullDiskEndsOnceThereIsRoom() async throws {
            cameras.connected.withLock { $0 = [Self.camera] }
            try start(cameraMode: .real)
            let camera = try #require(cameras.last)
            try await sendFrames(camera, until: "the camera file") { (try? manifestOnDisk().cameraFiles.count) == 1 }
            camera.lose(.diskFull)
            try await wait("the line") { recorder.problemLines().first?.text.hasPrefix("Disk full since ") == true }
            #expect(recorder.problemLines().first?.isRed == true)
            // The next free space check, at most 5 s on.
            try await wait("the room", seconds: 7) { recorder.problemLines().first { $0.text.hasPrefix("Disk full ") }?.isRed == false }
            _ = await stop()
        }

        /// Two audio inputs of the same name: a new file of one ends only its own failed files' lines (D78).
        @Test func aNewAudioFileEndsOnlyItsOwnInputsFailedFiles() async throws {
            let inputs = ["X", "Y"].map { AudioInputInfo(name: "Mic", channelCount: 1, isDefault: $0 == "X", transport: .usb, uid: $0) }
            try start(inputs: inputs)
            try await wait("the audio inputs' captures") { sources.byUID.withLock { $0.count } == 2 }
            try await startAudioFiles(["X", "Y"])
            let x = try #require(try manifestOnDisk().audioFiles.first { $0.audioSourceUID == "X" })
            recorder.audioFileEnded(failedEnd(of: x))
            try #require(sources.last(of: "Y")).lose(.captureFailed("the stand-in failed"))
            try await wait("Y's restart") { sources.byUID.withLock { $0["Y"]?.count } == 2 }
            try await startAudioFiles(["Y"], "Y's new file", count: 3)
            let line = try #require(recorder.problemLines().first { $0.text.hasPrefix("File \(x.name) failed") })
            #expect(line.isRed)
            _ = await stop()
        }

        /// A failure of an audio file reported after a newer file of its input started is over when told (D78).
        @Test func anAudioFileFailureReportedAfterANewerFileIsOverAtOnce() async throws {
            try start()
            try await startAudioFiles([uid])
            source.lose(.captureFailed("the stand-in failed"))
            try await wait("the restart") { sources.count == 2 }
            try await startAudioFiles([uid], "the new file", count: 2)
            let first = try #require(try manifestOnDisk().audioFiles.first)
            recorder.audioFileEnded(failedEnd(of: first))
            let line = try #require(recorder.problemLines().first { $0.text.hasPrefix("File \(first.name) failed") })
            #expect(!line.isRed)
            _ = await stop()
        }

        /// A failed end of an audio file, as `AudioCapture` reports it.
        private func failedEnd(of file: RecordingManifest.AudioFile) -> AudioFileEnd {
            var file = file
            file.end = file.end ?? file.start + 0.5
            file.state = .notFinalized
            return AudioFileEnd(file: file, error: AudioFileWriterError(nil, while: "cannot write \(file.name)"))
        }

        /// A stalled camera the recorder stops, here as it is suspended: its stall ends with its capture,
        /// neither recovered nor disconnected (D78).
        @Test func aStalledCameraStoppedEndsItsStallLine() async throws {
            cameras.connected.withLock { $0 = [Self.camera] }
            try start(cameraMode: .real, cameraFrameWatch: Self.quickFrameWatch)
            let camera = try #require(cameras.last)
            try await sendFrames(camera, until: "the camera file") { (try? manifestOnDisk().cameraFiles.count) == 1 }
            try await wait("the stall") { (try? manifestOnDisk().events.map(\.event)) == [.cameraStalled] }
            cameras.connected.withLock { $0 = [Self.suspended] }
            recorder.camerasChanged()
            let line = try #require(recorder.problemLines().first)
            #expect(line.text.hasPrefix("Camera 1 Stand-in camera stalled "))
            #expect(line.text.hasSuffix(" s at 0:00, stopped"))
            _ = await stop()
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
