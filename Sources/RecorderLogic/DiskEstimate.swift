import Foundation

/// How much disk space a recording needs per hour, file by file: a video
/// file (a screen file or a camera file) is its video plus its guide tracks,
/// an audio file its tracks, all at the rates in `Encoding`.
public enum DiskEstimate {
    public static func videoFileBytesPerHour(frameSize: FrameSize, settings: Settings) -> Double {
        let video = Encoding.videoBytesPerHour(frameSize: frameSize)
        return video + bytesPerHour(bitRate: GuideTrack.tracks(for: settings).map(\.bitRate).reduce(0, +))
    }

    public static func audioInputFileBytesPerHour(channelCount: Int) -> Double {
        bytesPerHour(bitRate: channelCount * Encoding.audioInputTrackBitRate)
    }

    public static let systemAudioFileBytesPerHour = bytesPerHour(bitRate: Encoding.systemAudioTrackBitRate)

    /// Every file a recording with these settings and devices writes, no
    /// screen file and no camera file at the recording resolution None; nil when the channels of an
    /// audio input it records cannot be read. A camera file is estimated as a screen file of its frame size.
    public static func bytesPerHour(
        settings: Settings, screens: [ScreenInfo], audioInputs: [AudioInputInfo], cameras: [CameraInfo] = []
    ) -> Double? {
        let recordedScreens = settings.effectiveResolution.recordsScreens ? screens : []
        let screenFiles = recordedScreens.map {
            videoFileBytesPerHour(
                frameSize: settings.effectiveResolution.frameSize(forLooksLike: $0.pointSize), settings: settings)
        }
        var audioInputFiles: [Double] = []
        for input in audioInputs where AudioTracker.records(input, settings: settings) {
            guard case .success(let channelCount) = input.channelCount else { return nil }
            audioInputFiles.append(audioInputFileBytesPerHour(channelCount: channelCount))
        }
        let cameraFiles = cameras.filter { CameraTracker.records($0, settings: settings) }.compactMap { camera in
            camera.frameSize(resolution: settings.effectiveResolution, limited: settings.limitCameras).map { videoFileBytesPerHour(frameSize: $0, settings: settings) }
        }
        let systemAudioFile = settings.systemAudio ? systemAudioFileBytesPerHour : 0
        return (screenFiles + cameraFiles + audioInputFiles).reduce(systemAudioFile, +)
    }

    private static func bytesPerHour(bitRate: Int) -> Double {
        Double(bitRate) * 3600 / 8
    }

    /// Decimal gigabytes with one digit, as Finder shows them.
    public static func gigabytes(_ bytes: Double) -> String {
        String(format: "%.1f GB", bytes / 1_000_000_000)
    }

    /// Decimal megabytes without a digit below 1 GB, as they round, from
    /// there gigabytes with one digit: the status window's sizes.
    public static func megabytesOrGigabytes(_ bytes: Double) -> String {
        bytes < 999_500_000 ? String(format: "%.0f MB", bytes / 1_000_000) : gigabytes(bytes)
    }

    /// Decimal gigabytes per hour with one digit, "<0.1" below 0.05.
    public static func gigabytesPerHour(_ bytesPerHour: Double) -> String {
        bytesPerHour < 50_000_000 ? "<0.1" : String(format: "%.1f", bytesPerHour / 1_000_000_000)
    }
}
