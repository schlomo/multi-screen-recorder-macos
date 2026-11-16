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

    /// A screen file, with its guide tracks.
    public struct ScreenFile: Codable, Equatable, Sendable {
        public var name: String
        public var screen: String
        public var screenUUID: String
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
            name: String, screen: String, screenUUID: String, frameSize: FrameSize, start: Double, timecode: String,
            guideTracks: [String] = []
        ) {
            self.name = name
            self.screen = screen
            self.screenUUID = screenUUID
            self.frameSize = [frameSize.width, frameSize.height]
            self.start = start
            end = nil
            self.timecode = timecode
            state = .recording
            self.guideTracks = guideTracks
            framesRepeatedForLateness = 0
        }

        private enum CodingKeys: String, CodingKey {
            case name, screen, screenUUID, frameSize, start, end, timecode, state, guideTracks, framesRepeatedForLateness
        }

        /// `end` is written as null while the file is being written.
        public func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(name, forKey: .name)
            try container.encode(screen, forKey: .screen)
            try container.encode(screenUUID, forKey: .screenUUID)
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
        /// The audio source's clock against the shared clock over the file,
        /// in parts per million, positive when it runs fast: the clock drift
        /// correction over the file's duration; nil until the file ends, and
        /// for a file shorter than `clockDriftShortestFile`.
        public var clockDriftPpm: Double?
        /// The seconds of sound the clock drift correction added to the file
        /// (negative: removed); nil until the file ends.
        public var clockDriftCorrection: Double?

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
            clockDriftCorrection = nil
        }

        /// The file ended after `duration` seconds, with `correction`
        /// seconds of sound added: `clockDriftCorrection` to 0.0001 s and,
        /// for a file long enough, `clockDriftPpm` to a tenth of a ppm.
        public mutating func clockDrift(
            correction: Double, duration: Double, shortest: Duration = RecorderValues.clockDriftShortestFile
        ) {
            clockDriftCorrection = (correction * 10_000).rounded() / 10_000
            let isLongEnough = duration > 0 && duration * 1e9 >= Double(shortest.nanoseconds)
            clockDriftPpm = isLongEnough ? (-correction / duration * 1e7).rounded() / 10 : nil
        }

        private enum CodingKeys: String, CodingKey {
            case name, audioSource, audioSourceUID, channels, start, end, timecode, state, clockDriftPpm, clockDriftCorrection
        }

        /// `end`, `clockDriftPpm` and `clockDriftCorrection` are written as null until known;
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
            try container.encode(clockDriftCorrection, forKey: .clockDriftCorrection)
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
    /// The screen files; `files` in the JSON lists them with the audio
    /// files, in the order of their start.
    public var files: [ScreenFile]
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

    /// One entry of `files`: an audio file has `audioSource`, a screen file not.
    private enum FileEntry: Codable {
        case screen(ScreenFile)
        case audio(AudioFile)

        private enum Keys: String, CodingKey { case audioSource }

        init(from decoder: any Decoder) throws {
            let keys = try decoder.container(keyedBy: Keys.self)
            self = keys.contains(.audioSource) ? .audio(try AudioFile(from: decoder)) : .screen(try ScreenFile(from: decoder))
        }

        func encode(to encoder: any Encoder) throws {
            switch self {
            case .screen(let file): try file.encode(to: encoder)
            case .audio(let file): try file.encode(to: encoder)
            }
        }

        var start: Double {
            switch self {
            case .screen(let file): file.start
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
        files = entries.compactMap { if case .screen(let file) = $0 { file } else { nil } }
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
        let entries = files.map(FileEntry.screen) + audioFiles.map(FileEntry.audio)
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

    /// The recording ends: its end time, its result and its CPU use; a
    /// result of `problems` never comes with empty `problems` (D47).
    public mutating func finalize(ended date: Date, timeZone: TimeZone, cpu: CPU? = nil) {
        state = .finalized
        ended = Self.timestamp(date, timeZone: timeZone)
        problems += untoldProblems
        result = endedWell ? .ok : .problems
        self.cpu = cpu
    }

    /// D47's rule that `problems` is never empty when the result is
    /// `problems`: failures are told while recording, so this adds a
    /// problem only when nothing was told, naming the first failure and
    /// how many there were, or else the first file not finalized.
    private var untoldProblems: [RecordingProblem] {
        guard problems.isEmpty, !endedWell else { return [] }
        let failures = events.filter(\.event.isFailure).sorted { $0.at < $1.at }
        if let first = failures.first {
            let count = failures.count == 1 ? "1 failure event" : "\(failures.count) failure events"
            return [RecordingProblem(
                atSeconds: first.at, problem: "A failure was not told while recording",
                error: "\(first.problem.text) (\(count), see events)")]
        }
        let notFinalized = files.filter { $0.state != .finalized }.map { ($0.name, $0.end ?? $0.start) }
            + audioFiles.filter { $0.state != .finalized }.map { ($0.name, $0.end ?? $0.start) }
        guard let (name, at) = notFinalized.first else { return [] }
        return [RecordingProblem(
            atSeconds: at, problem: "A file was not finalized and nothing was told while recording", error: name)]
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
        case screenConnected = "screen connected"
        case screenDisconnected = "screen disconnected"
        case screenFrameSizeChanged = "screen frame size changed"
        case screenMirroringStarted = "screen mirroring started"
        case screenMirroringStopped = "screen mirroring stopped"
        case mainScreenChanged = "main screen changed"
        case screenStreamFailed = "screen stream failed"
        case screenShowsAnotherScreensPicture = "screen shows another screen's picture"
        case screenFileWriterFellBehind = "screen file writer fell behind"
        case screenFileWriterFailed = "screen file writer failed"
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
            case .screenStreamFailed, .screenShowsAnotherScreensPicture, .screenFileWriterFellBehind,
                 .screenFileWriterFailed, .diskFull, .audioInputFailed, .systemAudioFailed, .audioFileWriterFailed,
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
    /// The screen the event is about, where it is about one.
    public var screen: String?
    /// The audio source the event is about, where it is about one.
    public var audioSource: String?
    /// For `screen frame size changed`: the old and the new frame size;
    /// for `default microphone changed`: the old and the new default
    /// microphone, absent where there was or is none.
    public var from: Value?
    public var to: Value?
    /// For `audio input gap`: its length in seconds, to the millisecond.
    public var length: Double?
    /// For `screen mirroring started`: the screen it mirrors.
    public var mirrors: String?
    /// For a failure (`screen stream failed`, `audio input failed` and the
    /// like) and a failing writer: why.
    public var error: String?

    public init(at nanoseconds: Int64, event: Kind, screen: String? = nil, audioSource: String? = nil) {
        at = (Double(nanoseconds) / 1_000_000).rounded() / 1000
        self.event = event
        self.screen = screen
        self.audioSource = audioSource
    }

    /// The screen or audio source the event is about, if any.
    public var subject: String? { screen ?? audioSource }

    /// The event as a problem told to the person, at its time.
    public var problem: RecordingProblem {
        let what = screen.map { "Screen \($0)" } ?? audioSource.map { "Audio source \($0)" } ?? "The recording"
        return RecordingProblem(atSeconds: at, problem: what, error: error.map { "\(event.rawValue): \($0)" } ?? event.rawValue)
    }
}

/// A problem told to the person (the Dock badge's "!", the status window,
/// standard error in `msr record`), at its time on the shared clock.
public struct RecordingProblem: Codable, Equatable, Sendable {
    /// Seconds from the recording's start, to the millisecond.
    public var at: Double
    /// What went wrong, such as "Screen file <name>".
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
