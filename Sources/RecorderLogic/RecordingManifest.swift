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

    /// A display file, with its guide tracks.
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

    /// An audio file: an audio input's mono tracks or the system audio's
    /// stereo track (D49).
    public struct AudioFile: Codable, Equatable, Sendable {
        /// An audio input's number of mono tracks, or `stereo` for the system audio.
        public enum Channels: Equatable, Sendable, Codable {
            case mono(Int)
            case stereo

            public init(from decoder: any Decoder) throws {
                let container = try decoder.singleValueContainer()
                if let count = try? container.decode(Int.self) {
                    self = .mono(count)
                } else if try container.decode(String.self) == "stereo" {
                    self = .stereo
                } else {
                    throw DecodingError.dataCorruptedError(in: container, debugDescription: "channels is a count or \"stereo\"")
                }
            }

            public func encode(to encoder: any Encoder) throws {
                var container = encoder.singleValueContainer()
                switch self {
                case .mono(let count): try container.encode(count)
                case .stereo: try container.encode("stereo")
                }
            }
        }

        public var name: String
        public var audioSource: String
        /// The audio input's Core Audio UID; nil for the system audio.
        public var audioSourceUID: String?
        public var channels: Channels
        /// Seconds from the recording's start on the shared clock.
        public var start: Double
        /// Nil while the file is being written.
        public var end: Double?
        public var timecode: String
        public var state: State
        /// The audio source's clock against the shared clock, in parts per
        /// million, positive when it runs fast; nil until it can be measured.
        public var clockDriftPpm: Double?

        public init(
            name: String, audioSource: String, audioSourceUID: String?, channels: Channels, start: Double, timecode: String
        ) {
            self.name = name
            self.audioSource = audioSource
            self.audioSourceUID = audioSourceUID
            self.channels = channels
            self.start = start
            end = nil
            self.timecode = timecode
            state = .recording
            clockDriftPpm = nil
        }

        private enum CodingKeys: String, CodingKey {
            case name, audioSource, audioSourceUID, channels, start, end, timecode, state, clockDriftPpm
        }

        /// `end` and `clockDriftPpm` are written as null until known;
        /// `audioSourceUID` only for an audio input.
        public func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(name, forKey: .name)
            try container.encode(audioSource, forKey: .audioSource)
            try container.encodeIfPresent(audioSourceUID, forKey: .audioSourceUID)
            try container.encode(channels, forKey: .channels)
            try container.encode(start, forKey: .start)
            try container.encode(end, forKey: .end)
            try container.encode(timecode, forKey: .timecode)
            try container.encode(state, forKey: .state)
            try container.encode(clockDriftPpm, forKey: .clockDriftPpm)
        }
    }

    /// Our process's CPU use over the recording, sampled every second, in
    /// percent of one core as Activity Monitor shows it; encoding and
    /// capture in macOS's own processes are not in it.
    public struct CPU: Codable, Equatable, Sendable {
        public var averagePercent: Double
        public var peakPercent: Double

        public init(averagePercent: Double, peakPercent: Double) {
            self.averagePercent = averagePercent
            self.peakPercent = peakPercent
        }
    }

    /// How a finalized recording went (D47).
    public enum Result: String, Codable, Sendable {
        /// Every file is finalized and no file was ended by a failure.
        case ok
        /// A file is not finalized or was ended by a failure.
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
    /// Nil until the recording is finalized.
    public var cpu: CPU?
    public var settings: RecordedSettings
    /// The display files; `files` in the JSON lists them with the audio
    /// files, in the order of their start.
    public var files: [DisplayFile]
    public var audioFiles: [AudioFile]
    public var events: [RecordingEvent]
    /// Every problem told to the person.
    public var problems: [RecordingProblem]

    public init(app: String, started: Date, timeZone: TimeZone, settings: Settings) {
        self.app = app
        state = .recording
        self.started = Self.timestamp(started, timeZone: timeZone)
        self.settings = RecordedSettings(settings)
        files = []
        audioFiles = []
        events = []
        problems = []
    }

    private enum CodingKeys: String, CodingKey {
        case app, state, started, ended, result, cpu, settings, files, events, problems
    }

    /// One entry of `files`: an audio file has `audioSource`, a display file not.
    private enum FileEntry: Codable {
        case display(DisplayFile)
        case audio(AudioFile)

        private enum Keys: String, CodingKey { case audioSource }

        init(from decoder: any Decoder) throws {
            let keys = try decoder.container(keyedBy: Keys.self)
            self = keys.contains(.audioSource) ? .audio(try AudioFile(from: decoder)) : .display(try DisplayFile(from: decoder))
        }

        func encode(to encoder: any Encoder) throws {
            switch self {
            case .display(let file): try file.encode(to: encoder)
            case .audio(let file): try file.encode(to: encoder)
            }
        }

        var start: Double {
            switch self {
            case .display(let file): file.start
            case .audio(let file): file.start
            }
        }
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        app = try container.decode(String.self, forKey: .app)
        state = try container.decode(State.self, forKey: .state)
        started = try container.decode(String.self, forKey: .started)
        ended = try container.decodeIfPresent(String.self, forKey: .ended)
        result = try container.decodeIfPresent(Result.self, forKey: .result)
        cpu = try container.decodeIfPresent(CPU.self, forKey: .cpu)
        settings = try container.decode(RecordedSettings.self, forKey: .settings)
        let entries = try container.decode([FileEntry].self, forKey: .files)
        files = entries.compactMap { if case .display(let file) = $0 { file } else { nil } }
        audioFiles = entries.compactMap { if case .audio(let file) = $0 { file } else { nil } }
        events = try container.decode([RecordingEvent].self, forKey: .events)
        problems = try container.decode([RecordingProblem].self, forKey: .problems)
    }

    /// `ended`, `result` and `cpu` are written as null until the recording
    /// is finalized; `files` in the order of their start, `events` and
    /// `problems` in the order of their time.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(app, forKey: .app)
        try container.encode(state, forKey: .state)
        try container.encode(started, forKey: .started)
        try container.encode(ended, forKey: .ended)
        try container.encode(result, forKey: .result)
        try container.encode(cpu, forKey: .cpu)
        try container.encode(settings, forKey: .settings)
        let entries = files.map(FileEntry.display) + audioFiles.map(FileEntry.audio)
        try container.encode(Self.inTimeOrder(entries, at: \.start), forKey: .files)
        try container.encode(Self.inTimeOrder(events, at: \.at), forKey: .events)
        try container.encode(Self.inTimeOrder(problems, at: \.at), forKey: .problems)
    }

    /// Sorted by time; those at the same time keep their order.
    private static func inTimeOrder<Item>(_ items: [Item], at time: KeyPath<Item, Double>) -> [Item] {
        items.enumerated()
            .sorted { ($0.element[keyPath: time], $0.offset) < ($1.element[keyPath: time], $1.offset) }
            .map(\.element)
    }

    /// Whether nothing was lost: every file is finalized and no file was
    /// ended by a failure. A problem told alone changes nothing (D47).
    public var endedWell: Bool {
        files.allSatisfy { $0.state == .finalized } && audioFiles.allSatisfy { $0.state == .finalized }
            && !events.contains(where: \.event.isFailure)
    }

    /// An audio file started: listed from now on; false when the manifest
    /// is finalized, which changes no more, or lists it already.
    public mutating func audioFileStarted(_ file: AudioFile) -> Bool {
        guard state != .finalized, !audioFiles.contains(where: { $0.name == file.name }) else { return false }
        audioFiles.append(file)
        return true
    }

    /// An audio file ended: its entry as it ended; false once finalized.
    public mutating func audioFileEnded(_ file: AudioFile) -> Bool {
        guard state != .finalized else { return false }
        if let index = audioFiles.firstIndex(where: { $0.name == file.name }) {
            audioFiles[index] = file
        } else {
            audioFiles.append(file)
        }
        return true
    }

    /// Events reported by a capture; false once finalized.
    public mutating func record(_ new: [RecordingEvent]) -> Bool {
        guard state != .finalized else { return false }
        events += new
        return true
    }

    /// The recording ends: its end time, its result and its CPU use. What
    /// makes the result `problems` and was not told is listed in
    /// `problems` now, so the two never disagree (D47).
    public mutating func finalize(ended date: Date, timeZone: TimeZone, cpu: CPU? = nil) {
        state = .finalized
        ended = Self.timestamp(date, timeZone: timeZone)
        problems += untoldProblems
        result = endedWell ? .ok : .problems
        self.cpu = cpu
    }

    /// The failures no problem at their time tells, and the files not
    /// finalized that no problem names.
    private var untoldProblems: [RecordingProblem] {
        let failures = events.filter { event in
            event.event.isFailure && !problems.contains { $0.at == event.at }
        }.map(\.problem)
        let named = { (name: String) in problems.contains { $0.text.contains(name) } }
        let displayFiles = files.filter { $0.state != .finalized && !named($0.name) }
            .map { RecordingProblem(atSeconds: $0.end ?? $0.start, problem: "Display file \($0.name)", error: "not finalized") }
        let audioFiles = audioFiles.filter { $0.state != .finalized && !named($0.name) }
            .map { RecordingProblem(atSeconds: $0.end ?? $0.start, problem: "Audio file \($0.name)", error: "not finalized") }
        return failures + displayFiles + audioFiles
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
        case defaultMicrophoneChanged = "default microphone changed"
        case audioInputGap = "audio input gap"
        case audioInputFailed = "audio input failed"
        case systemAudioFailed = "system audio failed"
        case audioFileWriterFailed = "audio file writer failed"
        case audioFileWriterFellBehind = "audio file writer fell behind"

        /// The events of a file ended by a failure, which make the result
        /// `problems` and `msr record` exit 3 (D47). An audio input that
        /// disconnects, and a gap, are none.
        public var isFailure: Bool {
            switch self {
            case .displayStreamFailed, .displayShowsAnotherDisplaysPicture, .displayFileWriterFellBehind,
                 .displayFileWriterFailed, .diskFull, .audioInputFailed, .systemAudioFailed, .audioFileWriterFailed,
                 .audioFileWriterFellBehind: true
            default: false
            }
        }
    }

    /// A `from` or a `to`: a frame size, or an audio input's name.
    public enum Value: Codable, Equatable, Sendable, ExpressibleByArrayLiteral, ExpressibleByStringLiteral {
        case frameSize([Int])
        case name(String)

        public init(arrayLiteral elements: Int...) { self = .frameSize(elements) }
        public init(stringLiteral value: String) { self = .name(value) }

        public init(from decoder: any Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let size = try? container.decode([Int].self) {
                self = .frameSize(size)
            } else {
                self = .name(try container.decode(String.self))
            }
        }

        public func encode(to encoder: any Encoder) throws {
            var container = encoder.singleValueContainer()
            switch self {
            case .frameSize(let size): try container.encode(size)
            case .name(let name): try container.encode(name)
            }
        }

        /// "1670x1080" or the name.
        public var text: String {
            switch self {
            case .frameSize(let size): size.map(String.init).joined(separator: "x")
            case .name(let name): name
            }
        }
    }

    /// Seconds from the recording's start, to the millisecond.
    public var at: Double
    public var event: Kind
    /// The display the event is about, where it is about one.
    public var display: String?
    /// The audio source the event is about, where it is about one.
    public var audioSource: String?
    /// For `display frame size changed`: the old and the new frame size;
    /// for `default microphone changed`: the old and the new default
    /// microphone, absent where there was or is none.
    public var from: Value?
    public var to: Value?
    /// For `audio input gap`: its length in seconds, to the millisecond.
    public var length: Double?
    /// For `display mirroring started`: the display it mirrors.
    public var mirrors: String?
    /// For a failure (`display stream failed`, `audio input failed` and the
    /// like) and a failing writer: why.
    public var error: String?

    public init(at nanoseconds: Int64, event: Kind, display: String? = nil, audioSource: String? = nil) {
        at = (Double(nanoseconds) / 1_000_000).rounded() / 1000
        self.event = event
        self.display = display
        self.audioSource = audioSource
    }

    /// The display or audio source the event is about, if any.
    public var subject: String? { display ?? audioSource }

    /// The event as a problem told to the person, at its time.
    public var problem: RecordingProblem {
        let what = display.map { "Display \($0)" } ?? audioSource.map { "Audio source \($0)" } ?? "The recording"
        return RecordingProblem(atSeconds: at, problem: what, error: error.map { "\(event.rawValue): \($0)" } ?? event.rawValue)
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

    /// `at` in seconds from the recording's start, as a manifest entry has it.
    init(atSeconds seconds: Double, problem: String, error: String?) {
        self.init(at: Int64((seconds * 1_000_000_000).rounded()), problem: problem, error: error)
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
