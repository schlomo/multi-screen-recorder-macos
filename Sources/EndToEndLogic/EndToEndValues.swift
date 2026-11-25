/// The end-to-end tests' tolerances (*data*), calibrated on the first
/// recordings on the owner's Mac (2026-11-19) and to be revisited when a
/// run shows them too tight or too loose.
public enum EndToEndValues {
    /// How far a time in the manifest may be from when the driver saw the
    /// change happen, beyond the settle time, in seconds.
    public static let timeTolerance = 0.5
    /// How long after the stop a recording and its files may end, in
    /// seconds: finalizing every file comes first. Uncalibrated until the
    /// pipeline's first run; each scenario prints its margin for that.
    public static let finalizeAllowance = 3.0
    /// How long a screen waits unchanged before its file starts: the
    /// recorder's settle time (recorder.md), restated here, not read from
    /// the recorder's code.
    public static let settleTime = 1.0
    /// How long after its settle time ends a screen file may start, the
    /// new stream's first frame included: the recorder design's target
    /// (recorder.md, owner's ruling in D63).
    public static let firstFrameLimit = 1.0
    /// How long the driver waits for the screens to settle after a change
    /// before it stops: they settle within about 2.5 s on the runner.
    public static let screensSettleLimit = 15.0
    /// How long the driver waits for every audio input file of the app's recording to be out of
    /// measuring (`AudioMeasuring`) before the status window's screenshots and video, in seconds.
    public static let audioMeasuringLimit = 90.0
    /// How much less than everything up to the kill's last fragment a
    /// killed file may hold, in seconds.
    public static let killSlack = 0.5
    /// How far behind real time the recorder mixes the guide tracks, in
    /// seconds: a screen file's fragment is written only once its guide
    /// samples arrive, so a killed one holds that much less. The recorder's
    /// `RecorderValues.guideTrackDelay` (recorder.md, D80), restated here,
    /// not read from the recorder's code.
    public static let guideTrackDelay = 1.0
    /// How much of a recording's start the review artifact keeps of one
    /// screen file per scenario and of the loopback device's audio file, in
    /// seconds, cut without re-encoding.
    public static let reviewExcerptSeconds = 5
    /// How far the tone's level may be from what was played, in dB.
    public static let levelTolerance = 1.0
    /// A stretch this far below the tone's level is silent, in dB.
    public static let quietBelowTone = 10.0
    /// How far apart the same click may be in two files, placed by their
    /// timecode, in seconds.
    public static let clickTolerance = 0.005
    /// How far two clicks in one file may be from one second apart.
    public static let clickPeriodTolerance = 0.001
    /// A run of samples this far below the tone's peak is a hole, in the test tone's amplitude
    /// as a fraction: the 1 kHz sine stays below 5 % of its peak for 0.032 ms around a zero
    /// crossing, so a run of at least `holeSeconds` cannot be the tone.
    public static let holeBelowTonePeak = 0.05
    /// The shortest quiet run counted as a hole: one period of the tone.
    public static let holeSeconds = 0.001
}
