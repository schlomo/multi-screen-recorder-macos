import CoreMedia
import Foundation
import RecorderLogic
import Synchronization
import Testing
@testable import RecorderCore

/// An audio capture with a stand-in source and a stand-in writer: what
/// reaches the recording manifest when a file ends, the capture stops, the
/// source is lost or the writer is slow.
@Suite struct AudioCaptureTests {
    final class StandInSource: AudioBufferSource, @unchecked Sendable {
        private var queue: DispatchQueue?
        private var deliver: (@Sendable (CMSampleBuffer) -> Void)?
        private var ended: (@Sendable (AudioTracker.CaptureEnd) -> Void)?

        func start(
            queue: DispatchQueue, deliver: @escaping @Sendable (CMSampleBuffer) -> Void,
            ended: @escaping @Sendable (AudioTracker.CaptureEnd) -> Void
        ) {
            self.queue = queue
            self.deliver = deliver
            self.ended = ended
        }

        func stop() async {}

        /// Hands a buffer to the capture on its queue and waits until it took it.
        func send(_ buffer: CMSampleBuffer) {
            queue!.sync { deliver!(buffer) }
        }

        func lose(_ end: AudioTracker.CaptureEnd) {
            ended!(end)
        }
    }

    final class StandInWriter: AudioFileWriting, @unchecked Sendable {
        private let state = Mutex<(isReady: Bool, samples: Int64, silence: Int64, endPosition: Int64??)>((true, 0, 0, nil))

        var isReady: Bool {
            get { state.withLock { $0.isReady } }
            set { state.withLock { $0.isReady = newValue } }
        }

        var samples: Int64 { state.withLock { $0.samples } }
        var endPosition: Int64?? { state.withLock { $0.endPosition } }

        func append(_ channels: [[Float]], at position: Int64) throws(AudioFileWriterError) -> Bool {
            state.withLock { state in
                guard state.isReady else { return false }
                state.samples += Int64(channels[0].count)
                return true
            }
        }

        func appendSilence(_ count: Int64, at position: Int64) throws(AudioFileWriterError) -> Bool {
            state.withLock { state in
                guard state.isReady else { return false }
                state.silence += count
                return true
            }
        }

        func finish(endPosition: Int64?) async throws(AudioFileWriterError) {
            state.withLock { $0.endPosition = .some(endPosition) }
        }
    }

    final class Reported: @unchecked Sendable {
        private let state = Mutex<(started: [String], ended: [AudioFileEnd], events: [RecordingEvent], end: AudioTracker.CaptureEnd?)>(
            ([], [], [], nil))

        var started: [String] { state.withLock { $0.started } }
        var ended: [AudioFileEnd] { state.withLock { $0.ended } }
        var events: [RecordingEvent] { state.withLock { $0.events } }
        var captureEnd: AudioTracker.CaptureEnd? { state.withLock { $0.end } }

        var reports: AudioCaptureReports {
            AudioCaptureReports(
                fileStarted: { file in self.state.withLock { $0.started.append(file.name) } },
                fileEnded: { end in self.state.withLock { $0.ended.append(end) } },
                event: { event in self.state.withLock { $0.events.append(event) } },
                ended: { end in self.state.withLock { $0.end = end } })
        }

        /// Waits until the capture said it ended, for at most 5 s.
        func waitForCaptureEnd() async throws -> AudioTracker.CaptureEnd {
            for _ in 0..<500 {
                if let end = captureEnd { return end }
                try await Task.sleep(for: .milliseconds(10))
            }
            Issue.record("the capture did not end")
            throw CancellationError()
        }
    }

    private let reading = readClocks()
    private let source = StandInSource()
    private let writer = StandInWriter()
    private let reported = Reported()
    private let samplesPerBuffer = 1600

    private func capture(_ id: AudioTracker.SourceID = .input("Razer"), drainTimeout: Duration = .seconds(2)) -> AudioCapture {
        let context = RecordingContext(
            folder: FileManager.default.temporaryDirectory, started: Date(), timeZone: TimeZone(identifier: "Europe/Berlin")!,
            clock: SharedClock(reading: reading), app: "Multi Screen Recorder (tests)")
        let writer = writer
        let capture = AudioCapture(
            id: id, number: id == .systemAudio ? 0 : 2, name: id == .systemAudio ? "System audio" : "Razer Seiren V3 Mini", source: source, context: context,
            guides: GuideTrackFeed(tracks: [], now: { 0 }), reports: reported.reports, drainTimeout: drainTimeout,
            makeWriter: { _, _, _ in writer })
        capture.start()
        return capture
    }

    /// A buffer of `channels` channels whose first sample is `at` nanoseconds from t0.
    private func buffer(at nanoseconds: Int64, channels: Int = 1) throws -> CMSampleBuffer {
        let samples = Array(repeating: [Float](repeating: 0.25, count: samplesPerBuffer), count: channels)
        let time = CMTime(value: CMTimeValue(reading.host) + nanoseconds, timescale: 1_000_000_000)
        return try pcmSample(samples[...], format: pcmFormat(channels: channels), at: time)
    }

    /// The nanoseconds of the `index`th buffer of a run without gaps.
    private func time(ofBuffer index: Int) -> Int64 {
        Int64(index * samplesPerBuffer) * 1_000_000_000 / Int64(RecorderValues.audioSampleRate)
    }

    @Test func samplesStillWaitingAtTheEndAreWrittenBeforeTheFileIsFinalized() async throws {
        let capture = capture()
        writer.isReady = false
        for index in 0..<3 { source.send(try buffer(at: time(ofBuffer: index))) }
        #expect(writer.samples == 0)
        let writer = writer
        Task {
            try? await Task.sleep(for: .milliseconds(50))
            writer.isReady = true
        }
        await capture.stop()
        let ends = reported.ended
        #expect(writer.samples == 3 * Int64(samplesPerBuffer))
        #expect(writer.endPosition == .some(3 * Int64(samplesPerBuffer)))
        let end = try #require(ends.first)
        #expect(ends.count == 1)
        #expect(end.error == nil)
        #expect(end.file.state == .finalized)
        #expect(end.file.end == end.file.start + 0.1)
    }

    @Test func samplesTheWriterNeverTookAreNotCountedAndToldAsLost() async throws {
        let capture = capture(drainTimeout: .milliseconds(50))
        source.send(try buffer(at: 0))
        writer.isReady = false
        source.send(try buffer(at: time(ofBuffer: 1)))
        await capture.stop()
        let ends = reported.ended
        let end = try #require(ends.first)
        #expect(writer.endPosition == .some(Int64(samplesPerBuffer)))
        #expect(end.file.end == end.file.start + Double(samplesPerBuffer) / Double(RecorderValues.audioSampleRate))
        #expect(end.error?.description.contains("\(samplesPerBuffer) samples") == true)
        #expect(end.error?.description.contains("lost") == true)
        #expect(end.lostSamples == Int64(samplesPerBuffer))
        // A failure (D47): the result is `problems`.
        let event = try #require(end.events.first)
        #expect(end.events.count == 1)
        #expect(event.event == .audioFileWriterFellBehind)
        #expect(event.event.isFailure)
        #expect(event.audioSource == "Razer Seiren V3 Mini")
        #expect(event.error == end.error?.description)
        #expect(event.at == (end.file.end! * 1000).rounded() / 1000)
    }

    @Test func aFileEndWithNothingLostHasNoEvent() async throws {
        let capture = capture()
        source.send(try buffer(at: 0))
        await capture.stop()
        let ends = reported.ended
        #expect(ends.first?.lostSamples == 0)
        #expect(ends.first?.events.isEmpty == true)
    }

    @Test func theInboxGivesTheReportsInOrderOnce() {
        let inbox = AudioReportInbox()
        inbox.post(.event(RecordingEvent(at: 0, event: .audioInputGap, audioSource: "A")))
        inbox.post(.event(RecordingEvent(at: 1_000_000, event: .audioInputGap, audioSource: "B")))
        let taken = inbox.take().map { report -> String? in
            if case .event(let event) = report { event.audioSource } else { nil }
        }
        #expect(taken == ["A", "B"])
        #expect(inbox.take().isEmpty)
    }

    @Test func stopEndsEveryFileOfTheCapture() async throws {
        let capture = capture()
        source.send(try buffer(at: 0))
        // A gap over the longest filled gap ends the file and starts a new one.
        source.send(try buffer(at: 2_000_000_000))
        #expect(reported.events.map(\.event) == [.audioInputGap])
        #expect(reported.events.first?.audioSource == "Razer Seiren V3 Mini")
        #expect(reported.started.count == 2)
        await capture.stop()
        let ends = reported.ended
        // Each file finishes in its own task, so the order of their ends is not promised.
        #expect(ends.count == reported.started.count)
        #expect(ends.map(\.file.name).sorted() == reported.started.sorted())
        #expect(ends.allSatisfy { $0.file.state == .finalized })
    }

    /// One route only: a file end reported twice would be applied twice,
    /// its `audio file writer fell behind` written and told twice.
    @Test func everyFileEndIsReportedOnceThroughItsReports() async throws {
        let capture = capture(drainTimeout: .milliseconds(10))
        source.send(try buffer(at: 0))
        source.send(try buffer(at: 2_000_000_000))
        writer.isReady = false
        source.send(try buffer(at: 2_000_000_000 + time(ofBuffer: 1)))
        await capture.stop()
        #expect(reported.ended.map(\.file.name) == reported.started)
        #expect(reported.ended.flatMap(\.events).map(\.event) == [.audioFileWriterFellBehind])
    }

    @Test func aCaptureThatEndsByItselfReportsEachFileEndOnce() async throws {
        let capture = capture()
        source.send(try buffer(at: 0))
        source.lose(.disconnected)
        _ = try await reported.waitForCaptureEnd()
        withExtendedLifetime(capture) {}
        #expect(reported.ended.map(\.file.name) == reported.started)
    }

    @Test func aGapFilledWithSilenceGoesToTheWriterAsSilence() async throws {
        let capture = capture()
        source.send(try buffer(at: 0))
        source.send(try buffer(at: time(ofBuffer: 1) + 100_000_000))
        await capture.stop()
        #expect(writer.samples == 2 * Int64(samplesPerBuffer))
        #expect(writer.endPosition == .some(2 * Int64(samplesPerBuffer) + 4800))
    }

    @Test func aLostSourceEndsTheCaptureWithItsFileEnds() async throws {
        let capture = capture()
        source.send(try buffer(at: 0))
        source.lose(.disconnected)
        let end = try await reported.waitForCaptureEnd()
        let files = reported.ended
        withExtendedLifetime(capture) {}
        #expect(end == .disconnected)
        #expect(files.map(\.file.name) == reported.started)
        #expect(files.first?.file.state == .finalized)
    }

    @Test func systemAudioThatIsNotStereoIsACaptureFailure() async throws {
        let capture = capture(.systemAudio)
        source.send(try buffer(at: 0, channels: 1))
        let end = try await reported.waitForCaptureEnd()
        let files = reported.ended
        withExtendedLifetime(capture) {}
        #expect(end == .captureFailed("the system audio came with 1 channels instead of 2"))
        #expect(files.isEmpty)
    }

    @Test func aWriterThatTakesNothingForTheAudioWaitBoundFellBehind() async throws {
        let capture = capture(drainTimeout: .milliseconds(10))
        writer.isReady = false
        let buffers = RecorderValues.audioWaitBoundSeconds * RecorderValues.audioSampleRate / samplesPerBuffer + 2
        for index in 0..<buffers { source.send(try buffer(at: time(ofBuffer: index))) }
        let end = try await reported.waitForCaptureEnd()
        let files = reported.ended
        withExtendedLifetime(capture) {}
        #expect(end == .writerFellBehind)
        #expect(files.first?.error?.description.contains("lost") == true)
    }
}
