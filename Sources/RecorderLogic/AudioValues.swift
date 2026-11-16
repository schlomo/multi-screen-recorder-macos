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
    /// How far behind real time the guide track "Microphones" is mixed, so
    /// every source's buffers have arrived.
    public static let guideTrackDelay = Duration.milliseconds(200)
    /// How often the guide tracks are mixed and handed to the display files.
    public static let guideTrackInterval = Duration.milliseconds(100)
    /// How much of its recent output a guide track mix keeps, for a display
    /// file's last mix at its end: above the drain timeout of its ticks.
    public static let guideTrackHistorySeconds = 5
    /// How often the CPU use of our process is sampled.
    public static let cpuSampleInterval = Duration.seconds(1)
}

