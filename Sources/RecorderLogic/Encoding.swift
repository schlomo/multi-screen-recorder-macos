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
}

/// An audio track in every display file for playback and waveform sync
/// only; the audio files hold the sources themselves.
public enum GuideTrack: Equatable, Sendable {
    case microphones
    case systemAudio

    public var name: String {
        switch self {
        case .microphones: "Microphones"
        case .systemAudio: "System audio"
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
        (settings.audioMode == .none ? [] : [.microphones]) + (settings.systemAudio ? [.systemAudio] : [])
    }
}
