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

/// What an audio file holds and says about itself (D45, D46): its audio
/// tracks, the reel name in its timecode track and its metadata items.
public struct AudioFileDescription: Equatable, Sendable {
    public enum Source: Equatable, Sendable {
        /// An audio input under its unique name (`AudioInputNames`).
        case audioInput(name: String, coreAudioUID: String, channelCount: Int)
        case systemAudio
    }

    public struct MetadataItem: Equatable, Sendable {
        public let key: String
        public let value: String
    }

    public static let metadataKeyPrefix = "org.schapiro.multiscreenrecorder."
    public static let systemAudioName = "System audio"

    public let source: Source
    /// The recording's start as the recording manifest gives it.
    public let recordingStart: String
    public let appVersion: String

    public init(source: Source, recordingStart: Date, timeZone: TimeZone, appVersion: String) {
        self.source = source
        self.recordingStart = RecordingManifest.timestamp(recordingStart, timeZone: timeZone)
        self.appVersion = appVersion
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

    /// One mono track per channel of an audio input; one stereo track for the system audio.
    public var channelsPerTrack: Int {
        switch source {
        case .audioInput: 1
        case .systemAudio: 2
        }
    }

    public var bitRatePerTrack: Int {
        switch source {
        case .audioInput: RecorderValues.audioInputTrackBitRate
        case .systemAudio: RecorderValues.systemAudioTrackBitRate
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

    /// QuickTime metadata items, each key under `metadataKeyPrefix`.
    public var metadata: [MetadataItem] {
        var items = [MetadataItem(key: "sourceName", value: sourceName)]
        if case .audioInput(_, let coreAudioUID, _) = source {
            items.append(MetadataItem(key: "coreAudioUID", value: coreAudioUID))
        }
        items += [
            MetadataItem(key: "channelCount", value: String(channelCount)),
            MetadataItem(key: "recordingStart", value: recordingStart),
            MetadataItem(key: "appVersion", value: appVersion),
        ]
        return items.map { MetadataItem(key: Self.metadataKeyPrefix + $0.key, value: $0.value) }
    }
}
