/// The audio half's values (*data*, D45, D46): starting points, calibrated
/// at the v1 gate, beside `RecorderValues`.
extension RecorderValues {
    /// Every audio file's sample rate; every audio input measured ran at it.
    public static let audioSampleRate = 48_000
    /// An audio input's audio tracks: one mono AAC-LC track per channel.
    public static let audioInputTrackBitRate = 128_000
    /// The system audio's one stereo AAC-LC track.
    public static let systemAudioTrackBitRate = 192_000
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
}

