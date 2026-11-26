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
    /// The guide track "Audio inputs": one mono mix of every recorded audio input channel.
    public static let audioInputsGuideTrackBitRate = 64_000
    /// The guide track "System audio", stereo.
    public static let systemAudioGuideTrackBitRate = 96_000
    /// A keyframe every this many seconds of video.
    public static let keyframeIntervalSeconds = 2
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

/// A guide track: a track in every screen file for playback and waveform
/// sync only; the audio files hold the sources themselves.
public enum GuideTrack: Hashable, Sendable {
    case audioInputs
    case systemAudio

    public var name: String {
        switch self {
        case .audioInputs: "Audio inputs"
        case .systemAudio: "System audio"
        }
    }

    /// "Audio inputs" is one mono mix, "System audio" stereo.
    public var channelCount: Int {
        switch self {
        case .audioInputs: 1
        case .systemAudio: 2
        }
    }

    public var bitRate: Int {
        switch self {
        case .audioInputs: Encoding.audioInputsGuideTrackBitRate
        case .systemAudio: Encoding.systemAudioGuideTrackBitRate
        }
    }

    /// The guide tracks a screen file has follow from the settings alone: a
    /// source that is missing is silence in its guide track. Without screen
    /// files (the recording resolution None) there are none.
    public static func tracks(for settings: Settings) -> [GuideTrack] {
        guard settings.effectiveResolution.recordsScreens else { return [] }
        return (settings.effectiveAudioMode == .none ? [] : [.audioInputs]) + (settings.systemAudio ? [.systemAudio] : [])
    }
}
