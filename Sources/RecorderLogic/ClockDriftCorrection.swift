/// One audio source's clock drift correction: its sound resampled so its
/// sample count follows the shared clock instead of the device's clock
/// (`ClockDriftTracker`, `ClockDriftResampler`). The buffers form segments:
/// a segment starts with the first buffer, after a gap (a buffer whose
/// timestamp runs more than `gapTolerance` ahead of the position its
/// segment's sample count gives) and on a change of the channel count; the
/// resampler is flushed at a segment's end. Within a segment the corrected
/// chunks are contiguous: the first starts at the segment's first timestamp
/// plus the correction applied by then, each further one where the one
/// before ended; so a gap reaches the audio file and the guide track as a
/// jump of its length, as without the correction. Times are nanoseconds on
/// the shared clock.
public struct ClockDriftCorrection: Sendable {
    /// Corrected samples, one array per channel, the first at `time`;
    /// `applied`: the correction applied up to its end, in seconds.
    public struct Chunk: Equatable, Sendable {
        public var time: Int64
        public var channels: [[Float]]
        public var applied: Double
    }

    /// What the status window and `--debug` show of the correction.
    public struct Status: Equatable, Sendable {
        /// The device's clock drift, positive when its clock runs fast; nil until measured.
        public var clockDriftPpm: Double?
        /// The sound added so far, in seconds (negative: removed).
        public var applied: Double
        /// What is still off, in seconds; nil before the first measurement.
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
        Status(clockDriftPpm: tracker.clockDriftPpm, applied: applied, remaining: tracker.target.map { $0 - applied })
    }

    /// A buffer whose first sample has the timestamp `time`, which arrived
    /// at `arrival`: the corrected chunks it gives, the tail of a segment
    /// that ended before it first.
    public mutating func correct(_ channels: [[Float]], at time: Int64, arrival: Int64) -> [Chunk] {
        let count = channels.first?.count ?? 0
        var chunks: [Chunk] = []
        if let segment {
            let ahead = time - (segment.start + Self.nanoseconds(in: segment.inputSamples, sampleRate: sampleRate))
            if segment.resampler.channelCount != channels.count || ahead > gapTolerance { chunks += flush() }
        }
        if segment == nil {
            let applied = applied
            segment = Segment(
                resampler: ClockDriftResampler(channelCount: channels.count, sampleRate: sampleRate),
                start: time, correctedStart: time + Int64((applied * 1e9).rounded()), appliedBefore: applied)
        }
        let appliedBefore = applied
        let outputBefore = segment!.resampler.outputCount
        let corrected = segment!.resampler.process(channels, rate: tracker.rate)
        segment!.inputSamples += Int64(count)
        chunks += Self.chunk(corrected, of: segment!, outputBefore: outputBefore, applied: applied)
        tracker.record(time: time, arrival: arrival, applied: appliedBefore)
        return chunks
    }

    /// Ends the current segment, if any: the resampler's tail as the last chunk.
    public mutating func flush() -> [Chunk] {
        guard var segment else { return [] }
        let outputBefore = segment.resampler.outputCount
        let tail = segment.resampler.flush(rate: tracker.rate)
        appliedBefore = segment.appliedBefore + segment.resampler.applied
        self.segment = nil
        return Self.chunk(tail, of: segment, outputBefore: outputBefore, applied: appliedBefore)
    }

    private static func chunk(_ channels: [[Float]], of segment: Segment, outputBefore: Int64, applied: Double) -> [Chunk] {
        guard let first = channels.first, !first.isEmpty else { return [] }
        let time = segment.correctedStart + nanoseconds(in: outputBefore, sampleRate: segment.resampler.sampleRate)
        return [Chunk(time: time, channels: channels, applied: applied)]
    }

    /// A sample count as nanoseconds, rounded down, without overflowing on long files.
    private static func nanoseconds(in samples: Int64, sampleRate: Int) -> Int64 {
        let rate = Int64(sampleRate)
        return samples / rate * 1_000_000_000 + samples % rate * 1_000_000_000 / rate
    }
}
