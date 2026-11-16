import Foundation

/// The names of a recording's audio inputs: a device name as part of a file
/// name (`RecordingNames.fileNamePart`), and two audio inputs with the same
/// name told apart by " (2)", " (3)" in order of appearance. An audio input
/// that comes back keeps its name.
public struct AudioInputNames: Sendable {
    private var namesByUID: [String: String] = [:]
    private var taken: Set<String> = []

    public init() {}

    public mutating func name(coreAudioUID: String, deviceName: String) -> String {
        if let name = namesByUID[coreAudioUID] { return name }
        let base = RecordingNames.fileNamePart(deviceName)
        var name = base
        var copy = 2
        while taken.contains(name) {
            name = "\(base) (\(copy))"
            copy += 1
        }
        namesByUID[coreAudioUID] = name
        taken.insert(name)
        return name
    }
}

/// What an audio file holds and says about itself (D46, D49): its audio
/// tracks, the reel name in its timecode track and its metadata items, as a
/// display file's (`DisplayFileMetadata`).
public struct AudioFileDescription: Equatable, Sendable {
    public enum Source: Equatable, Sendable {
        /// An audio input under its unique name (`AudioInputNames`).
        case audioInput(name: String, coreAudioUID: String, channelCount: Int)
        case systemAudio
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
        case .audioInput(let name, _, _): name
        case .systemAudio: Self.systemAudioName
        }
    }

    public var channelCount: Int {
        switch source {
        case .audioInput(_, _, let channelCount): channelCount
        case .systemAudio: 2
        }
    }

    /// As the recording manifest's `channels`.
    public var channels: RecordingManifest.AudioFile.Channels {
        switch source {
        case .audioInput(_, _, let channelCount): .mono(channelCount)
        case .systemAudio: .stereo
        }
    }

    public var coreAudioUID: String? {
        if case .audioInput(_, let uid, _) = source { uid } else { nil }
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

    /// "Microphone: Razer Seiren V3 Mini, channel 1", one per audio track.
    public var trackNames: [String] {
        switch source {
        case .audioInput(let name, _, let channelCount): (1...channelCount).map { "Microphone: \(name), channel \($0)" }
        case .systemAudio: [Self.systemAudioName]
        }
    }

    /// "Microphone - Razer Seiren V3 Mini": the source as the timecode track's reel name.
    public var reelName: String {
        switch source {
        case .audioInput(let name, _, _): "Microphone - \(name)"
        case .systemAudio: Self.systemAudioName
        }
    }

    /// Each metadata item's full key and value: under
    /// `DisplayFileMetadata.keyPrefix` as the manifest names them, the app
    /// and the reel name also under the standard keys a display file uses.
    public var items: [(key: String, value: String)] {
        var own = [("audioSource", sourceName)]
        if let coreAudioUID { own.append(("audioSourceUID", coreAudioUID)) }
        let channelsText = switch channels {
        case .mono(let count): String(count)
        case .stereo: "stereo"
        }
        own += [("channels", channelsText), ("recordingStarted", recordingStarted), ("app", app)]
        return own.map { (DisplayFileMetadata.keyPrefix + $0.0, $0.1) } + [
            (DisplayFileMetadata.softwareKey, app), (DisplayFileMetadata.reelKey, reelName),
            (DisplayFileMetadata.cameraNameKey, reelName),
        ]
    }
}
