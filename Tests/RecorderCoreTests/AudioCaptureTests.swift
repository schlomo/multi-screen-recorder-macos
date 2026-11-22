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
        private let state = Mutex<(
            isReady: Bool, refusalsLeft: Int?, samples: Int64, silence: Int64, endPosition: Int64??, appends: Int, failsAtAppend: Int?,
            taken: [Int]
        )>((true, nil, 0, 0, nil, 0, nil, []))
        private let sound = Mutex<Int64?>(nil)
        /// The first tick of the first file made.
        let firstTick = Mutex<Int64?>(nil)

        /// The position of the first sample taken that is not zero, from the file's first tick.
        var firstSound: Int64? { sound.withLock { $0 } }

        var isReady: Bool {
            get { state.withLock { $0.isReady } }
            set { state.withLock { $0.isReady = newValue } }
        }

        /// Refuses the next `refusals` appends, then takes every one: ready
        /// on an event, never after a time, so a slow machine changes nothing.
        func becomesReady(afterRefusals refusals: Int) {
            state.withLock { $0.refusalsLeft = refusals }
        }

        /// Throws at the `append`th append (1 the first) and every one after it.
        func fails(atAppend append: Int) {
            state.withLock { $0.failsAtAppend = append }
        }

        var refusalsLeft: Int? { state.withLock { $0.refusalsLeft } }
        var appends: Int { state.withLock { $0.appends } }
        var samples: Int64 { state.withLock { $0.samples } }
        /// The samples of each append the writer took, in order.
        var taken: [Int] { state.withLock { $0.taken } }
        var endPosition: Int64?? { state.withLock { $0.endPosition } }

        func append(_ channels: [[Float]], at position: Int64) throws(AudioFileWriterError) -> Bool {
            let fails = state.withLock { state in
                state.appends += 1
                return state.failsAtAppend.map { state.appends >= $0 } ?? false
            }
            if fails { throw AudioFileWriterError(nil, while: "writing a stand-in file") }
            return state.withLock { state in
                if let left = state.refusalsLeft, !state.isReady {
                    state.refusalsLeft = left - 1
                    if left > 0 { return false }
                    state.isReady = true
                }
                guard state.isReady else { return false }
                state.samples += Int64(channels[0].count)
                state.taken.append(channels[0].count)
                if let index = channels[0].firstIndex(where: { $0 != 0 }) {
                    sound.withLock { $0 = $0 ?? position + Int64(index) }
                }
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
        private let state = Mutex<(
            started: [String], ended: [AudioFileEnd], events: [RecordingEvent], clockDrift: [ClockDriftCorrection.Status],
            end: AudioTracker.CaptureEnd?, noAudio: [Bool]
        )>(([], [], [], [], nil, []))

        var started: [String] { state.withLock { $0.started } }
        var ended: [AudioFileEnd] { state.withLock { $0.ended } }
        var events: [RecordingEvent] { state.withLock { $0.events } }
        var clockDrift: [ClockDriftCorrection.Status] { state.withLock { $0.clockDrift } }
        var captureEnd: AudioTracker.CaptureEnd? { state.withLock { $0.end } }
        var noAudio: [Bool] { state.withLock { $0.noAudio } }

        var reports: AudioCaptureReports {
            AudioCaptureReports(
                fileStarted: { file in self.state.withLock { $0.started.append(file.name) } },
                fileEnded: { end in self.state.withLock { $0.ended.append(end) } },
                event: { event in self.state.withLock { $0.events.append(event) } },
                clockDrift: { status in self.state.withLock { $0.clockDrift.append(status) } },
                noAudio: { isNoAudio in self.state.withLock { $0.noAudio.append(isNoAudio) } },
                ended: { end in self.state.withLock { $0.end = end } })
        }

        /// Waits until `count` file ends were reported, for at most 5 s.
        func waitForFileEnds(_ count: Int) async throws {
            for _ in 0..<500 {
                if ended.count >= count { return }
                try await Task.sleep(for: .milliseconds(10))
            }
            Issue.record("\(ended.count) of \(count) file ends were reported")
            throw CancellationError()
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
    /// When the capture is told a buffer arrived, when a test sets it.
    final class Arrival: Sendable {
        let time = Mutex<Int64?>(nil)
    }

    private let arrival = Arrival()
    private let source = StandInSource()
    private let writer = StandInWriter()
    private let reported = Reported()
    private let samplesPerBuffer = 1600
    /// The samples the clock drift correction's resampler holds back until
    /// the next buffer or the capture's end.
    private let heldBack = RecorderValues.clockDriftResamplerTaps / 2

    private func capture(
        _ id: AudioTracker.SourceID = .input("Razer"), drainTimeout: Duration = .seconds(2),
        inputVolume: (@Sendable () -> Double?)? = nil
    ) -> AudioCapture {
        let context = RecordingContext(
            folder: FileManager.default.temporaryDirectory, started: Date(), timeZone: TimeZone(identifier: "Europe/Berlin")!,
            clock: SharedClock(reading: reading), app: "Multi Screen Recorder (tests)")
        let writer = writer
        let arrival = arrival
        let capture = AudioCapture(
            id: id, number: id == .systemAudio ? 0 : 2, name: id == .systemAudio ? "System audio" : "Razer Seiren V3 Mini", source: source, context: context,
            guides: GuideTrackFeed(tracks: [], now: { 0 }), reports: reported.reports, drainTimeout: drainTimeout,
            now: { arrival.time.withLock { $0 } ?? context.now() }, inputVolume: inputVolume,
            makeWriter: { _, _, firstTick in
                writer.firstTick.withLock { $0 = $0 ?? firstTick }
                return writer
            })
        capture.start()
        return capture
    }

    /// A buffer of `channels` channels whose first sample is `at` nanoseconds from t0.
    private func buffer(at nanoseconds: Int64, channels: Int = 1, count: Int? = nil, value: Float = 0.25) throws -> CMSampleBuffer {
        let samples = Array(repeating: [Float](repeating: value, count: count ?? samplesPerBuffer), count: channels)
        let time = CMTime(value: CMTimeValue(reading.host) + nanoseconds, timescale: 1_000_000_000)
        return try pcmSample(samples[...], format: pcmFormat(channels: channels), at: time)
    }

    /// The samples of one append to the writer: about 100 ms.
    private let appendSamples = RecorderValues.audioFileAppendSamples

    /// Buffers of a run without gaps until the writer took its first append:
    /// the corrected samples then reach `appendSamples`.
    private var buffersUntilTheFirstAppend: Int { (appendSamples + heldBack) / samplesPerBuffer + 1 }

    /// The nanoseconds of the `index`th buffer of a run without gaps.
    private func time(ofBuffer index: Int) -> Int64 {
        Int64(index * samplesPerBuffer) * 1_000_000_000 / Int64(RecorderValues.audioSampleRate)
    }

    /// The writer takes the waiting samples only after Stop tried twice, so
    /// the end waits for it; the bound is far away, as the bound itself is
    /// `samplesTheWriterNeverTookAreNotCountedAndToldAsLost`'s.
    @Test func samplesStillWaitingAtTheEndAreWrittenBeforeTheFileIsFinalized() async throws {
        let capture = capture(drainTimeout: .seconds(60))
        writer.isReady = false
        for index in 0..<3 { source.send(try buffer(at: time(ofBuffer: index))) }
        #expect(writer.samples == 0)
        writer.becomesReady(afterRefusals: 2)
        await capture.stop()
        #expect(writer.refusalsLeft == -1)
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
        let first = buffersUntilTheFirstAppend
        for index in 0..<first { source.send(try buffer(at: time(ofBuffer: index))) }
        writer.isReady = false
        source.send(try buffer(at: time(ofBuffer: first)))
        await capture.stop()
        let ends = reported.ended
        let end = try #require(ends.first)
        // The first append's samples, all but those held back for the next buffer, were written.
        let written = first * samplesPerBuffer - heldBack
        let lost = samplesPerBuffer + heldBack
        #expect(writer.endPosition == .some(Int64(written)))
        #expect(end.file.end == end.file.start + Double(written) / Double(RecorderValues.audioSampleRate))
        #expect(end.error?.description.contains("\(lost) samples") == true)
        #expect(end.error?.description.contains("lost") == true)
        #expect(end.lostSamples == Int64(lost))
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
        // The first file's samples, gathered for an append, are written as it ends; the writer stays ready until then.
        try await reported.waitForFileEnds(1)
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

    /// The capture ends at the buffer that pushes the waiting samples over
    /// the audio wait bound; the correction's held-back samples are dropped,
    /// not added to the waiting ones.
    @Test func aWriterThatTakesNothingForTheAudioWaitBoundFellBehind() async throws {
        let capture = capture(drainTimeout: .milliseconds(10))
        writer.isReady = false
        let bound = RecorderValues.audioWaitBoundSeconds * RecorderValues.audioSampleRate
        // The first buffer whose corrected samples go over the bound, and one more.
        let sent = (bound + heldBack) / samplesPerBuffer + 1
        for index in 0...sent { source.send(try buffer(at: time(ofBuffer: index))) }
        let end = try await reported.waitForCaptureEnd()
        let files = reported.ended
        withExtendedLifetime(capture) {}
        #expect(end == .writerFellBehind)
        #expect(files.first?.error?.description.contains("lost") == true)
        #expect(files.first?.lostSamples == Int64(sent * samplesPerBuffer - heldBack))
    }

    /// Every sample goes through the clock drift correction; the samples it
    /// holds back reach the file at Stop.
    @Test func theFileEndCarriesItsClockDriftCorrection() async throws {
        let capture = capture()
        let sent = buffersUntilTheFirstAppend
        for index in 0..<sent { source.send(try buffer(at: time(ofBuffer: index))) }
        #expect(writer.samples == Int64(sent * samplesPerBuffer - heldBack))
        await capture.stop()
        #expect(writer.samples == Int64(sent * samplesPerBuffer))
        let end = try #require(reported.ended.first)
        // Too short for a clock drift; the correction is known.
        #expect(end.file.clockDriftPpm == nil)
        #expect(end.file.clockDriftCorrection != nil)
        // The status is reported from the first buffer on.
        #expect(reported.clockDrift.first?.clockDriftPpm == nil)
    }

    @Test func aChannelCountChangeEndsTheFileWithAllItsSamples() async throws {
        let capture = capture()
        source.send(try buffer(at: 0))
        source.send(try buffer(at: time(ofBuffer: 1), channels: 2))
        #expect(reported.started.count == 2)
        await capture.stop()
        #expect(writer.samples == 2 * Int64(samplesPerBuffer))
        #expect(reported.ended.map(\.file.channels).sorted { "\($0)" < "\($1)" } == [.mono(1), .mono(2)])
    }

    // MARK: Clock drift

    /// A device 500 ppm slow, its buffers arriving 5 ms after their
    /// timestamps plus what its clock lost: each buffer is sent with that
    /// arrival, and the same buffers go through `expected`, a correction
    /// of the test's own.
    private func sendDrifting(
        _ count: Int, from first: Int, after gap: Int64 = 0, to expected: inout ClockDriftCorrection
    ) throws {
        for index in first..<(first + count) {
            try sendDrifting(at: time(ofBuffer: index) + gap, count: samplesPerBuffer, to: &expected)
        }
    }

    /// The gap `expected` found before the buffer, if any.
    @discardableResult
    private func sendDrifting(at nanoseconds: Int64, count: Int, to expected: inout ClockDriftCorrection) throws -> ClockDriftCorrection.Gap? {
        let time = SharedClock(reading: reading).sinceStart(host: reading.host + UInt64(nanoseconds))
        let arrived = time + 5_000_000 + time / 2000
        let gap = expected.correct([[Float](repeating: 0.25, count: count)], at: time, arrival: arrived).gap
        arrival.time.withLock { $0 = arrived }
        source.send(try buffer(at: nanoseconds, count: count))
        return gap
    }

    /// The status goes to the recorder at the first buffer and then about
    /// once a second of arrivals (`ClockDriftScheduleTests` has the
    /// `--debug` block's cadence).
    @Test func theClockDriftStatusIsReportedAboutOnceASecond() async throws {
        let capture = capture()
        var expected = ClockDriftCorrection()
        // 25 s of buffers of 1600 samples.
        try sendDrifting(750, from: 0, to: &expected)
        let reports = reported.clockDrift
        #expect((25...26).contains(reports.count), "\(reports.count) reports")
        #expect(reports.last?.clockDriftPpm != nil)
        await capture.stop()
    }

    /// A file's clock drift is the one shown at its end, its correction
    /// what was added during it: the second file's counts from its own
    /// start, and leaves out nothing of the first's. The drift added at
    /// the gap that ended the first file is no file's.
    @Test func eachFileCarriesTheCorrectionAddedDuringIt() async throws {
        let capture = capture()
        var expected = ClockDriftCorrection()
        try sendDrifting(600, from: 0, to: &expected)
        // A gap of 2 s ends the file; the correction's tail goes to it. The
        // first buffer after it, of 1 s, adds about 0.3 ms, none of it the first file's.
        let atGap = expected.applied
        let gap = try #require(try sendDrifting(at: time(ofBuffer: 600) + 2_000_000_000, count: 30 * samplesPerBuffer, to: &expected))
        // 500 ppm over the 2 s gap: about 1 ms.
        #expect(abs(gap.drift - 0.001) < 0.0001, "\(gap.drift * 1000) ms")
        #expect(expected.applied - atGap - gap.drift > 0.0002, "\((expected.applied - atGap - gap.drift) * 1000) ms")
        try sendDrifting(570, from: 630, after: 2_000_000_000, to: &expected)
        await capture.stop()
        _ = expected.flush()
        let ends = reported.ended.sorted { $0.file.start < $1.file.start }
        try #require(ends.count == 2)
        let first = try #require(ends[0].file.clockDriftCorrection)
        let second = try #require(ends[1].file.clockDriftCorrection)
        let rounded = { (seconds: Double) in (seconds * 10_000).rounded() / 10_000 }
        #expect(atGap > 0.003, "\(atGap * 1000) ms at the gap")
        #expect(first == rounded(atGap))
        #expect(second == rounded(expected.applied - atGap - gap.drift))
        #expect(ends[1].file.clockDriftPpm == (expected.status.clockDriftPpm.map { ($0 * 10).rounded() / 10 }))
        #expect(ends[1].file.clockDriftPpm != nil)
    }

    /// A gap filled with silence stays in its file, and so does the drift
    /// added at it, as longer silence.
    @Test func aFilledGapsDriftIsInItsFile() async throws {
        let capture = capture()
        var expected = ClockDriftCorrection()
        try sendDrifting(600, from: 0, to: &expected)
        let gap = try #require(try sendDrifting(at: time(ofBuffer: 600) + 500_000_000, count: samplesPerBuffer, to: &expected))
        #expect(abs(gap.drift - 0.00025) < 0.00005, "\(gap.drift * 1000) ms")
        try sendDrifting(299, from: 601, after: 500_000_000, to: &expected)
        await capture.stop()
        _ = expected.flush()
        let ends = reported.ended
        try #require(ends.count == 1)
        #expect(ends[0].file.clockDriftCorrection == (expected.applied * 10_000).rounded() / 10_000)
    }

    /// A capture that ends by itself writes the correction's held-back samples.
    @Test func aCaptureThatEndsByItselfWritesTheCorrectionsTail() async throws {
        let capture = capture()
        let sent = buffersUntilTheFirstAppend
        for index in 0..<sent { source.send(try buffer(at: time(ofBuffer: index))) }
        #expect(writer.samples == Int64(sent * samplesPerBuffer - heldBack))
        source.lose(.disconnected)
        _ = try await reported.waitForCaptureEnd()
        withExtendedLifetime(capture) {}
        #expect(writer.samples == Int64(sent * samplesPerBuffer))
    }

    /// A writer that failed ends the capture without the tail, and a Stop
    /// racing after that neither writes it nor opens a file.
    /// The buffers start 0.5 ms after a tick, so the tail would cross the
    /// next tick and open a file.
    @Test func aFailedWriterEndsTheCaptureWithoutItsTail() async throws {
        let capture = capture()
        // The first buffer ends before the first tick, so one more buffer is needed for the first append.
        writer.fails(atAppend: 1)
        for index in 0...buffersUntilTheFirstAppend { source.send(try buffer(at: 500_000 + time(ofBuffer: index))) }
        let end = try await reported.waitForCaptureEnd()
        let samples = writer.samples
        guard case .writerFailed(let error) = end else {
            Issue.record("the capture ended with \(end)")
            return
        }
        #expect(error.text.contains("writing a stand-in file"))
        await capture.stop()
        #expect(writer.appends == 1)
        #expect(writer.samples == samples)
        #expect(reported.started.count == 1)
        #expect(reported.ended.count == 1)
    }

    /// The file a failed writer ends is told by the capture's failure event,
    /// not by a problem of its own on standard error (D65); a stop's is not.
    @Test func aFileEndedByAFailedCaptureIsToldByItsEvent() async throws {
        let failing = capture()
        writer.fails(atAppend: 1)
        for index in 0...buffersUntilTheFirstAppend { source.send(try buffer(at: 500_000 + time(ofBuffer: index))) }
        _ = try await reported.waitForCaptureEnd()
        await failing.stop()
        #expect(reported.ended.first?.endedByFailedCapture == true)
        #expect(reported.ended.first?.toldByAnEvent == true)
    }

    @Test func aFileEndedByAStopIsNotToldByAnEvent() async throws {
        let capture = capture()
        source.send(try buffer(at: 0))
        await capture.stop()
        #expect(reported.ended.first?.endedByFailedCapture == false)
        #expect(reported.ended.first?.toldByAnEvent == false)
    }

    @Test func lostSamplesAreToldByTheirEvent() {
        let file = RecordingManifest.AudioFile(
            name: "a.mov", audioSource: "Mic", audioSourceUID: "u", channels: .mono(1), start: 0, timecode: "t")
        #expect(AudioFileEnd(file: file, error: nil, lostSamples: 5).toldByAnEvent)
        #expect(!AudioFileEnd(file: file, error: AudioFileWriterError(nil, while: "x"), lostSamples: 0).toldByAnEvent)
    }

    /// The tail at a gap pushes the waiting samples over the audio wait
    /// bound: the capture ends, and nothing after the gap starts a file.
    @Test func aTailThatEndsTheCaptureWritesNothingAfterIt() async throws {
        let capture = capture(drainTimeout: .milliseconds(10))
        writer.isReady = false
        let bound = RecorderValues.audioWaitBoundSeconds * RecorderValues.audioSampleRate
        // Input of the bound plus half the held-back samples: waiting stays
        // within the bound until the tail comes.
        let input = bound + heldBack / 2
        let full = input / samplesPerBuffer
        for index in 0..<full { source.send(try buffer(at: time(ofBuffer: index))) }
        source.send(try buffer(at: time(ofBuffer: full), count: input - full * samplesPerBuffer))
        #expect(reported.captureEnd == nil)
        source.send(try buffer(at: time(ofBuffer: full + 1) + 2_000_000_000))
        let end = try await reported.waitForCaptureEnd()
        withExtendedLifetime(capture) {}
        #expect(end == .writerFellBehind)
        #expect(reported.started.count == 1)
        #expect(reported.ended.count == 1)
    }

    // MARK: Appends of about 100 ms

    /// A microphone's buffers of 512 samples reach the writer in appends of
    /// about 100 ms, not one append per buffer: the appends, not the encoder,
    /// cost the most (backlog item 6). Stop writes the rest.
    @Test func theWriterTakesTheAudioInAppendsOfAbout100Milliseconds() async throws {
        let capture = capture()
        let perBuffer = 512
        let buffers = 200
        for index in 0..<buffers {
            let nanoseconds = Int64(index * perBuffer) * 1_000_000_000 / Int64(RecorderValues.audioSampleRate)
            source.send(try buffer(at: nanoseconds, count: perBuffer))
        }
        let taken = writer.taken
        // Less than one append's samples still wait.
        #expect((0..<appendSamples).contains(buffers * perBuffer - heldBack - taken.reduce(0, +)))
        #expect(taken.count >= 15)
        #expect(taken.allSatisfy { (appendSamples..<appendSamples + perBuffer).contains($0) }, "\(taken)")
        await capture.stop()
        #expect(writer.samples == Int64(buffers * perBuffer))
        #expect(writer.taken.dropLast().allSatisfy { $0 >= appendSamples })
        #expect(RecorderValues.audioFileAppendSamples == RecorderValues.audioSampleRate / 10)
    }

    // MARK: Level meter, input volume and no audio (D69)

    /// Sends the buffers of a run without gaps, each `value` throughout, arriving 1 ms after their time.
    private func send(_ value: Float, buffers: Range<Int>, channels: Int = 1) throws {
        for index in buffers {
            arrival.time.withLock { $0 = time(ofBuffer: index) + 1_000_000 }
            source.send(try buffer(at: time(ofBuffer: index), channels: channels, value: value))
        }
    }

    /// Buffers of exact zeros for the no audio time.
    private var buffersOfNoAudio: Int {
        Int(RecorderValues.noAudioTime.nanoseconds * Int64(RecorderValues.audioSampleRate) / 1_000_000_000) / samplesPerBuffer
    }

    private func kinds(_ events: [RecordingEvent]) -> [RecordingEvent.Kind] { events.map(\.event) }

    @Test func eachIncomingBufferGoesToTheLevelMeter() throws {
        let capture = capture()
        source.send(try buffer(at: 0, value: -0.5))
        source.send(try buffer(at: time(ofBuffer: 1), value: 0.25))
        let level = capture.readLevel(at: time(ofBuffer: 2))
        #expect(level.peak == 0.5)
        #expect(level.hold == 0.5)
        #expect(capture.readLevel(at: time(ofBuffer: 3)).peak == 0)
    }

    @Test func anAudioInputsFileHasItsInputVolumeAtItsStart() async throws {
        let capture = capture(inputVolume: { 0.4567 })
        try send(0.25, buffers: 0..<10)
        await capture.stop()
        #expect(reported.ended.map(\.file.inputVolume) == [0.457])
    }

    @Test func anInputWithNoAudioFromTheStartGetsNoFile() async throws {
        let capture = capture()
        try send(0, buffers: 0..<(buffersOfNoAudio + 30))
        #expect(reported.started.isEmpty)
        #expect(kinds(reported.events) == [.noAudioStarted])
        #expect(reported.events.first?.audioSource == "Razer Seiren V3 Mini")
        #expect(abs(reported.events[0].at - 10) < 0.01, "\(reported.events[0].at)")
        #expect(reported.noAudio == [true])
        await capture.stop()
        #expect(reported.ended.isEmpty)
        #expect(writer.appends == 0)
    }

    /// The new file starts at a tick before the sound, so nothing of it is cut.
    @Test func soundAfterNoAudioStartsAFileWithNothingCut() async throws {
        let capture = capture()
        let quiet = buffersOfNoAudio + 30
        try send(0, buffers: 0..<quiet)
        try send(0.25, buffers: quiet..<(quiet + 20))
        await capture.stop()
        #expect(kinds(reported.events) == [.noAudioStarted, .noAudioStopped])
        #expect(reported.noAudio == [true, false])
        #expect(reported.started.count == 1)
        let soundStarts = Double(time(ofBuffer: quiet)) / 1_000_000_000
        let file = try #require(reported.ended.first?.file)
        #expect(file.start <= soundStarts)
        #expect(soundStarts - file.start < 0.07)
        #expect(try #require(writer.firstSound) > 0)
        #expect(abs(reported.events[1].at - soundStarts) < 0.002, "\(reported.events[1].at)")
    }

    @Test func zerosShorterThanTheNoAudioTimeStayInTheFile() async throws {
        let capture = capture()
        try send(0.25, buffers: 0..<10)
        try send(0, buffers: 10..<(10 + buffersOfNoAudio - 10))
        try send(0.25, buffers: (buffersOfNoAudio)..<(buffersOfNoAudio + 10))
        await capture.stop()
        #expect(reported.events.isEmpty)
        #expect(reported.started.count == 1)
        #expect(reported.ended.count == 1)
    }

    @Test func noAudioEndsTheFileAndTheSoundStartsTheNext() async throws {
        let capture = capture()
        try send(0.25, buffers: 0..<10)
        try send(0, buffers: 10..<(10 + buffersOfNoAudio + 10))
        try await reported.waitForFileEnds(1)
        let first = try #require(reported.ended.first?.file)
        #expect(first.state == .finalized)
        let noAudioStarts = Double(time(ofBuffer: 10)) / 1_000_000_000 + 10
        #expect(abs(try #require(first.end) - noAudioStarts) < 0.07, "\(String(describing: first.end))")
        let restart = 10 + buffersOfNoAudio + 10
        try send(0.25, buffers: restart..<(restart + 10))
        await capture.stop()
        #expect(kinds(reported.events) == [.noAudioStarted, .noAudioStopped])
        #expect(reported.started.count == 2)
        #expect(reported.ended.count == 2)
    }

    /// Buffers of a gap too long to fill.
    private var buffersOfALongGap: Int {
        Int(RecorderValues.longestFilledAudioGap.nanoseconds * Int64(RecorderValues.audioSampleRate) / 1_000_000_000) / samplesPerBuffer + 20
    }

    @Test func aFileEndedByAGapStartsAgainOnlyWithSoundAfterTheZeros() async throws {
        let capture = capture()
        try send(0.25, buffers: 0..<10)
        let afterGap = 10 + buffersOfALongGap
        try send(0, buffers: afterGap..<(afterGap + 5))
        let restart = afterGap + 5
        try send(0.25, buffers: restart..<(restart + 10))
        await capture.stop()
        #expect(reported.started.count == 2)
        #expect(reported.ended.count == 2)
        #expect(!kinds(reported.events).contains(.noAudioStarted))
        let second = try #require(reported.ended.map(\.file).max { $0.start < $1.start })
        let soundStarts = Double(time(ofBuffer: restart)) / 1_000_000_000
        // At most the leading zeros before the sound, none of the zeros before the gap.
        #expect(second.start <= soundStarts)
        #expect(soundStarts - second.start < 0.07, "\(second.start) \(soundStarts)")
        #expect(second.start >= Double(time(ofBuffer: afterGap)) / 1_000_000_000)
    }

    @Test func zerosAfterAGapThatEndedTheFileStartNone() async throws {
        let capture = capture()
        try send(0.25, buffers: 0..<10)
        let afterGap = 10 + buffersOfALongGap
        try send(0, buffers: afterGap..<(afterGap + 5))
        await capture.stop()
        #expect(reported.started.count == 1)
        #expect(reported.ended.count == 1)
    }

    @Test func aFileEndedByAChannelCountChangeStartsAgainOnlyWithSoundAfterTheZeros() async throws {
        let capture = capture()
        try send(0.25, buffers: 0..<10)
        try send(0, buffers: 10..<15, channels: 2)
        try send(0.25, buffers: 15..<25, channels: 2)
        await capture.stop()
        #expect(reported.started.count == 2)
        let second = try #require(reported.ended.map(\.file).first { $0.channels == .mono(2) })
        let soundStarts = Double(time(ofBuffer: 15)) / 1_000_000_000
        #expect(second.start <= soundStarts)
        #expect(soundStarts - second.start < 0.07, "\(second.start) \(soundStarts)")
        #expect(second.start >= Double(time(ofBuffer: 10)) / 1_000_000_000)
    }

    @Test func theSystemAudioIsExcluded() async throws {
        let capture = capture(.systemAudio)
        try send(0, buffers: 0..<(buffersOfNoAudio + 30), channels: 2)
        await capture.stop()
        #expect(reported.events.isEmpty)
        #expect(reported.started.count == 1)
        #expect(reported.ended.first?.file.inputVolume == nil)
    }
}
