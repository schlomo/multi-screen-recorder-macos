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

/// The clock drift correction's values (*data*): the windows the buffers'
/// lateness is measured in, the fits, and how fast the correction follows.
extension RecorderValues {
    /// Buffers are grouped by arrival in windows of this length; a window's
    /// smallest lateness is one measurement.
    public static let clockDriftWindow = Duration.seconds(1)
    /// A window with fewer buffers gives no measurement.
    public static let clockDriftWindowMinimumBuffers = 10
    /// The measurements the correction rate's slope is fitted over.
    public static let clockDriftRateFitMeasurements = 10
    /// The measurements the clock drift shown is fitted over, and the
    /// fewest it is shown with.
    public static let clockDriftShownFitMeasurements = 60
    public static let clockDriftShownMinimumMeasurements = 10
    /// How fast the correction closes what is still off: that divided by this.
    public static let clockDriftFollowTime = Duration.seconds(5)
    /// The largest correction rate, in parts per million.
    public static let clockDriftMaximumRatePpm = 1000.0
    /// A measurement more than this above the expected lateness is a stall,
    /// not the device's clock, and is rejected.
    public static let clockDriftRejectedLateness = Duration.milliseconds(5)
    /// After this many rejected windows in a row the lateness really
    /// stepped up: the next measurement is accepted.
    public static let clockDriftRejectedWindowsInARow = 10
    /// An audio file shorter than this has no `clockDriftPpm`.
    public static let clockDriftShortestFile = Duration.seconds(10)
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

