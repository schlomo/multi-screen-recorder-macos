import CoreMedia
import Foundation
import RecorderLogic
import Synchronization
import Testing
@testable import RecorderCore

extension GlobalRecordingLog {
    /// A recorder's wiring, audio only with one stand-in audio input and its
    /// stand-in input volume: what reaches the observer, the recording
    /// manifest and the status window. Nested in `GlobalRecordingLog`: a recorder
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
        private var recorder: Recorder!
        private let samplesPerBuffer = 1600

        init() throws {
            home = FileManager.default.temporaryDirectory.appending(path: "RecorderTests-\(UUID().uuidString)", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        }

        deinit {
            try? FileManager.default.removeItem(at: home)
        }

        private func start() throws {
            var settings = Settings.defaults
            settings.auto = false
            settings.resolution = RecordingResolution.none
            settings.audioMode = .defaultMicrophone
            settings.systemAudio = false
            settings.outputFolder = home.path(percentEncoded: false)
            let input = AudioInputInfo(name: name, channelCount: 1, isDefault: true, transport: .usb, uid: uid)
            let sources = sources
            let volume = volume
            let devices = RecorderDevices(
                audioInputs: { [input] },
                audioInputSource: { _ in
                    let source = AudioCaptureTests.StandInSource()
                    sources.list.withLock { $0.append(source) }
                    return source
                },
                inputVolume: { _, _ in volume })
            let facts = ReadyCheckFacts(
                screenRecording: nil, microphoneGranted: true, screens: .success([]), audioInputs: .success([input]),
                outputFolder: .unusable("not probed by the tests"))
            recorder = try Recorder(
                settings: settings, homeFolder: home, app: "Multi Screen Recorder (tests)", readyCheckFacts: facts, observer: observer,
                devices: devices)
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
