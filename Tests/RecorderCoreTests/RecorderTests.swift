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
            var callsToAction: [RecordingProblem] = []

            func recorder(_ recorder: Recorder, lowDiskSpace: Bool) {}
            func recorder(_ recorder: Recorder, screenShowsAnotherScreensPicture screen: String) {}
            func recorder(_ recorder: Recorder, problem: RecordingProblem, ofAnEvent: Bool) {
                problems.append((problem, ofAnEvent))
            }
            func recorder(_ recorder: Recorder, eventLine: String, isFailure: Bool) {
                eventLines.append((eventLine, isFailure))
            }
            func recorder(_ recorder: Recorder, callToAction problem: RecordingProblem) {
                callsToAction.append(problem)
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
            inputs: [AudioInputInfo]? = nil, audioInputsFollowed: Bool = true, audioDelayInterval: Duration = .seconds(3600),
            unrecoveredAfter: Duration = RecorderValues.unrecoveredAfter
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
                // By default measured only when a test calls `measureAudioDelays`, never by the timer mid-test.
                devices: devicesUsed, cameraFrameWatch: cameraFrameWatch, audioDelayInterval: audioDelayInterval,
                unrecoveredAfter: unrecoveredAfter)
        }

        private var source: AudioCaptureTests.StandInSource { sources.last }

        /// Each stand-in source's end of the latest buffer sent, in host nanoseconds.
        private var sentUntil: [ObjectIdentifier: Int64] = [:]

        /// Buffers of `value` throughout, the first `start` buffers after `origin`, now unless given.
        private func send(
            _ value: Float, buffers: Int, after start: Int = 0, to source: AudioCaptureTests.StandInSource? = nil, from origin: Int64? = nil
        ) throws {
            let source = source ?? self.source
            let origin = origin ?? Int64(readClocks().host)
            func nanoseconds(_ buffers: Int) -> Int64 {
                Int64(buffers) * Int64(samplesPerBuffer) * 1_000_000_000 / Int64(RecorderValues.audioSampleRate)
            }
            for index in 0..<buffers {
                let samples = [[Float](repeating: value, count: samplesPerBuffer)]
                let time = CMTime(value: origin + nanoseconds(start + index), timescale: 1_000_000_000)
                source.send(try pcmSample(samples[...], format: pcmFormat(channels: 1), at: time))
            }
            sentUntil[ObjectIdentifier(source)] = origin + nanoseconds(start + buffers)
        }

        /// Buffers of `value` right after the latest one sent to `source`, however long ago that was: on the
        /// test's own clock, as a pause of a slow runner longer than the longest filled gap would end the file.
        private func sendNext(_ value: Float, buffers: Int, to source: AudioCaptureTests.StandInSource?) throws {
            let source = source ?? self.source
            try send(value, buffers: buffers, to: source, from: sentUntil[ObjectIdentifier(source)])
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
                // On from each source's latest buffer, so a slow runner's pause between tries is no gap (D81).
                for uid in uids { try? sendNext(0.1, buffers: 1, to: sources.last(of: uid)) }
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
            // Stop and start the recording again, and report it, at once (D84).
            #expect(observer.callsToAction.map(\.problem) == ["Changes of the audio inputs cannot be followed"])
            let line = try #require(recorder.problemLines().first)
            #expect(line.text == "Changes of the audio inputs not followed since 0:00: the stand-in's listener failed")
            #expect(line.isRed)
            _ = await stop()
        }

        /// The microphones' sound, each later by its lag, placed straight into the delay measurement's rings from
        /// 1 s to 13 s after the latest start of their newest files, so every window is there at once and within
        /// each file however late a slow runner started it.
        private func feedDelayedNoise(_ uids: [String: Double]) throws {
            let rate = RecorderValues.audioSampleRate
            let newest = Dictionary(try manifestOnDisk().audioFiles.compactMap { file in
                file.audioSourceUID.map { ($0, file.start) }
            }) { $1 }
            let base = Int((uids.keys.compactMap { newest[$0] }.max() ?? 0).rounded(.up))
            let noise = FedTables.noise(seed: 7)
            for (uid, lag) in uids {
                for chunk in stride(from: rate, to: 13 * rate, by: rate / 10) {
                    let shift = Int((lag * Double(rate)).rounded())
                    let samples = Array(noise[(chunk - shift + rate)..<(chunk - shift + rate + rate / 10)])
                    recorder.audioDelayFeed.receive([samples], from: uid, at: Int64(base * rate + chunk) * 1_000_000_000 / Int64(rate))
                }
            }
        }

        /// What an input sends into the delay measurement's rings in `feed` (D89).
        enum FedSound {
            /// Speech-like bursts shared by every input, later by the lag.
            case speech(Double)
            /// The same speech under steady noise.
            case noisySpeech(Double)
            /// Speech-like bursts of another talker, unrelated to `speech`: loud and quiet 125 ms slots at random.
            case otherSpeech
            /// Near-silence of its own, about -71 dBFS rms: above digital zero.
            case quiet
            /// Bursts of a second shared signal, unrelated to `speech`, later by the lag: a call's audio on two loopbacks.
            case call(Double)
            case hum
            case noise
        }

        /// As `feedDelayedNoise`, each input its own sound, an input's sound ending `shortBy` seconds early.
        private func feed(_ sounds: [String: FedSound], shortBy: [String: Double] = [:]) throws {
            let rate = RecorderValues.audioSampleRate
            let newest = Dictionary(try manifestOnDisk().audioFiles.compactMap { file in
                file.audioSourceUID.map { ($0, file.start) }
            }) { $1 }
            let base = Int((sounds.keys.compactMap { newest[$0] }.max() ?? 0).rounded(.up))
            let speech = FedTables.bursts(seed: 7, phase: 0, slot: rate / 5)
            let call = FedTables.bursts(seed: 991, phase: 3000, slot: rate / 4)
            for (uid, sound) in sounds {
                let first = UInt64(uid.unicodeScalars.first!.value)
                let own = FedTables.noise(seed: 100 + first)
                let (signal, lag): ([Float], Double) = switch sound {
                case .speech(let lag): (speech, lag)
                case .call(let lag): (call, lag)
                case .noisySpeech(let lag): (FedTables.cached("noisySpeech \(first)") { zip(speech, own).map { $0 + 0.3 * $1 } }, lag)
                case .otherSpeech: (FedTables.cached("otherSpeech \(first)") { own.enumerated().map { sample in
                    var slot = UInt64(sample.offset / (rate / 8)) &* 0x9E37_79B9_7F4A_7C15 &+ first
                    slot ^= slot >> 29
                    slot = slot &* 0xBF58_476D_1CE4_E5B9
                    slot ^= slot >> 32
                    return slot % 2 == 0 ? sample.element : sample.element / 20
                } }, 0)
                case .quiet: (FedTables.cached("quiet \(first)") { own.map { $0 / 1000 } }, 0)
                case .hum: (FedTables.cached("hum") { (0..<own.count).map { Float(0.5 * sin(2 * Double.pi * 50 * Double($0) / Double(rate))) } }, 0)
                case .noise: (own, 0)
                }
                let shift = Int((lag * Double(rate)).rounded())
                let until = 13 * rate - Int((shortBy[uid] ?? 0) * Double(rate))
                for chunk in stride(from: rate, to: until, by: rate / 10) {
                    let samples = Array(signal[(chunk - shift + rate)..<(chunk - shift + rate + rate / 10)])
                    recorder.audioDelayFeed.receive([samples], from: uid, at: Int64(base * rate + chunk) * 1_000_000_000 / Int64(rate))
                }
            }
        }

        private func recordingLog() throws -> String {
            try String(contentsOf: recorder.folder.appending(path: RecordingNames.recordingLog), encoding: .utf8)
        }

        private func fileName(of uid: String) throws -> String {
            try #require(try manifestOnDisk().audioFiles.last { $0.audioSourceUID == uid }?.name)
        }

        private func delays(of uid: String) throws -> [Double] {
            try manifestOnDisk().audioFiles.last { $0.audioSourceUID == uid }?.delays.map(\.delay) ?? []
        }

        /// The owner's recording on 0.20261125.116 (D89): input 1 a dock's line-in with nothing connected,
        /// near-silence above digital zero; the others with clear speech. Nothing counts against the line-in, but the
        /// microphones count against each other: the reference moves to the one the most count against (all tie, the
        /// lowest number), the others sync in that same measurement, and the line-in, never synced, lists no entry.
        @Test func aNearSilentInput1HandsTheReferenceToAMicrophoneAtTheFirstMeasurement() async throws {
            try await startInputs(["Q", "O", "Z", "B"])
            try feed(["Q": .quiet, "O": .speech(0.5), "Z": .speech(0), "B": .speech(0.1)])
            await recorder.measureAudioDelays()
            let (z, b) = (try delays(of: "Z"), try delays(of: "B"))
            #expect(z.count == 1 && abs((z.first ?? 0) + 0.5) < 0.002, "\(z)")
            #expect(b.count == 1 && abs((b.first ?? 0) + 0.4) < 0.002, "\(b)")
            for _ in 0..<3 { await recorder.measureAudioDelays() }
            let (q, o) = (try fileName(of: "Q"), try fileName(of: "O"))
            #expect(try delays(of: "O") == [0])
            _ = await stop()
            #expect(try delays(of: "Q").isEmpty)
            let log = try recordingLog()
            #expect(log.contains("reference \(q): no counted window against it while another input had sound; \(o) has counted "
                + "windows of 2 other inputs against it"), "\(log)")
            #expect(log.contains("reference \(q) → \(o): moved on a reference miss, so it is the new anchor and every input starts over"))
            #expect(log.contains("\(q): no clear sound to sync"))
        }

        /// A loud steady hum as input 1 hands the reference on at the first measurement and never gets it back (D89).
        @Test func aLoudHumNeverBecomesTheReference() async throws {
            try await startInputs(["H", "A", "B"])
            for _ in 0..<4 {
                try feed(["H": .hum, "A": .speech(0), "B": .speech(0.2)])
                await recorder.measureAudioDelays()
            }
            let (h, a) = (try fileName(of: "H"), try fileName(of: "A"))
            let b = try delays(of: "B")
            #expect(b.count == 1 && abs((b.first ?? 0) - 0.2) < 0.002, "\(b)")
            _ = await stop()
            let log = try recordingLog()
            #expect(log.contains("reference \(h) → \(a): moved on a reference miss"), "\(log)")
            #expect(!log.contains("→ \(h)"))
            #expect(!log.contains("\(h) has counted windows"))
        }

        /// The reference and a synced input pause for two measurements while an unsynced
        /// input with unrelated speech-like sound goes on: nothing moves, the audio delays and the mix stay (D89).
        @Test func aPauseWhileAnUnsyncedInputSoundsMovesNothing() async throws {
            try await startInputs(["R", "A", "C"])
            let a = SourceLabel.audioInput(2, name: "Mic A")
            try feed(["R": .speech(0), "A": .speech(0.5), "C": .otherSpeech])
            await recorder.measureAudioDelays()
            try await wait("A in the guide track") {
                try? sendNext(0.1, buffers: 1, to: sources.last(of: "A"))
                return isInTheGuideTrack(a)
            }
            for _ in 0..<2 {
                try feed(["R": .quiet, "A": .quiet, "C": .otherSpeech])
                await recorder.measureAudioDelays()
            }
            try feed(["R": .speech(0), "A": .speech(0.5), "C": .otherSpeech])
            await recorder.measureAudioDelays()
            try sendNext(0.1, buffers: 2, to: sources.last(of: "A"))
            try await Task.sleep(for: .milliseconds(50))
            #expect(isInTheGuideTrack(a))
            let delaysOfA = try delays(of: "A")
            #expect(delaysOfA.count == 1 && abs((delaysOfA.first ?? 0) - 0.5) < 0.002, "\(delaysOfA)")
            #expect(try delays(of: "C").isEmpty, "C is unsynced")
            _ = await stop()
            let log = try recordingLog()
            #expect(!log.contains("no counted window against it"), "\(log)")
            #expect(!log.contains("starts over"))
        }

        /// The reference and a synced input pause for 40 s while an unsynced input with unrelated sound goes on:
        /// nothing moves, and at Stop the audio delays are as before (D89).
        @Test func aLongPauseWhileAnUnsyncedInputSoundsKeepsTheAudioDelays() async throws {
            try await startInputs(["R", "A", "C"])
            try feed(["R": .speech(0), "A": .speech(0.5), "C": .otherSpeech])
            for _ in 0..<3 { await recorder.measureAudioDelays() }
            for _ in 0..<4 {
                try feed(["R": .quiet, "A": .quiet, "C": .otherSpeech])
                await recorder.measureAudioDelays()
            }
            for _ in 0..<3 {
                try feed(["R": .speech(0), "A": .speech(0.5), "C": .otherSpeech])
                await recorder.measureAudioDelays()
            }
            _ = await stop()
            #expect(try delays(of: "R") == [0])
            let delaysOfA = try delays(of: "A")
            #expect(delaysOfA.count == 1 && abs((delaysOfA.first ?? 0) - 0.5) < 0.002, "\(delaysOfA)")
            #expect(try delays(of: "C").isEmpty)
            let log = try recordingLog()
            #expect(!log.contains("no counted window against it"), "\(log)")
            #expect(!log.contains("starts over"))
        }

        /// A reference that stops matching before the sync is established moves to an input the others count against
        /// (of those that tie, the lowest number), which becomes the new anchor, every input starting over (D89).
        @Test func aReferenceMissBeforeTheSyncIsEstablishedMovesToAProvenInput() async throws {
            try await startInputs(["R", "A", "B"])
            try feed(["R": .speech(0), "A": .quiet, "B": .quiet])
            await recorder.measureAudioDelays()
            for _ in 0..<3 {
                try feed(["R": .hum, "A": .noisySpeech(0), "B": .speech(0.3)])
                await recorder.measureAudioDelays()
            }
            let (r, a) = (try fileName(of: "R"), try fileName(of: "A"))
            #expect(try delays(of: "A") == [0])
            let delaysOfB = try delays(of: "B")
            #expect(delaysOfB.count == 1 && abs((delaysOfB.first ?? 0) - 0.3) < 0.002, "\(delaysOfB)")
            _ = await stop()
            #expect(try delays(of: "R").isEmpty)
            let log = try recordingLog()
            #expect(log.contains("reference \(r) → \(a): moved on a reference miss, so it is the new anchor and every input starts over"), "\(log)")
        }

        /// The reference matches once, as a burst on the dock gives, then hums: the microphones prove input 2,
        /// synced by that one window, and the reference moves to it keeping every audio delay; all end synced
        /// against input 1, the anchor (D90).
        @Test func aReferenceThatHumsAfterOneMatchHandsOnToTheSyncedInput() async throws {
            try await startInputs(["R", "A", "B", "C"])
            try feed(["R": .speech(0), "A": .speech(0.3), "B": .quiet, "C": .quiet])
            await recorder.measureAudioDelays()
            for _ in 0..<3 {
                try feed(["R": .hum, "A": .speech(0.3), "B": .speech(0.1), "C": .speech(0.2)])
                await recorder.measureAudioDelays()
            }
            let (r, a) = (try fileName(of: "R"), try fileName(of: "A"))
            _ = await stop()
            #expect(try delays(of: "R") == [0])
            for (uid, expected) in [("A", 0.3), ("B", 0.1), ("C", 0.2)] {
                let listed = try delays(of: uid)
                #expect(listed.count == 1 && abs((listed.first ?? 0) - expected) < 0.002, "\(uid) \(listed)")
            }
            let log = try recordingLog()
            #expect(log.contains("reference \(r) → \(a): lags re-based onto the anchor by 300 ms late"), "\(log)")
            #expect(!log.contains("starts over"))
        }

        /// Input 1's talker starts after 30 s, input 2 has noisy speech all along,
        /// input 3 unrelated sound: nothing proves another reference, nothing moves, and input 2 syncs once input 1
        /// speaks, as under main's rules (D89).
        @Test func aTalkerStartingLateOnInput1SyncsAsBefore() async throws {
            try await startInputs(["R", "A", "C"])
            for _ in 0..<3 {
                try feed(["R": .quiet, "A": .noisySpeech(0.1), "C": .otherSpeech])
                await recorder.measureAudioDelays()
            }
            for _ in 0..<3 {
                try feed(["R": .speech(0), "A": .noisySpeech(0.1), "C": .otherSpeech])
                await recorder.measureAudioDelays()
            }
            _ = await stop()
            #expect(try delays(of: "R") == [0])
            let a = try delays(of: "A")
            #expect(a.count == 1 && abs((a.first ?? 0) - 0.1) < 0.002, "\(a)")
            #expect(try delays(of: "C").isEmpty)
            #expect(!(try recordingLog()).contains("starts over"))
        }

        /// A lone microphone beside an unrelated input whose file ends on no audio and
        /// starts again: nothing moves, the microphone stays the anchor and in the guide track (D89).
        @Test func aLoneMicrophoneKeepsTheReferenceBesideAnUnrelatedInputsNewFile() async throws {
            try await startInputs(["R", "C"])
            let r = SourceLabel.audioInput(1, name: "Mic R")
            for _ in 0..<2 {
                try feed(["R": .speech(0), "C": .otherSpeech])
                await recorder.measureAudioDelays()
            }
            let buffersOfNoAudio = Int(RecorderValues.noAudioTime.nanoseconds * Int64(RecorderValues.audioSampleRate) / 1_000_000_000)
                / samplesPerBuffer
            try sendNext(0, buffers: buffersOfNoAudio + 10, to: sources.last(of: "C"))
            try await wait("C's file's end") { (try? manifestOnDisk().audioFiles.first { $0.audioSource == "Mic C" }?.end) != nil }
            try sendNext(0.1, buffers: 1, to: sources.last(of: "C"))
            try await wait("C's next file") { (try? manifestOnDisk().audioFiles.filter { $0.audioSource == "Mic C" }.count) == 2 }
            for _ in 0..<3 {
                try feed(["R": .speech(0), "C": .otherSpeech])
                await recorder.measureAudioDelays()
            }
            try await wait("R in the guide track") {
                try? sendNext(0.1, buffers: 1, to: sources.last(of: "R"))
                return isInTheGuideTrack(r)
            }
            _ = await stop()
            #expect(try delays(of: "R") == [0])
            #expect(!(try recordingLog()).contains("reference "))
        }

        /// The reference goes quiet after the sync while two synced inputs share speech: it moves to the lower
        /// numbered of them, re-based, and every audio delay stays (D90).
        @Test func aReferenceMissAfterTheSyncMovesToASyncedInputKeepingEveryAudioDelay() async throws {
            try await startInputs(["R", "A", "B"])
            try feed(["R": .speech(0), "A": .speech(0.5), "B": .speech(0.2)])
            for _ in 0..<2 { await recorder.measureAudioDelays() }
            try feed(["R": .quiet, "A": .speech(0.5), "B": .speech(0.2)])
            for _ in 0..<2 { await recorder.measureAudioDelays() }
            let (r, a) = (try fileName(of: "R"), try fileName(of: "A"))
            _ = await stop()
            #expect(try delays(of: "R") == [0])
            let (delaysOfA, delaysOfB) = (try delays(of: "A"), try delays(of: "B"))
            #expect(delaysOfA.count == 1 && abs((delaysOfA.first ?? 0) - 0.5) < 0.002, "\(delaysOfA)")
            #expect(delaysOfB.count == 1 && abs((delaysOfB.first ?? 0) - 0.2) < 0.002, "\(delaysOfB)")
            let log = try recordingLog()
            #expect(log.contains("reference \(r) → \(a): lags re-based onto the anchor by 500 ms late"), "\(log)")
            #expect(!log.contains("starts over"))
        }

        /// A measurement taken against a reference that moved while it ran counts nothing (D89): before the sync is
        /// established, two measurements run against a quiet R at once; the first proves A and moves the reference, B
        /// syncing against A at once; the second, against R, moves nothing more.
        @Test func aMeasurementAgainstAReferenceThatMovedCountsNothing() async throws {
            try await startInputs(["R", "A", "B"])
            try feed(["R": .quiet, "A": .speech(0.5), "B": .speech(0.2)])
            let first = Task { await recorder.measureAudioDelays() }
            let second = Task { await recorder.measureAudioDelays() }
            await first.value
            await second.value
            let (r, b) = (try fileName(of: "R"), try fileName(of: "B"))
            _ = await stop()
            let log = try recordingLog().split(separator: "\n")
            #expect(log.filter { $0.contains("\(b): lag ") && $0.contains("against \(r)") }.count == 2, "both ran against R")
            #expect(log.filter { $0.contains("reference \(r) → ") }.count == 1, "\(log.joined(separator: "\n"))")
            let delaysOfB = try delays(of: "B")
            #expect(delaysOfB.count == 1 && abs((delaysOfB.first ?? 0) + 0.3) < 0.002, "\(delaysOfB)")
        }

        /// A known cost (D89): two inputs carrying one call's audio beside a room that is
        /// quiet for the first 20 s take the reference and establish the sync, so the room's microphones, speaking
        /// later, never sync. The audio mode Wired, the default, records no virtual input but the default microphone.
        @Test func twoInputsOfOneCallTakeTheReferenceBeforeTheRoomSpeaks() async throws {
            try await startInputs(["R", "M", "N", "A", "B"])
            for _ in 0..<2 {
                try feed(["R": .quiet, "M": .quiet, "N": .quiet, "A": .call(0), "B": .call(0.01)])
                await recorder.measureAudioDelays()
            }
            for _ in 0..<5 {
                try feed(["R": .speech(0), "M": .speech(0.1), "N": .speech(0.2), "A": .call(0), "B": .call(0.01)])
                await recorder.measureAudioDelays()
            }
            _ = await stop()
            let delaysOfB = try delays(of: "B")
            #expect(try delays(of: "A") == [0] && delaysOfB.count == 1 && abs((delaysOfB.first ?? 0) - 0.01) < 0.002, "\(delaysOfB)")
            for uid in ["R", "M", "N"] { #expect(try delays(of: uid).isEmpty, "\(uid)") }
            let (r, a) = (try fileName(of: "R"), try fileName(of: "A"))
            #expect(try recordingLog().contains("reference \(r) → \(a): moved on a reference miss"))
        }

        /// An input whose sound ends 0.3 s before the others' is measured over the same
        /// windows, every window ending at the earliest end, and syncs (D89).
        @Test func anInputSlightlyBehindStillSyncs() async throws {
            try await startInputs(["R", "A", "B"])
            try feed(["R": .speech(0), "A": .speech(0.5), "B": .speech(0.2)], shortBy: ["B": 0.3])
            await recorder.measureAudioDelays()
            _ = await stop()
            let delaysOfB = try delays(of: "B")
            #expect(delaysOfB.count == 1 && abs((delaysOfB.first ?? 0) - 0.2) < 0.002, "\(delaysOfB)")
        }

        /// A file that ended on no audio keeps its list at a miss move's start-over, though it is still its device's
        /// newest while the capture runs (D89).
        @Test func aFileThatEndedKeepsItsEntriesAtAMissMove() async throws {
            try await startInputs(["R", "A", "B", "C"])
            try feed(["R": .speech(0), "A": .quiet, "B": .quiet, "C": .speech(0.3)])
            await recorder.measureAudioDelays()
            let buffersOfNoAudio = Int(RecorderValues.noAudioTime.nanoseconds * Int64(RecorderValues.audioSampleRate) / 1_000_000_000)
                / samplesPerBuffer
            try sendNext(0, buffers: buffersOfNoAudio + 10, to: sources.last(of: "C"))
            try await wait("C's file's end") { (try? manifestOnDisk().audioFiles.first { $0.audioSource == "Mic C" }?.end) != nil }
            try feed(["R": .quiet, "A": .speech(0.5), "B": .speech(0.2)])
            await recorder.measureAudioDelays()
            _ = await stop()
            let delaysOfC = try delays(of: "C")
            #expect(delaysOfC.count == 1 && abs((delaysOfC.first ?? 0) - 0.3) < 0.002, "\(delaysOfC)")
            #expect(try recordingLog().contains("moved on a reference miss"))
        }

        /// The owner's Mac, 2026-11-26: a healthy reference whose window falls just short once while two synced
        /// inputs match hands on to one of them, re-based: nothing starts over, and the old reference, the anchor,
        /// measured against the new one from then on, stays synced at 0 (D90).
        @Test func aHealthyReferenceThatMissesOnceKeepsEverySync() async throws {
            try await startInputs(["R", "A", "B"])
            try feed(["R": .speech(0.4), "A": .speech(0), "B": .speech(0.014)])
            await recorder.measureAudioDelays()
            try feed(["R": .noise, "A": .speech(0), "B": .speech(0.014)])
            await recorder.measureAudioDelays()
            for _ in 0..<3 {
                try feed(["R": .speech(0.4), "A": .speech(0), "B": .speech(0.014)])
                await recorder.measureAudioDelays()
            }
            let (r, a) = (try fileName(of: "R"), try fileName(of: "A"))
            _ = await stop()
            let log = try recordingLog()
            #expect(log.contains("reference \(r) → \(a): lags re-based onto the anchor by 400 ms early"), "\(log)")
            #expect(!log.contains("starts over"))
            let (delaysOfA, delaysOfB) = (try delays(of: "A"), try delays(of: "B"))
            #expect(delaysOfA.count == 1 && abs((delaysOfA.first ?? 0) + 0.4) < 0.002, "\(delaysOfA)")
            #expect(delaysOfB.count == 1 && abs((delaysOfB.first ?? 0) + 0.386) < 0.002, "\(delaysOfB)")
            #expect(try delays(of: "R") == [0])
        }

        /// The reference muted while two inputs have an audio delay: the lower-numbered one takes it (D80, D85).
        @Test func aMutedReferenceGoesToTheLowestNumberWithAnAudioDelay() async throws {
            try await startInputs(["R", "A", "B"])
            try feed(["R": .speech(0), "A": .noisySpeech(0.5), "B": .speech(0.2)])
            await recorder.measureAudioDelays()
            let buffersOfNoAudio = Int(RecorderValues.noAudioTime.nanoseconds * Int64(RecorderValues.audioSampleRate) / 1_000_000_000)
                / samplesPerBuffer
            try sendNext(0, buffers: buffersOfNoAudio + 10, to: sources.last(of: "R"))
            try await wait("R's file's end") { (try? manifestOnDisk().audioFiles.first { $0.audioSource == "Mic R" }?.end) != nil }
            try feed(["A": .noisySpeech(0.5), "B": .speech(0.2)])
            await recorder.measureAudioDelays()
            let (r, a) = (try fileName(of: "R"), try fileName(of: "A"))
            _ = await stop()
            let log = try recordingLog()
            #expect(log.contains("reference \(r) → \(a): lags re-based onto the anchor by 500 ms late"), "\(log)")
        }

        /// The audio delays in the manifest are against the anchor, the first input whose file is written, listing its own 0, and
        /// change only with a file's own: the earliest input's file ending and its next file, carrying its
        /// audio delay over, leave the others' as they were (D80).
        @Test func theDelaysAreAgainstTheAnchorAndStayWhenTheEarliestInputsFileEnds() async throws {
            let inputs = ["R", "A", "B"].map { AudioInputInfo(name: "Mic \($0)", channelCount: 1, isDefault: $0 == "R", transport: .usb, uid: $0) }
            try start(inputs: inputs)
            try await wait("the audio inputs' captures") { sources.byUID.withLock { $0.count } == 3 }
            try await startAudioFiles(["R", "A", "B"])
            try feedDelayedNoise(["R": 0, "A": -0.5, "B": 0.2])
            for _ in 0..<3 { await recorder.measureAudioDelays() }
            func delays() throws -> [String: [Double]] {
                Dictionary(try manifestOnDisk().audioFiles.map { ($0.audioSource, $0.delays.map(\.delay)) }, uniquingKeysWith: { _, last in last })
            }
            let measured = try delays()
            #expect(measured["Mic R"] == [0])
            #expect(measured["Mic A"]?.count == 1 && abs((measured["Mic A"]?.last ?? 0) + 0.5) < 0.002)
            #expect(measured["Mic B"]?.count == 1 && abs((measured["Mic B"]?.last ?? 0) - 0.2) < 0.002)
            // A's file ends, and A starts again in a new file without a measurement yet.
            try #require(sources.last(of: "A")).lose(.captureFailed("the stand-in failed"))
            try await wait("A's restart") { sources.byUID.withLock { $0["A"]?.count } == 2 }
            try await startAudioFiles(["A"], "A's new file", count: 4)
            try feedDelayedNoise(["R": 0, "B": 0.2])
            await recorder.measureAudioDelays()
            #expect(try delays()["Mic B"] == measured["Mic B"])
            #expect(try delays()["Mic R"] == [0])
            let files = try manifestOnDisk().audioFiles.filter { $0.audioSource == "Mic A" }
            #expect(files.count == 2)
            // Carried over: the new file's first entry, at its start, the same value.
            #expect(files.last?.delays.map(\.at) == [0])
            #expect(files.last?.delays.map(\.delay) == files.first?.delays.map(\.delay))
            #expect(files.first?.delays.count == 1)
            _ = await stop()
        }

        /// At Stop each file's audio delays are rewritten with hindsight: a false first window, corrected at 3
        /// windows, leaves one entry; until then, as after a crash, the live entries stay on disk (D80).
        @Test func stopRewritesTheDelaysWithHindsightAndACrashKeepsTheLiveOnes() async throws {
            try await startInputs(["R", "A"])
            func delaysOfA() throws -> [Double]? {
                try manifestOnDisk().audioFiles.first { $0.audioSource == "Mic A" }?.delays.map(\.delay)
            }
            try feedDelayedNoise(["R": 0, "A": 0.3])
            await recorder.measureAudioDelays()
            try feedDelayedNoise(["R": 0, "A": 0.2])
            for _ in 0..<3 { await recorder.measureAudioDelays() }
            let live = try #require(try delaysOfA())
            #expect(live.count == 2 && abs(live[0] - 0.3) < 0.002 && abs(live[1] - 0.2) < 0.002)
            _ = await stop()
            let delays = try #require(try manifestOnDisk().audioFiles.first { $0.audioSource == "Mic A" }?.delays)
            #expect(delays.map(\.at) == [0])
            #expect(abs((delays.first?.delay ?? 0) - 0.2) < 0.002)
            #expect(try manifestOnDisk().audioFiles.first { $0.audioSource == "Mic R" }?.delays.map(\.delay) == [0])
        }

        /// The reference's capture ending makes the next input the reference: the others are re-based onto the
        /// anchor through its audio delay, so the mix keeps every input and no listed delay changes; the anchor's
        /// new file, measured against the reference in use, changes none either (D80, D85).
        @Test func theReferencesCaptureEndingAndReturningKeepsTheGuideTrackAndTheDelays() async throws {
            try await startInputs(["R", "A", "B"])
            let (a, b) = (SourceLabel.audioInput(2, name: "Mic A"), SourceLabel.audioInput(3, name: "Mic B"))
            try feedDelayedNoise(["R": 0, "A": 0.5, "B": 0.2])
            await recorder.measureAudioDelays()
            func delays() throws -> [String: [Double]] {
                Dictionary(try manifestOnDisk().audioFiles.map { ($0.audioSource, $0.delays.map(\.delay)) }, uniquingKeysWith: { _, last in last })
            }
            let measured = try delays()
            try await wait("A and B in the guide track") {
                try? sendNext(0.1, buffers: 1, to: sources.last(of: "A"))
                try? sendNext(0.1, buffers: 1, to: sources.last(of: "B"))
                return isInTheGuideTrack(a) && isInTheGuideTrack(b)
            }
            try #require(sources.last(of: "R")).lose(.captureFailed("the stand-in failed"))
            try await wait("R's file's end") { (try? manifestOnDisk().audioFiles.first { $0.audioSource == "Mic R" }?.end) != nil }
            try feedDelayedNoise(["A": 0.5, "B": 0.2])
            await recorder.measureAudioDelays()
            try sendNext(0.1, buffers: 2, to: sources.last(of: "A"))
            try sendNext(0.1, buffers: 2, to: sources.last(of: "B"))
            try await Task.sleep(for: .milliseconds(50))
            #expect(isInTheGuideTrack(a) && isInTheGuideTrack(b))
            #expect(try delays() == measured)
            try await wait("R's restart") { sources.byUID.withLock { $0["R"]?.count } == 2 }
            try await startAudioFiles(["R"], "R's new file", count: 4)
            try feedDelayedNoise(["R": 0, "A": 0.5, "B": 0.2])
            await recorder.measureAudioDelays()
            #expect(try delays() == measured)
            _ = await stop()
        }

        /// The owner's recording 2026-11-24 20.55.08 (D85): the Osmo "O" sounds first, the anchor, the Razer "Z"
        /// 550 ms early against it; the Osmo's capture ends and starts again, its new file 100 ms less late. The
        /// Razer stays the reference and keeps its audio delay; the Osmo's new file carries over its 0 and is
        /// measured against the Razer.
        @Test func theAnchorsNewFileIsMeasuredAgainstTheReferenceInUse() async throws {
            try await startInputs(["O", "Z"])
            try feedDelayedNoise(["O": 0, "Z": -0.55])
            for _ in 0..<3 { await recorder.measureAudioDelays() }
            try #require(sources.last(of: "O")).lose(.captureFailed("the stand-in was unplugged"))
            try await wait("O's restart") { sources.byUID.withLock { $0["O"]?.count } == 2 }
            try await startAudioFiles(["O"], "O's new file", count: 3)
            try feedDelayedNoise(["O": -0.1, "Z": -0.55])
            await recorder.measureAudioDelays()
            let files = try manifestOnDisk().audioFiles
            let osmo = files.filter { $0.audioSource == "Mic O" }
            #expect(osmo.count == 2)
            #expect(osmo.first?.delays.map(\.delay) == [0])
            let carriedAndMeasured = try #require(osmo.last?.delays.map(\.delay))
            #expect(carriedAndMeasured.count == 2 && carriedAndMeasured.first == 0 && abs((carriedAndMeasured.last ?? 0) + 0.1) < 0.002,
                    "\(carriedAndMeasured)")
            let razer = try #require(files.first { $0.audioSource == "Mic Z" }?.delays.map(\.delay))
            #expect(razer.count == 1 && abs((razer.first ?? 0) + 0.55) < 0.002, "\(razer)")
            _ = await stop()
        }

        /// The anchor is the first input whose file is written, the default microphone or not: one whose file
        /// starts later is measured against it, and nothing starts over (D80).
        @Test func anInputWhoseFileStartsLaterIsMeasuredAgainstTheAnchor() async throws {
            cameras.connected.withLock { $0 = [Self.camera] }
            let inputs = ["R", "A"].map { AudioInputInfo(name: "Mic \($0)", channelCount: 1, isDefault: $0 == "R", transport: .usb, uid: $0) }
            try start(cameraMode: .real, inputs: inputs)
            try await wait("the audio inputs' captures") { sources.byUID.withLock { $0.count } == 2 }
            let a = SourceLabel.audioInput(2, name: "Mic A")
            try await startAudioFiles(["A"], "A's file", count: 1)
            try await wait("A in the guide track") {
                try? sendNext(0.1, buffers: 1, to: sources.last(of: "A"))
                return isInTheGuideTrack(a)
            }
            try await startAudioFiles(["R"], "R's file", count: 2)
            try feedDelayedNoise(["R": 0.5, "A": 0])
            await recorder.measureAudioDelays()
            await recorder.measureAudioDelays()
            try sendNext(0.1, buffers: 2, to: sources.last(of: "A"))
            try await Task.sleep(for: .milliseconds(50))
            #expect(isInTheGuideTrack(a))
            let files = try manifestOnDisk().audioFiles
            let r = try #require(files.first { $0.audioSource == "Mic R" })
            #expect(r.delays.count == 1 && abs((r.delays.first?.delay ?? 0) - 0.5) < 0.002)
            #expect(files.first { $0.audioSource == "Mic A" }?.delays.map(\.delay) == [0])
            _ = await stop()
        }

        /// The anchor muted mid-recording, its file ended on no audio, hands the reference to the next input
        /// with an audio delay, so an input waiting to join is measured and joins (D80).
        @Test func aMutedAnchorHandsTheReferenceToAnInputWithAnAudioDelay() async throws {
            try await startInputs(["R", "A", "B"])
            let b = SourceLabel.audioInput(3, name: "Mic B")
            try feedDelayedNoise(["R": 0, "A": 0.5])
            await recorder.measureAudioDelays()
            let buffersOfNoAudio = Int(RecorderValues.noAudioTime.nanoseconds * Int64(RecorderValues.audioSampleRate) / 1_000_000_000)
                / samplesPerBuffer
            try sendNext(0, buffers: buffersOfNoAudio + 10, to: sources.last(of: "R"))
            try await wait("R's file's end") { (try? manifestOnDisk().audioFiles.first { $0.audioSource == "Mic R" }?.end) != nil }
            try feedDelayedNoise(["A": 0.5, "B": 0.2])
            await recorder.measureAudioDelays()
            try await wait("B in the guide track") {
                try? sendNext(0.1, buffers: 1, to: sources.last(of: "B"))
                return isInTheGuideTrack(b)
            }
            let delays = try #require(try manifestOnDisk().audioFiles.first { $0.audioSource == "Mic B" }?.delays)
            #expect(delays.count == 1 && abs((delays.first?.delay ?? 0) - 0.2) < 0.002)
            _ = await stop()
        }

        /// The anchor muted while the only other input has no audio delay yet: that input becomes the new
        /// anchor and every input starts over, so measuring never stalls (D80).
        @Test func aMutedAnchorWithOnlyAnInputWaitingMakesThatTheNewAnchor() async throws {
            try await startInputs(["D", "B"])
            let b = SourceLabel.audioInput(2, name: "Mic B")
            #expect(!isInTheGuideTrack(b))
            let buffersOfNoAudio = Int(RecorderValues.noAudioTime.nanoseconds * Int64(RecorderValues.audioSampleRate) / 1_000_000_000)
                / samplesPerBuffer
            try sendNext(0, buffers: buffersOfNoAudio + 10, to: sources.last(of: "D"))
            try await wait("D's file's end") { (try? manifestOnDisk().audioFiles.first { $0.audioSource == "Mic D" }?.end) != nil }
            try await wait("B in the guide track") {
                try? sendNext(0.1, buffers: 1, to: sources.last(of: "B"))
                return isInTheGuideTrack(b)
            }
            #expect(try manifestOnDisk().audioFiles.first { $0.audioSource == "Mic B" }?.delays.map(\.delay) == [0])
            _ = await stop()
        }

        /// The anchor first, an Osmo-like late microphone, and a later input, the default microphone, measured
        /// against it: the anchor's audio delay changing from 558 ms to 470 ms later is followed by the 60 s rule, and the mix
        /// places the anchor by it (D80, rec9).
        @Test func theAnchorsChangingAudioDelayIsFollowedThoughAnotherInputIsTheDefault() async throws {
            cameras.connected.withLock { $0 = [Self.camera] }
            let inputs = ["O", "M"].map { AudioInputInfo(name: "Mic \($0)", channelCount: 1, isDefault: $0 == "M", transport: .usb, uid: $0) }
            var watch = CameraFrameWatch()
            watch.firstFrameLimit = .seconds(600)
            try start(cameraMode: .real, cameraFrameWatch: watch, inputs: inputs)
            try await wait("the audio inputs' captures") { sources.byUID.withLock { $0.count } == 2 }
            try await startAudioFiles(["O"], "O's file", count: 1)
            try await startAudioFiles(["M"], "M's file", count: 2)
            try feedDelayedNoise(["O": 0, "M": -0.558])
            for _ in 0..<3 { await recorder.measureAudioDelays() }
            try feedDelayedNoise(["O": 0, "M": -0.470])
            for _ in 0..<4 { await recorder.measureAudioDelays() }
            let files = try manifestOnDisk().audioFiles
            #expect(files.first { $0.audioSource == "Mic O" }?.delays.map(\.delay) == [0])
            let m = try #require(files.first { $0.audioSource == "Mic M" }?.delays.map(\.delay))
            #expect(abs((m.first ?? 0) + 0.558) < 0.002)
            #expect(abs((m.last ?? 0) + 0.470) < 0.002)
            #expect(recorder.status().rows.dropLast().last?.clockDrift.hasSuffix("synced 470 ms") == true)
            // The earliest input, the mix's zero, shows its sync too (D86).
            #expect(recorder.status().rows.filter { $0.clockDrift.hasSuffix("synced 0 ms") }.count == 1)
            _ = await stop()
        }

        /// The anchor's file ending on a gap, its end told before its next file starts and no other input
        /// holding an audio delay, keeps the anchor the reference: nothing starts over, and it stays in the mix
        /// (D80). Only no audio or its capture ending hands the reference on.
        @Test func theAnchorsFileEndingOnAGapStartsNothingOver() async throws {
            let (r, _) = try await startTwoInputs()
            #expect(isInTheGuideTrack(r))
            var end = try #require(try manifestOnDisk().audioFiles.first { $0.audioSource == "Mic R" })
            end.end = end.start + 0.5
            end.state = .finalized
            recorder.audioFileEnded(AudioFileEnd(file: end, error: nil))
            await recorder.measureAudioDelays()
            try sendNext(0.1, buffers: 2, to: sources.last(of: "R"))
            try await Task.sleep(for: .milliseconds(50))
            #expect(isInTheGuideTrack(r))
            let files = try manifestOnDisk().audioFiles
            #expect(files.first { $0.audioSource == "Mic R" }?.delays.map(\.delay) == [0])
            #expect(files.first { $0.audioSource == "Mic A" }?.delays.isEmpty == true)
            _ = await stop()
            let log = try String(contentsOf: recorder.folder.appending(path: RecordingNames.recordingLog), encoding: .utf8)
            #expect(log.contains("not measured, the reference \(end.name) has no file open"))
        }

        /// The earliest input's file ending on no audio, its capture going on, leaves the others where the mix
        /// placed them (D80).
        @Test func theEarliestInputsFileEndingOnNoAudioMovesNoOtherInput() async throws {
            _ = try await startTwoInputs()
            try feedDelayedNoise(["R": 0, "A": -0.5])
            await recorder.measureAudioDelays()
            func referenceRow() -> String? { recorder.status().rows.dropLast().last?.clockDrift }
            try await wait("R placed later") { referenceRow()?.hasSuffix("synced 500 ms") == true }
            // The anchor's audio delay is 0; its mouse-over tells the placement, nothing about how it came about.
            #expect(recorder.status().rows.dropLast().last?.details.hasSuffix(
                "\nPlaced 500 ms earlier in the guide track, in line with the earliest microphone") == true)
            let buffersOfNoAudio = Int(RecorderValues.noAudioTime.nanoseconds * Int64(RecorderValues.audioSampleRate) / 1_000_000_000)
                / samplesPerBuffer
            try sendNext(0, buffers: buffersOfNoAudio + 10, to: sources.last(of: "A"))
            try await wait("A's file's end") { (try? manifestOnDisk().audioFiles.first { $0.audioSource == "Mic A" }?.end) != nil }
            #expect(referenceRow()?.hasSuffix("synced 500 ms") == true)
            _ = await stop()
        }

        /// The recorder's own timer measures the audio delays, every `audioDelayInterval` (D77).
        @Test func theTimerMeasuresTheAudioDelays() async throws {
            cameras.connected.withLock { $0 = [Self.camera] }
            let inputs = ["R", "A"].map { AudioInputInfo(name: "Mic \($0)", channelCount: 1, isDefault: $0 == "R", transport: .usb, uid: $0) }
            var watch = CameraFrameWatch()
            watch.firstFrameLimit = .seconds(600)
            try start(cameraMode: .real, cameraFrameWatch: watch, inputs: inputs, audioDelayInterval: .milliseconds(50))
            try await wait("the audio inputs' captures") { sources.byUID.withLock { $0.count } == 2 }
            try await startAudioFiles(["R", "A"])
            try feedDelayedNoise(["R": 0, "A": 0.5])
            try await wait("A's audio delay") {
                (try? manifestOnDisk().audioFiles.first { $0.audioSource == "Mic A" }?.delays.isEmpty) == false
            }
            _ = await stop()
        }

        /// R the reference and A, both recorded with a camera so the guide tracks exist, their files started.
        private func startTwoInputs() async throws -> (r: String, a: String) {
            try await startInputs(["R", "A"])
            return (SourceLabel.audioInput(1, name: "Mic R"), SourceLabel.audioInput(2, name: "Mic A"))
        }

        /// `uids`, the first the reference, named "Mic <uid>", recorded with a camera, their files started. The
        /// camera sends no frame, so its first-frame limit is out of reach of a slow runner's test.
        private func startInputs(_ uids: [String]) async throws {
            cameras.connected.withLock { $0 = [Self.camera] }
            let inputs = uids.map { AudioInputInfo(name: "Mic \($0)", channelCount: 1, isDefault: $0 == uids[0], transport: .usb, uid: $0) }
            var watch = CameraFrameWatch()
            watch.firstFrameLimit = .seconds(600)
            try start(cameraMode: .real, cameraFrameWatch: watch, inputs: inputs)
            try await wait("the audio inputs' captures") { sources.byUID.withLock { $0.count } == uids.count }
            try await startAudioFiles(uids)
        }

        /// An input early against the others beyond the limit is not mixed either, its row saying so (D90).
        @Test func anAudioInputEarlyBeyondTheLimitIsNotMixedItsRowSayingSo() async throws {
            try await startInputs(["R", "A", "B"])
            let a = SourceLabel.audioInput(2, name: "Mic A")
            try feedDelayedNoise(["R": 0, "A": -0.9, "B": 0])
            await recorder.measureAudioDelays()
            try sendNext(0.1, buffers: 3, to: sources.last(of: "A"))
            try await Task.sleep(for: .milliseconds(50))
            #expect(!isInTheGuideTrack(a))
            #expect(rowText(of: "A")?.hasSuffix("not in the guide track, 900 ms from the others") == true, "\(String(describing: rowText(of: "A")))")
            #expect(recorder.problemLines().isEmpty)
            _ = await stop()
        }

        /// Only the reference is in the guide track at the start; another input joins at its first counted
        /// window, placed by its audio delay, its row saying so; within the limit it stays (D80).
        @Test func anAudioInputJoinsTheGuideTrackPlacedByItsAudioDelay() async throws {
            let (r, a) = try await startTwoInputs()
            #expect(isInTheGuideTrack(r))
            #expect(!isInTheGuideTrack(a))
            #expect(recorder.status().rows.map(\.clockDrift).last?.hasSuffix("not synced yet") == true)
            try feedDelayedNoise(["R": 0, "A": 0.5])
            await recorder.measureAudioDelays()
            try await wait("A in the guide track") {
                try? sendNext(0.1, buffers: 1, to: sources.last(of: "A"))
                return isInTheGuideTrack(a)
            }
            #expect(recorder.status().rows.map(\.clockDrift).last?.hasSuffix("synced 500 ms") == true)
            let delays = try #require(try manifestOnDisk().audioFiles.first { $0.audioSource == "Mic A" }?.delays)
            #expect(delays.count == 1)
            #expect(abs((delays.first?.delay ?? 0) - 0.5) < 0.002)
            #expect(recorder.problemLines().isEmpty)
            _ = await stop()
        }

        private func isInTheGuideTrack(_ label: String) -> Bool { recorder.guides.isMixed(source: label, in: .audioInputs) }

        /// The status window's audio delay cell, after the clock drift, of the input `uid`.
        private func rowText(of uid: String) -> String? {
            recorder.status().rows.first { $0.audioSource == .input(uid) }?.clockDrift
        }

        /// An input whose first counted window puts it 0.9 s after the reference is not mixed in the "Audio inputs"
        /// guide track, its own file going on: its row says so, and there is no event, no problem line, no Dock
        /// bounce, badge or count; its next file, carrying its audio delay over, is not mixed either (D90).
        @Test func anAudioInputBeyondTheLimitIsNotMixedOnlyItsRowSayingSo() async throws {
            let (r, a) = try await startTwoInputs()
            #expect(!isInTheGuideTrack(a))
            try feedDelayedNoise(["R": 0, "A": 0.9])
            await recorder.measureAudioDelays()
            try sendNext(0.1, buffers: 3, to: sources.last(of: "A"))
            try await Task.sleep(for: .milliseconds(50))
            #expect(!isInTheGuideTrack(a))
            #expect(isInTheGuideTrack(r))
            #expect(rowText(of: "A")?.hasSuffix("not in the guide track, 900 ms from the others") == true, "\(String(describing: rowText(of: "A")))")
            #expect(try manifestOnDisk().events.filter { $0.event == .audioInputLeftTheGuideTrack }.isEmpty)
            #expect(recorder.problemLines().isEmpty)
            #expect(try manifestOnDisk().problems.isEmpty)
            #expect(observer.problems.isEmpty)
            let delaysOfA = try delays(of: "A")
            #expect(delaysOfA.count == 1 && abs((delaysOfA.first ?? 0) - 0.9) < 0.002, "\(delaysOfA)")

            let buffersOfNoAudio = Int(RecorderValues.noAudioTime.nanoseconds * Int64(RecorderValues.audioSampleRate) / 1_000_000_000)
                / samplesPerBuffer
            try sendNext(0, buffers: buffersOfNoAudio + 10, to: sources.last(of: "A"))
            try await wait("A's file's end") { (try? manifestOnDisk().audioFiles.first { $0.audioSource == "Mic A" }?.end) != nil }
            try sendNext(0.1, buffers: 1, to: sources.last(of: "A"))
            try await wait("A's next file") { (try? manifestOnDisk().audioFiles.filter { $0.audioSource == "Mic A" }.count) == 2 }
            try sendNext(0.1, buffers: 3, to: sources.last(of: "A"))
            try await Task.sleep(for: .milliseconds(50))
            #expect(!isInTheGuideTrack(a))
            #expect(rowText(of: "A")?.hasSuffix("not in the guide track, 900 ms from the others") == true, "\(String(describing: rowText(of: "A")))")
            #expect(recorder.problemLines().isEmpty)
            _ = await stop()
            let log = try recordingLog()
            #expect(log.contains(": not in the guide track with the carried-over audio delay"), "\(log)")
        }

        /// A false first counted window leaves an input unmixed; the median of its first 3 counted windows in sync
        /// mixes it, and the median of the latest minute late again unmixes it, each time without a problem (D90).
        @Test func anAudioInputUnmixedOnAFalseFirstWindowIsMixedOnceItsMedianFits() async throws {
            let (_, a) = try await startTwoInputs()
            try feedDelayedNoise(["R": 0, "A": 0.9])
            await recorder.measureAudioDelays()
            try feedDelayedNoise(["R": 0, "A": 0])
            for _ in 0..<3 { await recorder.measureAudioDelays() }
            try await wait("A in the guide track") {
                try? sendNext(0.1, buffers: 1, to: sources.last(of: "A"))
                return isInTheGuideTrack(a)
            }
            #expect(rowText(of: "A")?.hasSuffix("synced 0 ms") == true, "\(String(describing: rowText(of: "A")))")
            try feedDelayedNoise(["R": 0, "A": 0.9])
            for _ in 0..<3 { await recorder.measureAudioDelays() }
            try await wait("A out of the guide track again") {
                try? sendNext(0.1, buffers: 1, to: sources.last(of: "A"))
                return !isInTheGuideTrack(a)
            }
            #expect(recorder.problemLines().isEmpty)
            #expect(try manifestOnDisk().problems.isEmpty)
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
            try feedDelayedNoise(["R": 0, "A": 0.2])
            let stopping = Task { await recorder.stop() }
            try await Task.sleep(for: .milliseconds(200))
            for _ in 0..<3 { await recorder.measureAudioDelays() }
            let summary = await stopping.value
            // Only the anchor's own 0, listed at its file's start; nothing measured.
            #expect(Dictionary(uniqueKeysWithValues: summary.manifest.audioFiles.map { ($0.audioSource, $0.delays.map(\.delay)) })
                == ["Mic R": [0], "Mic A": []])
        }

        /// A measurement already running when Stop begins changes the recording no more (D77): the
        /// measuring task reaches its wait for the windows before the stopping task starts, both queued
        /// on the main actor in this order. Its first counted window would set the audio delay (D80).
        @Test func anAudioDelayMeasuredWhileStopBeginsIsNotRecorded() async throws {
            cameras.connected.withLock { $0 = [Self.camera] }
            let inputs = ["R", "A"].map { AudioInputInfo(name: "Mic \($0)", channelCount: 1, isDefault: $0 == "R", transport: .usb, uid: $0) }
            try start(cameraMode: .real, inputs: inputs)
            let camera = try #require(cameras.last)
            camera.stopTakes.withLock { $0 = .seconds(1) }
            try await wait("the audio inputs' captures") { sources.byUID.withLock { $0.count } == 2 }
            try await startAudioFiles(["R", "A"])
            try feedDelayedNoise(["R": 0, "A": 0.2])
            let measuring = Task { await recorder.measureAudioDelays() }
            let stopping = Task { await recorder.stop() }
            await measuring.value
            let summary = await stopping.value
            // Only the anchor's own 0, listed at its file's start; nothing measured.
            #expect(Dictionary(uniqueKeysWithValues: summary.manifest.audioFiles.map { ($0.audioSource, $0.delays.map(\.delay)) })
                == ["Mic R": [0], "Mic A": []])
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
            let before = recorder.elapsedSeconds
            // The time a busy machine takes between a test's clock reading and the recorder's.
            try await Task.sleep(for: .milliseconds(100))
            let summary = await stop()
            let stopped = recorder.elapsedSeconds
            let end = try #require(summary.manifest.cameraFiles.first?.end)
            // The stream stopped one second after the recorder asked, so a file that ended when the
            // stream stopped, or repeated its last frame for the wait, ends after `stopped - 1`.
            #expect(end <= stopped - 1)
            #expect(end > before - 0.2)
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
            // Nothing a person can do about a stall: no call to action (D84).
            #expect(observer.callsToAction.isEmpty)
            try await sendFrames(camera, until: "the stall's end") { (try? manifestOnDisk().events.count) == 2 }
            let ended = try #require(try manifestOnDisk().events.last)
            #expect(ended.event == .cameraStallEnded)
            #expect(try #require(ended.length) >= 0.2)
            #expect(recorder.status().rows.contains { $0.source == .camera(1, name: "Stand-in camera") && $0.state == "recording" })
            let summary = await stop()
            #expect(cameras.opened.withLock { $0.count } == 1)
            #expect(summary.manifest.cameraFiles.map(\.state) == [.finalized])
            #expect(summary.manifest.problems.count == 1)
            // A stall loses picture (D47), but asks for no report (D84).
            #expect(summary.manifest.result == .problems)
            #expect(summary.endedWithError && !summary.asksToReportIt)
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
        private func failedEnd(
            of file: RecordingManifest.CameraFile, lost: String? = nil, isDiskFull: Bool = false
        ) -> VideoFileEnd<RecordingManifest.CameraFile> {
            var file = file
            file.state = .notFinalized
            return VideoFileEnd(
                file: file, error: VideoFileWriterError(description: "cannot write \(file.name)", isDiskFull: isDiskFull), lost: lost)
        }

        /// A camera whose writer failed starts its new capture at once, no back-off: its row never waits to
        /// retry; failing again within `writerFailedAgainWithin` of that, it backs off (D88).
        @Test func aCameraWhoseWriterFailedStartsAgainAtOnceThenBacksOff() async throws {
            cameras.connected.withLock { $0 = [Self.camera] }
            try start(cameraMode: .real)
            let first = try #require(cameras.last)
            try await sendFrames(first, until: "the camera file") { (try? manifestOnDisk().cameraFiles.count) == 1 }
            let file = try #require(try manifestOnDisk().cameraFiles.first)
            func cameraState() -> String? { recorder.status().rows.first { $0.source == .camera(1, name: "Stand-in camera") }?.state }
            recorder.cameraCaptureEnded(
                uniqueID: "StandInCamera", captureNumber: 1, camera: "Stand-in camera", reason: .writerFailed("cannot write"),
                file: failedEnd(of: file))
            #expect(cameraState() != "failed, retrying")
            try await wait("the camera's new capture") { cameras.opened.withLock { $0.count } == 2 }
            let second = try #require(cameras.last)
            try await sendFrames(second, until: "the second camera file") { (try? manifestOnDisk().cameraFiles.count) == 2 }
            let newer = try #require(try manifestOnDisk().cameraFiles.last)
            recorder.cameraCaptureEnded(
                uniqueID: "StandInCamera", captureNumber: 2, camera: "Stand-in camera", reason: .writerFailed("cannot write"),
                file: failedEnd(of: newer))
            #expect(cameraState() == "failed, retrying")
            _ = await stop()
        }

        /// An audio source whose writer failed starts again at once; failing again within
        /// `writerFailedAgainWithin` of that, it waits its back-off, 1 s (D88).
        @Test func anAudioSourceWhoseWriterFailedStartsAgainAtOnceThenBacksOff() async throws {
            try start()
            try await wait("the audio input's capture") { sources.byUID.withLock { $0[uid]?.count } == 1 }
            try #require(sources.last(of: uid)).lose(.writerFailed("cannot write"))
            try await wait("the restart", seconds: 1) { sources.byUID.withLock { $0[uid]?.count } == 2 }
            try #require(sources.last(of: uid)).lose(.writerFailed("cannot write"))
            try await Task.sleep(for: .milliseconds(500))
            #expect(sources.byUID.withLock { $0[uid]?.count } == 2)
            try await wait("the restart after the back-off") { sources.byUID.withLock { $0[uid]?.count } == 3 }
            _ = await stop()
        }

        /// A camera file a full disk cut short: its lost tail is a red line without a call to action of its own, and
        /// the recording asks for no report (D84).
        @Test func aCameraFileAFullDiskCutShortAsksForNoReport() async throws {
            cameras.connected.withLock { $0 = [Self.camera] }
            try start(cameraMode: .real)
            let camera = try #require(cameras.last)
            try await sendFrames(camera, until: "the camera file") { (try? manifestOnDisk().cameraFiles.count) == 1 }
            let file = try #require(try manifestOnDisk().cameraFiles.first)
            recorder.cameraCaptureEnded(
                uniqueID: "StandInCamera", captureNumber: 1, camera: "Stand-in camera", reason: .diskFull,
                file: failedEnd(of: file, lost: "its last 2 s", isDiskFull: true))
            let lost = try #require(recorder.problemLines().first { $0.text.hasPrefix("File \(file.name) incomplete") })
            #expect(lost.isRed)
            #expect(observer.callsToAction.allSatisfy { !$0.problem.contains("incomplete") && !$0.problem.contains("its last 2 s") })
            #expect(observer.callsToAction.count == 1)
            let summary = await stop()
            #expect(summary.manifest.cameraFiles.first?.state == .notFinalized)
            #expect(!summary.asksToReportIt)
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

        /// No audio right after a gap is the input broken by it: a red line saying what to do, told as a
        /// problem, orange in the past once its sound returns (D81).
        @Test func noAudioRightAfterAGapIsARedProblemUntilTheSoundReturns() async throws {
            try start()
            let buffersOfNoAudio = Int(RecorderValues.noAudioTime.nanoseconds * Int64(RecorderValues.audioSampleRate) / 1_000_000_000)
                / samplesPerBuffer
            let origin = Int64(readClocks().host)
            try send(0.25, buffers: 3, from: origin)
            // A gap of 10 buffers, about 0.33 s, then only zeros.
            try send(0, buffers: buffersOfNoAudio + 10, after: 13, from: origin)
            try await wait("the problem") { !observer.problems.isEmpty }
            #expect(try manifestOnDisk().events.map(\.event) == [.audioInputGap, .noAudioStarted])
            #expect(recorder.problemLines() == [ProblemLine(
                text: "Audio 1 \(name) sends only silence since its gaps at 0:00; unplug and plug it in again", isRed: true)])
            #expect(observer.callsToAction.map(\.problem) == ["The audio input \(name) sends only silence since its gaps at 0:00"])
            #expect(try manifestOnDisk().problems.map(\.problem) == ["The audio input \(name) sends only silence since its gaps at 0:00"])
            try send(0.25, buffers: 10, after: buffersOfNoAudio + 23, from: origin)
            try await wait("the sound") { recorder.status().rows.first?.state == "recording" }
            let past = try #require(recorder.problemLines().first)
            #expect(!past.isRed)
            #expect(past.text.wholeMatch(of: /Audio 1 .+ sent only silence for .+ after its gaps at 0:00, recovered/) != nil, "\(past.text)")
            _ = await stop()
            let log = try String(contentsOf: recorder.folder.appending(path: RecordingNames.recordingLog), encoding: .utf8)
            #expect(log.contains("Audio 1 \(name): no audio since 0:00, right after its gap at 0:00: a red problem (D81)"))
        }

        /// A source that fails and does not come back calls to action once it lasted `unrecoveredAfter`, and the
        /// recording then asks to report it (D84). The stand-in's restart takes 1 s, longer than the wait here.
        @Test func aSourceFailingUnrecoveredCallsToActionAndAsksToReportIt() async throws {
            try start(unrecoveredAfter: .milliseconds(300))
            try send(0.25, buffers: 2)
            try await wait("the file") { (try? manifestOnDisk().audioFiles.count) == 1 }
            source.lose(.captureFailed("the stand-in failed"))
            try await wait("the call to action", seconds: 10) { !observer.callsToAction.isEmpty }
            #expect(observer.callsToAction.map(\.problem) == ["The audio input \(name) failed"])
            let summary = await stop()
            #expect(summary.asksToReportIt)
        }

        /// A source captured again before `unrecoveredAfter` stays quiet, at Stop too (D84).
        @Test func aSourceCapturedAgainBeforeTheWaitStaysQuiet() async throws {
            try start(unrecoveredAfter: .seconds(60))
            try send(0.25, buffers: 2)
            try await wait("the file") { (try? manifestOnDisk().audioFiles.count) == 1 }
            source.lose(.captureFailed("the stand-in failed"))
            try await wait("the problem") { !observer.problems.isEmpty }
            try await wait("the restart") { sources.count == 2 }
            try await wait("the new file") {
                try? sendNext(0.25, buffers: 1, to: sources.last)
                return (try? manifestOnDisk().audioFiles.count) == 2
            }
            let summary = await stop()
            #expect(observer.callsToAction.isEmpty)
            #expect(!summary.asksToReportIt)
        }

        /// A source still failing at Stop makes the recording ask to report it, without waiting for
        /// `unrecoveredAfter`; at Stop that bounces nothing and sets no badge (D84).
        @Test func aSourceStillFailingAtStopAsksToReportIt() async throws {
            try start(unrecoveredAfter: .seconds(60))
            try send(0.25, buffers: 2)
            try await wait("the file") { (try? manifestOnDisk().audioFiles.count) == 1 }
            source.lose(.captureFailed("the stand-in failed"))
            try await wait("the problem") { !observer.problems.isEmpty }
            #expect(observer.callsToAction.isEmpty)
            let summary = await stop()
            #expect(observer.callsToAction.isEmpty)
            #expect(summary.asksToReportIt)
        }

        /// An audio source ended by a full disk falls under the disk-full call to action, free up disk space, at
        /// once, and asks for no report (D84).
        @Test func anAudioSourceEndedByAFullDiskCallsToFreeUpDiskSpace() async throws {
            try start()
            try send(0.25, buffers: 2)
            try await wait("the file") { (try? manifestOnDisk().audioFiles.count) == 1 }
            source.lose(.diskFull)
            try await wait("the problem") { !observer.problems.isEmpty }
            #expect(observer.callsToAction.map(\.problem) == ["The audio file of \(name) ended"])
            #expect(recorder.problemLines().first?.text.hasPrefix("Disk full since ") == true)
            let summary = await stop()
            #expect(!summary.problemsAskToReportIt)
        }

        /// An audio file whose writer failed because the disk is full is the full disk, free up disk space, told
        /// once with its capture's end; left not finalized by it, the recording asks for no report (D84).
        @Test func anAudioFileAFullDiskLeftNotFinalizedAsksForNoReport() async throws {
            try start()
            try send(0.25, buffers: 2)
            try await wait("the file") { (try? manifestOnDisk().audioFiles.count) == 1 }
            source.lose(.diskFull)
            try await wait("the capture's end") { (try? manifestOnDisk().events.contains { $0.event == .diskFull }) == true }
            var file = try #require(try manifestOnDisk().audioFiles.first)
            file.end = file.end ?? file.start + 0.5
            file.state = .notFinalized
            var end = AudioFileEnd(file: file, error: AudioFileWriterError(POSIXError(.ENOSPC), while: "cannot write \(file.name)"))
            end.lost = "its last 0.5 s were not written"
            recorder.audioFileEnded(end)
            // Its lost tail is still a red line, but the full disk is the one call to action (D84).
            #expect(observer.callsToAction.map(\.problem) == ["The audio file of \(name) ended"])
            #expect(recorder.problemLines().map(\.text).filter { $0.hasPrefix("File ") }.map { $0.hasPrefix("File \(file.name) incomplete") }
                == [true])
            let summary = await stop()
            #expect(summary.manifest.audioFiles.map(\.state) == [.notFinalized])
            #expect(!summary.asksToReportIt)
        }

        /// A capture ending while its input has no audio ends that no audio with it: its line turns to the past,
        /// stopped, and its next capture records its sound (D69, D81).
        @Test func aCaptureEndingWhileItsInputHasNoAudioEndsItsNoAudio() async throws {
            try start()
            let buffersOfNoAudio = Int(RecorderValues.noAudioTime.nanoseconds * Int64(RecorderValues.audioSampleRate) / 1_000_000_000)
                / samplesPerBuffer
            let origin = Int64(readClocks().host)
            try send(0.25, buffers: 3, from: origin)
            try send(0, buffers: buffersOfNoAudio + 10, after: 13, from: origin)
            try await wait("the problem") { !observer.problems.isEmpty }
            #expect(recorder.status().rows.first?.state == "no audio")
            source.lose(.captureFailed("the stand-in failed"))
            try await wait("the restart") { sources.count == 2 }
            try await wait("the sound") {
                try? sendNext(0.25, buffers: 1, to: sources.last)
                return recorder.status().rows.first?.state == "recording"
            }
            let past = try #require(recorder.problemLines().first { $0.text.hasPrefix("Audio 1") })
            #expect(!past.isRed)
            #expect(past.text.wholeMatch(of: /Audio 1 .+ sent only silence for .+ after its gaps at 0:00, stopped/) != nil, "\(past.text)")
            _ = await stop()
        }

        /// Another input's gaps are no gaps of this one, even under the same name: they are found by its
        /// device (D81).
        @Test func anotherInputsGapsUnderTheSameNameMakeNoProblem() async throws {
            let inputs = ["X", "Y"].map { AudioInputInfo(name: "Mic", channelCount: 1, isDefault: $0 == "X", transport: .usb, uid: $0) }
            try start(inputs: inputs)
            try await wait("the audio inputs' captures") { sources.byUID.withLock { $0.count } == 2 }
            let buffersOfNoAudio = Int(RecorderValues.noAudioTime.nanoseconds * Int64(RecorderValues.audioSampleRate) / 1_000_000_000)
                / samplesPerBuffer
            let origin = Int64(readClocks().host)
            try send(0.25, buffers: 3, to: sources.last(of: "X"), from: origin)
            try send(0.25, buffers: 1, after: 13, to: sources.last(of: "X"), from: origin)
            try await wait("X's gap") { (try? manifestOnDisk().events.map(\.event)) == [.audioInputGap] }
            try send(0.25, buffers: 3, to: sources.last(of: "Y"), from: origin)
            try send(0, buffers: buffersOfNoAudio + 10, after: 3, to: sources.last(of: "Y"), from: origin)
            try await wait("Y's no audio") { (try? manifestOnDisk().events.contains { $0.event == .noAudioStarted }) == true }
            try await Task.sleep(for: .milliseconds(50))
            #expect(observer.problems.isEmpty)
            #expect(recorder.problemLines().isEmpty)
            _ = await stop()
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
            #expect(!summary.asksToReportIt)
            #expect(observer.problems.isEmpty)
            #expect(observer.callsToAction.isEmpty)
            #expect(observer.eventLines.allSatisfy { !$0.isFailure })
            let log = try String(contentsOf: recorder.folder.appending(path: RecordingNames.recordingLog), encoding: .utf8)
            #expect(log.contains("Audio 1 \(name): no audio since 0:00, no gap within 10 s before: no problem (D81)"))
        }
    }
}

/// The noise and the sounds built from it that `feed` and `feedDelayedNoise` send, each built once per process:
/// pure functions of their seed and length.
private enum FedTables {
    private static let tables = Mutex<[String: [Float]]>([:])

    static func cached(_ key: String, _ make: () -> [Float]) -> [Float] {
        if let table = tables.withLock({ $0[key] }) { return table }
        let table = make()
        tables.withLock { $0[key] = table }
        return table
    }

    static func noise(seed start: UInt64) -> [Float] {
        cached("noise \(start)") {
            var seed = start
            return (0..<(15 * RecorderValues.audioSampleRate)).map { _ -> Float in
                seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
                return Float(Int64(bitPattern: seed >> 11) % 2001 - 1000) / 2000
            }
        }
    }

    static func bursts(seed: UInt64, phase: Int, slot: Int) -> [Float] {
        cached("bursts \(seed) \(phase) \(slot)") {
            noise(seed: seed).enumerated().map { (($0.offset + phase) / slot) % 3 == 0 ? $0.element : $0.element / 20 }
        }
    }
}
