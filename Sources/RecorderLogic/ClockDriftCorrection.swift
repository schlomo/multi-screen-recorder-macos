/// One audio source's clock drift correction: its sound resampled so its
/// sample count follows the shared clock instead of the device's clock
/// (`ClockDriftTracker`, `ClockDriftResampler`). The buffers form segments:
/// a segment starts with the first buffer, after a gap (a buffer whose
/// timestamp runs more than `gapTolerance` ahead of the position its
/// segment's sample count gives) and on a change of the channel count; the
/// resampler is flushed at a segment's end. A device's clock keeps
/// drifting while no buffers come, so at a gap the correction grows by the
/// tracker's drift over the gap, as a jump, not resampled. Within a segment
/// the corrected audio is contiguous: the first starts at the segment's
/// first timestamp plus the correction applied by then, each further one
/// where the one before ended; so a gap reaches the audio file and the
/// guide track as a jump of its length plus that drift. That rests on an
/// assumption: a source's timestamps keep following its sample count
/// across a gap. Times are nanoseconds on the shared clock.
public struct ClockDriftCorrection: Sendable {
    /// Corrected samples, one array per channel, the first at `time`; the
    /// correction applied up to its start (after a gap including the
    /// drift during it) and up to its end, in seconds.
    public struct CorrectedAudio: Equatable, Sendable {
        public var time: Int64
        public var channels: [[Float]]
        public var appliedAtStart: Double
        public var applied: Double
    }

    /// A gap that started a new segment: its length, the correction
    /// applied when it came, the drift during it added to the correction,
    /// and the lateness of the buffers before and after it, in seconds.
    public struct Gap: Equatable, Sendable {
        public var length: Int64
        public var applied: Double
        public var drift: Double
        public var latenessBefore: Double
        public var latenessAfter: Double
    }

    /// What the status window and `--debug` show of the correction.
    public struct Status: Equatable, Sendable {
        /// The device's clock drift, positive when its clock runs fast; nil until measured.
        public var clockDriftPpm: Double?
        /// The sound added so far, in seconds (negative: removed).
        public var applied: Double
        /// What was still off at the latest estimate, the target and the
        /// correction taken at the same moment, in seconds; nil before the first.
        public var remaining: Double?

        public init(clockDriftPpm: Double?, applied: Double, remaining: Double?) {
            self.clockDriftPpm = clockDriftPpm
            self.applied = applied
            self.remaining = remaining
        }
    }

    public let sampleRate: Int
    public let gapTolerance: Int64
    private var tracker: ClockDriftTracker
    private var segment: Segment?
    /// The correction applied in the segments that ended.
    private var appliedBefore: Double = 0
    /// The latest buffer's lateness, in seconds.
    private var lateness: Double?

    private struct Segment {
        var resampler: ClockDriftResampler
        /// The first buffer's timestamp, and the corrected time of the first output sample.
        let start: Int64
        let correctedStart: Int64
        /// The correction applied in the segments before this one.
        let appliedBefore: Double
        var inputSamples: Int64 = 0
    }

    public init(
        sampleRate: Int = RecorderValues.audioSampleRate, gapTolerance: Duration = RecorderValues.audioGapTolerance,
        tracker: ClockDriftTracker = ClockDriftTracker()
    ) {
        precondition(sampleRate > 0, "the clock drift correction needs a positive sample rate")
        self.sampleRate = sampleRate
        self.gapTolerance = gapTolerance.nanoseconds
        self.tracker = tracker
    }

    /// The correction applied so far, in seconds.
    public var applied: Double { segment.map { $0.appliedBefore + $0.resampler.applied } ?? appliedBefore }

    public var status: Status {
        Status(clockDriftPpm: tracker.clockDriftPpm, applied: applied, remaining: tracker.remaining)
    }

    /// A buffer whose first sample has the timestamp `time`, which arrived
    /// at `arrival`: the corrected audio it gives, the tail of a segment
    /// that ended before it first, and the gap before it, if any.
    public mutating func correct(_ channels: [[Float]], at time: Int64, arrival: Int64) -> (audio: [CorrectedAudio], gap: Gap?) {
        let count = channels.first?.count ?? 0
        let latenessNow = Double(arrival - time) / 1e9
        var audio: [CorrectedAudio] = []
        var gap: Gap?
        if let segment {
            let ahead = time - (segment.start + Self.nanoseconds(in: segment.inputSamples, sampleRate: sampleRate))
            if ahead > gapTolerance {
                audio += flush()
                let drift = tracker.driftAcrossGap(of: ahead, arrival: arrival, applied: applied)
                gap = Gap(length: ahead, applied: applied, drift: drift, latenessBefore: lateness ?? latenessNow, latenessAfter: latenessNow)
                appliedBefore += drift
            } else if segment.resampler.channelCount != channels.count {
                audio += flush()
            }
        }
        lateness = latenessNow
        if segment == nil {
            let appliedNow = applied
            segment = Segment(
                resampler: ClockDriftResampler(channelCount: channels.count, sampleRate: sampleRate),
                start: time, correctedStart: time + Int64((appliedNow * 1e9).rounded()), appliedBefore: appliedNow)
        }
        let appliedBeforeBuffer = applied
        let outputBefore = segment!.resampler.outputCount
        let corrected = segment!.resampler.process(channels, rate: tracker.rate)
        segment!.inputSamples += Int64(count)
        audio += Self.corrected(corrected, of: segment!, outputBefore: outputBefore, appliedAtStart: appliedBeforeBuffer, applied: applied)
        tracker.record(time: time, arrival: arrival, applied: appliedBeforeBuffer)
        return (audio, gap)
    }

    /// Ends the current segment, if any: the resampler's tail as the last corrected audio.
    public mutating func flush() -> [CorrectedAudio] {
        guard var segment else { return [] }
        let outputBefore = segment.resampler.outputCount
        let appliedAtStart = segment.appliedBefore + segment.resampler.applied
        let tail = segment.resampler.flush(rate: tracker.rate)
        appliedBefore = segment.appliedBefore + segment.resampler.applied
        self.segment = nil
        return Self.corrected(tail, of: segment, outputBefore: outputBefore, appliedAtStart: appliedAtStart, applied: appliedBefore)
    }

    private static func corrected(
        _ channels: [[Float]], of segment: Segment, outputBefore: Int64, appliedAtStart: Double, applied: Double
    ) -> [CorrectedAudio] {
        guard let first = channels.first, !first.isEmpty else { return [] }
        let time = segment.correctedStart + nanoseconds(in: outputBefore, sampleRate: segment.resampler.sampleRate)
        return [CorrectedAudio(time: time, channels: channels, appliedAtStart: appliedAtStart, applied: applied)]
    }

    /// A sample count as nanoseconds, rounded down, without overflowing on long files.
    private static func nanoseconds(in samples: Int64, sampleRate: Int) -> Int64 {
        let rate = Int64(sampleRate)
        return samples / rate * 1_000_000_000 + samples % rate * 1_000_000_000 / rate
    }
}
