/// The audio half's values (*data*, D45, D46): starting points, calibrated
/// at the v1 gate, beside `RecorderValues`; the bit rates
/// are in `Encoding`.
extension RecorderValues {
    /// Every audio file's sample rate; every audio input measured ran at it.
    public static let audioSampleRate = 48_000
    /// How far a buffer's timestamp may run ahead of the position its sample
    /// count gives before it is a gap: above one buffer of 512 samples
    /// (about 10.7 ms), so ordinary jitter is no gap.
    public static let audioGapTolerance = Duration.milliseconds(32)
    /// The longest gap filled with silence; a longer one ends the audio
    /// file and a new one starts (D46).
    public static let longestFilledAudioGap = Duration.seconds(1)
    /// How far behind real time the guide track "Audio inputs" is mixed, so
    /// every source's buffers have arrived.
    public static let guideTrackDelay = Duration.milliseconds(200)
    /// How often the guide tracks are mixed and handed to the screen files.
    public static let guideTrackInterval = Duration.milliseconds(100)
    /// How often the CPU use of our process is sampled.
    public static let cpuSampleInterval = Duration.seconds(1)
}

/// The clock drift correction's values (*data*): the intervals the
/// buffers' lateness is measured in, the support line through them, the
/// rate that follows it, and the clock drift shown.
extension RecorderValues {
    /// Buffers are grouped by arrival in intervals of this length; each
    /// interval with a buffer gives a point, its smallest lateness.
    public static let clockDriftInterval = Duration.seconds(1)
    /// Points older than this are dropped: the support line is laid under
    /// the points of the last 20 s.
    public static let clockDriftHorizon = Duration.seconds(20)
    /// An estimate needs at least this many points, spanning at least this long.
    public static let clockDriftEstimateMinimumPoints = 5
    public static let clockDriftEstimateMinimumSpan = Duration.seconds(10)
    /// What is still off is caught up over this long, on top of the line's
    /// slope; without a fresh estimate the rate holds for this long, then
    /// is the kept slope.
    public static let clockDriftCatchUpTime = Duration.seconds(10)
    /// The largest correction rate and the steepest support line, in parts per million.
    public static let clockDriftMaximumRatePpm = 1000.0
    /// The kept slope is the median slope of this many estimates at most:
    /// the clock drift shown (from this many estimates on), a gap's drift,
    /// and the rate after the hold.
    public static let clockDriftShownEstimates = 60
    public static let clockDriftShownMinimumEstimates = 10
    /// How often an audio capture reports its clock drift to the status window.
    public static let clockDriftStatusInterval = Duration.seconds(1)
    /// How often `--debug` writes each audio source's clock drift line.
    public static let clockDriftDebugInterval = Duration.seconds(10)
    /// The resampler's filter: taps, phases between two samples, and its
    /// cutoff as a fraction of the sample rate.
    public static let clockDriftResamplerTaps = 64
    public static let clockDriftResamplerPhases = 512
    public static let clockDriftResamplerCutoff = 0.45
    public static let clockDriftResamplerKaiserBeta = 9.0
}

