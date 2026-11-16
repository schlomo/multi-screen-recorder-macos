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
/// buffers' lateness is measured in, the loop that follows it, and the fit
/// of the clock drift shown.
extension RecorderValues {
    /// Buffers are grouped by arrival in intervals of this length; each
    /// interval's smallest lateness goes into the rolling minimum.
    public static let clockDriftInterval = Duration.seconds(1)
    /// An interval with fewer buffers gives no measurement: a source with
    /// buffers of 8192 samples delivers about 6 a second.
    public static let clockDriftIntervalMinimumBuffers = 3
    /// A measurement is the smallest lateness of this many intervals, the
    /// newest and those before it: the system audio arrives in bursts, so
    /// one interval's smallest lateness is not its clock.
    public static let clockDriftRollingIntervals = 5
    /// The correction loop's natural frequency, per second, critically
    /// damped: proportional gain 2ω, integral gain ω².
    public static let clockDriftLoopFrequency = 0.3
    /// The measurements the clock drift shown is fitted over, and the
    /// fewest it is shown with.
    public static let clockDriftShownFitMeasurements = 60
    public static let clockDriftShownMinimumMeasurements = 10
    /// The first measurements after the reference or a step the clock
    /// drift shown leaves out: the loop is still settling then and the
    /// rolling minimum lags.
    public static let clockDriftShownSettlingMeasurements = 10
    /// The largest correction rate and clock drift shown, in parts per million.
    public static let clockDriftMaximumRatePpm = 1000.0
    /// A measurement more than this above the expected lateness is a stall,
    /// not the device's clock, and is rejected; more than this below it is
    /// a step, accepted at once.
    public static let clockDriftStep = Duration.milliseconds(5)
    /// After this many rejected intervals in a row the lateness really
    /// stepped up: the next measurement is accepted.
    public static let clockDriftRejectedIntervalsInARow = 10
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

