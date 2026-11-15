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

    /// How a finalized recording went.
    public enum Result: String, Codable, Sendable {
        case ok
        /// A problem was told, a file is not finalized, or an event is an error.
        case problems
    }

    public var app: String
    public var state: State
    /// The local start time, ISO 8601 with milliseconds and the offset.
    public var started: String
    /// The local end time, as `started`; nil until the recording is finalized.
    public var ended: String?
    /// Nil until the recording is finalized.
    public var result: Result?
    public var settings: RecordedSettings
    public var files: [DisplayFile]
    public var events: [RecordingEvent]
    /// Every problem told to the person.
    public var problems: [RecordingProblem]

    public init(app: String, started: Date, timeZone: TimeZone, settings: Settings) {
        self.app = app
        state = .recording
        self.started = Self.timestamp(started, timeZone: timeZone)
        self.settings = RecordedSettings(settings)
        files = []
        events = []
        problems = []
    }

    private enum CodingKeys: String, CodingKey {
        case app, state, started, ended, result, settings, files, events, problems
    }

    /// `ended` and `result` are written as null until the recording is
    /// finalized; `events` and `problems` in the order of their time.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(app, forKey: .app)
        try container.encode(state, forKey: .state)
        try container.encode(started, forKey: .started)
        try container.encode(ended, forKey: .ended)
        try container.encode(result, forKey: .result)
        try container.encode(settings, forKey: .settings)
        try container.encode(files, forKey: .files)
        try container.encode(Self.inTimeOrder(events, at: \.at), forKey: .events)
        try container.encode(Self.inTimeOrder(problems, at: \.at), forKey: .problems)
    }

    /// Sorted by time; those at the same time keep their order.
    private static func inTimeOrder<Item>(_ items: [Item], at time: KeyPath<Item, Double>) -> [Item] {
        items.enumerated()
            .sorted { ($0.element[keyPath: time], $0.offset) < ($1.element[keyPath: time], $1.offset) }
            .map(\.element)
    }

    /// Whether the recording went wrong: a problem was told, a file is not
    /// finalized, or an event is an error.
    public var hasProblems: Bool {
        !problems.isEmpty || files.contains { $0.state != .finalized } || events.contains(where: \.event.isError)
    }

    /// The recording ends: its end time and its result.
    public mutating func finalize(ended date: Date, timeZone: TimeZone) {
        state = .finalized
        ended = Self.timestamp(date, timeZone: timeZone)
        result = hasProblems ? .problems : .ok
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
        case displayFileWriterFailed = "display file writer failed"
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
            case .displayStreamFailed, .displayShowsAnotherDisplaysPicture, .displayFileWriterFellBehind,
                 .displayFileWriterFailed, .diskFull: true
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
    /// For `display stream failed` and `display file writer failed`: why.
    public var error: String?

    public init(at nanoseconds: Int64, event: Kind, display: String? = nil) {
        at = (Double(nanoseconds) / 1_000_000).rounded() / 1000
        self.event = event
        self.display = display
    }
}

/// A problem told to the person (the Dock badge's "!", the status window,
/// standard error in `msr record`), at its time on the shared clock.
public struct RecordingProblem: Codable, Equatable, Sendable {
    /// Seconds from the recording's start, to the millisecond.
    public var at: Double
    /// What went wrong, such as "Display file <name>".
    public var problem: String
    /// The full error text, nil when the problem says it all.
    public var error: String?

    public init(at nanoseconds: Int64, problem: String, error: String?) {
        at = (Double(nanoseconds) / 1_000_000).rounded() / 1000
        self.problem = problem
        self.error = error
    }

    /// The problem as the person reads it.
    public var text: String { error.map { "\(problem): \($0)" } ?? problem }

    private enum CodingKeys: String, CodingKey { case at, problem, error }

    /// `error` is written as null when there is none.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(at, forKey: .at)
        try container.encode(problem, forKey: .problem)
        try container.encode(error, forKey: .error)
    }
}
