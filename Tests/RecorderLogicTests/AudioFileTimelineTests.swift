import Testing
@testable import RecorderLogic

@Suite struct AudioFileTimelineTests {
    /// 512 samples at 48 kHz, as an `AVCaptureSession` delivers them.
    private let bufferSamples = 512
    private let millisecond: Int64 = 1_000_000

    /// The timestamp of the sample `index` samples after `origin`, as a
    /// source whose timestamps follow its sample count gives it.
    private func time(_ origin: Int64, after index: Int64) -> Int64 {
        origin + index * 1_000_000_000 / Int64(RecorderValues.audioSampleRate)
    }

    @Test func theRecordingValuesAreTheDesignsStartingPoints() {
        #expect(RecorderValues.audioSampleRate == 48_000)
        #expect(RecorderValues.audioGapTolerance == .milliseconds(32))
        #expect(RecorderValues.longestFilledAudioGap == .seconds(1))
        #expect(RecorderValues.guideTrackDelay == .milliseconds(200))
    }

    @Test func theFileStartsAtTheFirstTickAfterItsFirstBufferAndTrimsTheSamplesBefore() {
        var timeline = AudioFileTimeline()
        let origin = 10 * millisecond
        let samplesPerTick = Int64(RecorderValues.audioSampleRate / RecorderValues.framesPerSecond)
        let tickTime = TickGrid.recording.time(ofTick: 1)
        let trimmed = ((tickTime - origin) * Int64(RecorderValues.audioSampleRate) + 500_000_000) / 1_000_000_000
        #expect(trimmed > 2 * Int64(bufferSamples) && trimmed < 3 * Int64(bufferSamples))
        var placements: [AudioBufferPlacement.Action] = []
        for index in 0..<4 {
            let start = Int64(index * bufferSamples)
            placements.append(timeline.place(bufferAt: time(origin, after: start), sampleCount: bufferSamples, arrival: 0).action)
        }
        #expect(timeline.firstTick == 1)
        #expect(placements == [
            .trim, .trim,
            .write(silence: 0, firstSample: Int(trimmed) - 2 * bufferSamples, position: 0),
            .write(silence: 0, firstSample: 0, position: 3 * Int64(bufferSamples) - trimmed),
        ])
        // The next buffer follows the samples placed so far.
        #expect(timeline.place(bufferAt: time(origin, after: 4 * Int64(bufferSamples)), sampleCount: bufferSamples, arrival: 0).action
            == .write(silence: 0, firstSample: 0, position: 4 * Int64(bufferSamples) - trimmed))
        #expect(samplesPerTick == 1600)
    }

    @Test func aFirstBufferOnATickTrimsNothing() {
        var timeline = AudioFileTimeline()
        let tickTime = TickGrid.recording.time(ofTick: 30)
        let placement = timeline.place(bufferAt: tickTime, sampleCount: bufferSamples, arrival: 0)
        #expect(timeline.firstTick == 30)
        #expect(placement == AudioBufferPlacement(action: .write(silence: 0, firstSample: 0, position: 0), gap: nil))
    }

    @Test func timestampsThatJitterWithinTheToleranceAreNoGap() {
        var timeline = AudioFileTimeline()
        _ = timeline.place(bufferAt: 0, sampleCount: bufferSamples, arrival: 0)
        let jittered = timeline.place(bufferAt: time(0, after: Int64(bufferSamples)) + 32 * millisecond, sampleCount: bufferSamples, arrival: 0)
        #expect(jittered == AudioBufferPlacement(action: .write(silence: 0, firstSample: 0, position: Int64(bufferSamples)), gap: nil))
        let early = timeline.place(bufferAt: time(0, after: 2 * Int64(bufferSamples)) - 5 * millisecond, sampleCount: bufferSamples, arrival: 0)
        #expect(early == AudioBufferPlacement(action: .write(silence: 0, firstSample: 0, position: 2 * Int64(bufferSamples)), gap: nil))
        #expect(timeline.place(bufferAt: time(0, after: 3 * Int64(bufferSamples)), sampleCount: bufferSamples, arrival: 0).action
            == .write(silence: 0, firstSample: 0, position: 3 * Int64(bufferSamples)))
    }

    @Test func aGapUpToOneSecondIsFilledWithSilenceOfExactlyItsLength() {
        var timeline = AudioFileTimeline()
        _ = timeline.place(bufferAt: 0, sampleCount: bufferSamples, arrival: 0)
        let afterGap = timeline.place(bufferAt: time(0, after: Int64(bufferSamples)) + 100 * millisecond, sampleCount: bufferSamples, arrival: 0)
        #expect(afterGap.gap == AudioGap(length: 100 * millisecond, samples: 4800, isFilled: true))
        #expect(afterGap.action == .write(silence: 4800, firstSample: 0, position: Int64(bufferSamples) + 4800))
        // The sample count now includes the silence: the next buffer is no gap.
        let next = timeline.place(bufferAt: time(0, after: 2 * Int64(bufferSamples) + 4800), sampleCount: bufferSamples, arrival: 0)
        #expect(next == AudioBufferPlacement(action: .write(silence: 0, firstSample: 0, position: 2 * Int64(bufferSamples) + 4800), gap: nil))

        let oneSecond = timeline.place(bufferAt: time(0, after: 3 * Int64(bufferSamples) + 4800) + 1000 * millisecond, sampleCount: bufferSamples, arrival: 0)
        #expect(oneSecond.gap == AudioGap(length: 1000 * millisecond, samples: 48_000, isFilled: true))
    }

    @Test func aGapLongerThanOneSecondEndsTheFile() {
        var timeline = AudioFileTimeline()
        _ = timeline.place(bufferAt: 0, sampleCount: bufferSamples, arrival: 0)
        let afterGap = timeline.place(bufferAt: time(0, after: Int64(bufferSamples)) + 1001 * millisecond, sampleCount: bufferSamples, arrival: 0)
        #expect(afterGap == AudioBufferPlacement(action: .endFile, gap: AudioGap(length: 1001 * millisecond, samples: 48_048, isFilled: false)))
        // The buffer after the long gap is not counted: one in its place is still no gap.
        #expect(timeline.place(bufferAt: time(0, after: Int64(bufferSamples)), sampleCount: bufferSamples, arrival: 0)
            == AudioBufferPlacement(action: .write(silence: 0, firstSample: 0, position: Int64(bufferSamples)), gap: nil))
    }

    @Test func aGapBeforeTheFirstTickIsTrimmedWithItsBuffer() {
        var timeline = AudioFileTimeline()
        let origin = 1 * millisecond
        _ = timeline.place(bufferAt: origin, sampleCount: 48, arrival: 0)
        // 40 ms later than its sample count, past the first tick at 33.3 ms.
        let placement = timeline.place(bufferAt: time(origin, after: 48) + 40 * millisecond, sampleCount: bufferSamples, arrival: 0)
        let trimmed: Int64 = 1552 // (33.333 ms - 1 ms) at 48 kHz
        #expect(placement.gap?.samples == 1920)
        #expect(placement.action == .write(silence: 48 + 1920 - trimmed, firstSample: 0, position: 48 + 1920 - trimmed))
    }

    @Test func theClockDriftIsTheSamplesWrittenAgainstTheSharedClocksElapsedTime() throws {
        var measure = ClockDriftMeasure()
        measure.record(arrival: 5 * millisecond, samplesBefore: 0)
        #expect(measure.clockDriftPpm == nil)
        // 10.001 s of samples while the shared clock counted 10 s: 100 ppm fast.
        measure.record(arrival: 10_005 * millisecond, samplesBefore: 480_048)
        #expect(abs(try #require(measure.clockDriftPpm) - 100) < 0.001)
        measure.record(arrival: 20_005 * millisecond, samplesBefore: 959_904)
        #expect(abs(try #require(measure.clockDriftPpm) - -100) < 0.001)
    }

    @Test func anAudioFileMeasuresItsDriftFromTheArrivalOfItsBuffers() throws {
        var timeline = AudioFileTimeline()
        #expect(timeline.clockDriftPpm == nil)
        // A source 117 ppm slow: each buffer of 512 samples arrives 512 / 48000 s × (1 + 117e-6) apart.
        let interval = Double(bufferSamples) / 48_000 * 1_000_000_000 * (1 + 117e-6)
        for index in 0..<1000 {
            let start = Int64(index * bufferSamples)
            _ = timeline.place(bufferAt: time(0, after: start), sampleCount: bufferSamples, arrival: Int64((Double(index) * interval).rounded()))
        }
        let drift = try #require(timeline.clockDriftPpm)
        #expect(abs(drift - -117) < 0.5, "\(drift)")
    }
}
