import Foundation

/// What an audio file holds and says about itself (D46, D49): its audio
/// tracks, the reel name in its timecode track and its metadata items, as a
/// screen file's (`VideoFileMetadata`).
public struct AudioFileDescription: Equatable, Sendable {
    public enum Source: Equatable, Sendable {
        /// An audio input under its number in the recording and its device name.
        case audioInput(number: Int, name: String, coreAudioUID: String, channelCount: Int)
        case systemAudio

        /// "Audio 2 - Razer Seiren V3 Mini", "Audio 0 - System" (`SourceLabel`).
        public var label: String {
            switch self {
            case .audioInput(let number, let name, _, _): SourceLabel.audioInput(number, name: name)
            case .systemAudio: SourceLabel.systemAudio
            }
        }
    }

    public static let systemAudioName = "System audio"

    public let source: Source
    /// The recording's start, as the recording manifest's `started`.
    public let recordingStarted: String
    /// The app and its version, as the recording manifest's `app`.
    public let app: String

    public init(source: Source, recordingStarted: String, app: String) {
        self.source = source
        self.recordingStarted = recordingStarted
        self.app = app
    }

    public var sourceName: String {
        switch source {
        case .audioInput(_, let name, _, _): name
        case .systemAudio: Self.systemAudioName
        }
    }

    public var label: String { source.label }

    public var channelCount: Int {
        switch source {
        case .audioInput(_, _, _, let channelCount): channelCount
        case .systemAudio: 2
        }
    }

    /// As the recording manifest's `channels`.
    public var channels: RecordingManifest.AudioFile.Channels {
        switch source {
        case .audioInput(_, _, _, let channelCount): .mono(channelCount)
        case .systemAudio: .stereo
        }
    }

    public var coreAudioUID: String? {
        if case .audioInput(_, _, let uid, _) = source { uid } else { nil }
    }

    /// One mono track per channel of an audio input; one stereo track for the system audio.
    public var channelsPerTrack: Int {
        switch source {
        case .audioInput: 1
        case .systemAudio: 2
        }
    }

    public var bitRatePerTrack: Int {
        switch source {
        case .audioInput: Encoding.audioInputTrackBitRate
        case .systemAudio: Encoding.systemAudioTrackBitRate
        }
    }

    /// "Audio 2 - Razer Seiren V3 Mini, channel 1", one per audio track;
    /// the label for the system audio's one track.
    public var trackNames: [String] {
        switch source {
        case .audioInput(_, _, _, let channelCount): (1...channelCount).map { "\(label), channel \($0)" }
        case .systemAudio: [label]
        }
    }

    /// The label as the timecode track's reel name.
    public var reelName: String { label }

    /// Each metadata item's full key and value: under
    /// `VideoFileMetadata.keyPrefix` as the manifest names them, the app
    /// and the reel name also under the standard keys a screen file uses.
    public var items: [(key: String, value: String)] {
        var own = [("audioSource", sourceName)]
        if let coreAudioUID { own.append(("audioSourceUID", coreAudioUID)) }
        let channelsText = switch channels {
        case .mono(let count): String(count)
        case .stereo: "stereo"
        }
        own += [("channels", channelsText), ("recordingStarted", recordingStarted), ("app", app)]
        return own.map { (VideoFileMetadata.keyPrefix + $0.0, $0.1) } + [
            (VideoFileMetadata.softwareKey, app), (VideoFileMetadata.reelKey, reelName),
            (VideoFileMetadata.cameraNameKey, reelName),
        ]
    }
}
