import Foundation

/// How much disk space a recording needs per hour, file by file: a display
/// file is its video plus its guide tracks, an audio file its tracks, all at
/// the rates in `Encoding`.
public enum DiskEstimate {
    private static let pixelsAt1080p = Double(FrameSize(width: 1920, height: 1080).pixelCount)

    public static func displayFileBytesPerHour(frameSize: FrameSize, settings: Settings) -> Double {
        let video = Double(frameSize.pixelCount) / pixelsAt1080p * Encoding.videoBytesPerHourAt1080p
        return video + bytesPerHour(bitRate: GuideTrack.tracks(for: settings).map(\.bitRate).reduce(0, +))
    }

    public static func audioInputFileBytesPerHour(channelCount: Int) -> Double {
        bytesPerHour(bitRate: channelCount * Encoding.audioInputTrackBitRate)
    }

    public static let systemAudioFileBytesPerHour = bytesPerHour(bitRate: Encoding.systemAudioTrackBitRate)

    /// Every file a recording with these settings and devices writes; nil
    /// when the channels of an audio input it records cannot be read.
    public static func bytesPerHour(settings: Settings, displays: [DisplayInfo], audioInputs: [AudioInputInfo]) -> Double? {
        let displayFiles = displays.map {
            displayFileBytesPerHour(frameSize: settings.resolution.frameSize(forDisplay: $0.pixelSize), settings: settings)
        }
        var audioInputFiles: [Double] = []
        for input in audioInputs where settings.records(input) {
            guard case .success(let channelCount) = input.channelCount else { return nil }
            audioInputFiles.append(audioInputFileBytesPerHour(channelCount: channelCount))
        }
        let systemAudioFile = settings.systemAudio ? systemAudioFileBytesPerHour : 0
        return (displayFiles + audioInputFiles).reduce(systemAudioFile, +)
    }

    private static func bytesPerHour(bitRate: Int) -> Double {
        Double(bitRate) * 3600 / 8
    }

    /// Decimal gigabytes with one digit, as Finder shows them.
    public static func gigabytes(_ bytes: Double) -> String {
        String(format: "%.1f GB", bytes / 1_000_000_000)
    }

    /// Decimal gigabytes per hour with one digit, "<0.1" below 0.05.
    public static func gigabytesPerHour(_ bytesPerHour: Double) -> String {
        bytesPerHour < 50_000_000 ? "<0.1" : String(format: "%.1f", bytesPerHour / 1_000_000_000)
    }
}
