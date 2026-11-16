/// The encoding values (*data*): the encoders write with them and the disk
/// estimate counts them. Bit rates are in bits per second.
public enum Encoding {
    /// Video at 1080p; other frame sizes scale by their pixel count. A
    /// starting point, calibrated at the v1 gate.
    public static let videoBytesPerHourAt1080p = 1_000_000_000.0
    /// Each mono track of an audio input's audio file, one per channel.
    public static let audioInputTrackBitRate = 128_000
    /// The stereo track of the system audio's audio file.
    public static let systemAudioTrackBitRate = 192_000
    /// The guide track "Microphones": one mono mix of every recorded microphone channel.
    public static let microphonesGuideTrackBitRate = 64_000
    /// The guide track "System audio", stereo.
    public static let systemAudioGuideTrackBitRate = 96_000
    /// A keyframe every this many seconds of video.
    public static let keyframeIntervalSeconds = 2
    public static let keyframeIntervalFrames = keyframeIntervalSeconds * RecorderValues.framesPerSecond
    /// The encoder's quality target, 0 to 1: video is quality-targeted
    /// variable bit rate with a ceiling. A starting point, not designed.
    public static let videoQuality = 0.5
    /// The ceiling as a multiple of the estimated average rate of the frame
    /// size (`videoBytesPerHourAt1080p` scaled by pixel count). A starting
    /// point, not designed.
    public static let videoCeilingFactor = 4.0

    /// The bit rate the disk estimate counts for video of this frame size.
    public static func videoBytesPerHour(frameSize: FrameSize) -> Double {
        Double(frameSize.pixelCount) / Double(FrameSize.fullHD.pixelCount) * videoBytesPerHourAt1080p
    }

    /// The ceiling of the video's bit rate, in bytes per second.
    public static func videoCeilingBytesPerSecond(frameSize: FrameSize) -> Int {
        Int(videoBytesPerHour(frameSize: frameSize) / 3600 * videoCeilingFactor)
    }
}

/// A guide track: a track in every display file for playback and waveform
/// sync only; the audio files hold the sources themselves.
public enum GuideTrack: Hashable, Sendable {
    case microphones
    case systemAudio

    public var name: String {
        switch self {
        case .microphones: "Microphones"
        case .systemAudio: "System audio"
        }
    }

    /// "Microphones" is one mono mix, "System audio" stereo.
    public var channelCount: Int {
        switch self {
        case .microphones: 1
        case .systemAudio: 2
        }
    }

    public var bitRate: Int {
        switch self {
        case .microphones: Encoding.microphonesGuideTrackBitRate
        case .systemAudio: Encoding.systemAudioGuideTrackBitRate
        }
    }

    /// The guide tracks a display file has follow from the settings alone: a
    /// source that is missing is silence in its guide track.
    public static func tracks(for settings: Settings) -> [GuideTrack] {
        (settings.effectiveAudioMode == .none ? [] : [.microphones]) + (settings.systemAudio ? [.systemAudio] : [])
    }
}
