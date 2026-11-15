import Foundation

/// `recording.json` in the recording folder: the settings, every file with
/// its start on the shared clock and its state, and the events (D20),
/// rewritten atomically on every change.
public struct RecordingManifest: Codable, Equatable, Sendable {
    public enum State: String, Codable, Sendable {
        case recording
        case finalized
        case notFinalized = "not finalized"
    }

    /// The settings a recording uses, as in effect: auto mode resolved.
    public struct RecordedSettings: Codable, Equatable, Sendable {
        public var resolution: String
        public var audioMode: String
        public var systemAudio: Bool

        public init(_ settings: Settings) {
            resolution = settings.effectiveResolution.rawValue
            audioMode = settings.effectiveAudioMode.rawValue
            systemAudio = settings.systemAudio
        }
    }

    /// A display file. Until the audio half of the recording core (B2,
    /// D45), a display file has no guide tracks.
    public struct DisplayFile: Codable, Equatable, Sendable {
        public var name: String
        public var display: String
        public var displayUUID: String
        public var frameSize: [Int]
        /// Seconds from the recording's start on the shared clock.
        public var start: Double
        /// Nil while the file is being written.
        public var end: Double?
        public var timecode: String
        public var state: State
        public var guideTracks: [String]
        public var framesRepeatedForLateness: Int

        public init(
            name: String, display: String, displayUUID: String, frameSize: FrameSize, start: Double, timecode: String,
            guideTracks: [String] = []
        ) {
            self.name = name
            self.display = display
            self.displayUUID = displayUUID
            self.frameSize = [frameSize.width, frameSize.height]
            self.start = start
            end = nil
            self.timecode = timecode
            state = .recording
            self.guideTracks = guideTracks
            framesRepeatedForLateness = 0
        }

        private enum CodingKeys: String, CodingKey {
            case name, display, displayUUID, frameSize, start, end, timecode, state, guideTracks, framesRepeatedForLateness
        }

        /// `end` is written as null while the file is being written.
        public func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(name, forKey: .name)
            try container.encode(display, forKey: .display)
            try container.encode(displayUUID, forKey: .displayUUID)
            try container.encode(frameSize, forKey: .frameSize)
            try container.encode(start, forKey: .start)
            try container.encode(end, forKey: .end)
            try container.encode(timecode, forKey: .timecode)
            try container.encode(state, forKey: .state)
            try container.encode(guideTracks, forKey: .guideTracks)
            try container.encode(framesRepeatedForLateness, forKey: .framesRepeatedForLateness)
        }
    }

    public var app: String
    public var state: State
    /// The local start time, ISO 8601 with milliseconds and the offset.
    public var started: String
    public var settings: RecordedSettings
    public var files: [DisplayFile]
    public var events: [RecordingEvent]

    public init(app: String, started: Date, timeZone: TimeZone, settings: Settings) {
        self.app = app
        state = .recording
        self.started = Self.timestamp(started, timeZone: timeZone)
        self.settings = RecordedSettings(settings)
        files = []
        events = []
    }

    /// "2026-11-12T14:03:05.120+01:00".
    public static func timestamp(_ date: Date, timeZone: TimeZone) -> String {
        let milliseconds = (date.timeIntervalSince1970 * 1000).rounded()
        let whole = Date(timeIntervalSince1970: (milliseconds / 1000).rounded(.down))
        let offset = timeZone.secondsFromGMT(for: whole)
        let sign = offset < 0 ? "-" : "+"
        let (hours, minutes) = (abs(offset) / 3600, abs(offset) / 60 % 60)
        let fraction = Int(milliseconds.truncatingRemainder(dividingBy: 1000) + 1000) % 1000
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: whole)
        return String(format: "%04d-%02d-%02dT%02d:%02d:%02d.%03d%@%02d:%02d",
                      parts.year ?? 0, parts.month ?? 0, parts.day ?? 0, parts.hour ?? 0, parts.minute ?? 0,
                      parts.second ?? 0, fraction, sign, hours, minutes)
    }

    /// What the manifest says of a recording whose process is gone: it and
    /// every file still being written are not finalized.
    public func markedNotFinalized() -> RecordingManifest {
        var manifest = self
        if manifest.state == .recording { manifest.state = .notFinalized }
        for index in manifest.files.indices where manifest.files[index].state == .recording {
            manifest.files[index].state = .notFinalized
        }
        return manifest
    }

    public func jsonData() throws -> Data {
        try prettyJSON(self)
    }

    public init(json data: Data) throws {
        self = try JSONDecoder().decode(RecordingManifest.self, from: data)
    }
}

/// One event of a recording, at its time on the shared clock.
public struct RecordingEvent: Codable, Equatable, Sendable {
    /// Every event the recording manifest knows, as recorder.md lists them.
    /// The audio events are written from B2 of the recording core (D45).
    public enum Kind: String, Codable, CaseIterable, Sendable {
        case displayConnected = "display connected"
        case displayDisconnected = "display disconnected"
        case displayFrameSizeChanged = "display frame size changed"
        case displayMirroringStarted = "display mirroring started"
        case displayMirroringStopped = "display mirroring stopped"
        case mainDisplayChanged = "main display changed"
        case displayStreamFailed = "display stream failed"
        case displayShowsAnotherDisplaysPicture = "display shows another display's picture"
        case displayFileWriterFellBehind = "display file writer fell behind"
        case diskFull = "disk full"
        case sleep
        case wake
        case audioInputConnected = "audio input connected"
        case audioInputDisconnected = "audio input disconnected"
        case systemAudioStarted = "system audio started"
        case systemAudioStopped = "system audio stopped"

        /// The events that make `msr record` end with an error.
        public var isError: Bool {
            switch self {
            case .displayStreamFailed, .displayShowsAnotherDisplaysPicture, .displayFileWriterFellBehind, .diskFull: true
            default: false
            }
        }
    }

    /// Seconds from the recording's start, to the millisecond.
    public var at: Double
    public var event: Kind
    /// The display the event is about, where it has one.
    public var display: String?
    /// For `display frame size changed`: the old and the new frame size.
    public var from: [Int]?
    public var to: [Int]?
    /// For `display mirroring started`: the display it mirrors.
    public var mirrors: String?
    /// For `display stream failed`: why.
    public var error: String?

    public init(at nanoseconds: Int64, event: Kind, display: String? = nil) {
        at = (Double(nanoseconds) / 1_000_000).rounded() / 1000
        self.event = event
        self.display = display
    }
}
