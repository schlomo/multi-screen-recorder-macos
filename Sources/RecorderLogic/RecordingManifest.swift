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
        public var cameraMode: String
        public var systemAudio: Bool
        public var limitCameras: Bool

        public init(_ settings: Settings) {
            resolution = settings.effectiveResolution.rawValue
            audioMode = settings.effectiveAudioMode.rawValue
            cameraMode = settings.effectiveCameraMode.rawValue
            systemAudio = settings.systemAudio
            limitCameras = settings.limitCameras
        }

        private enum CodingKeys: String, CodingKey { case resolution, audioMode, cameraMode, systemAudio, limitCameras }

        /// A manifest from before cameras were recorded (D74) has no `cameraMode`: it recorded none;
        /// one from before the cameras' limit has no `limitCameras`: none was applied.
        public init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            resolution = try container.decode(String.self, forKey: .resolution)
            audioMode = try container.decode(String.self, forKey: .audioMode)
            cameraMode = try container.decodeIfPresent(String.self, forKey: .cameraMode) ?? CameraMode.none.rawValue
            systemAudio = try container.decode(Bool.self, forKey: .systemAudio)
            limitCameras = try container.decodeIfPresent(Bool.self, forKey: .limitCameras) ?? false
        }
    }

    /// A screen file, with its guide tracks.
    public struct ScreenFile: VideoFileEntry {
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

    /// A camera file, with its guide tracks: made as a screen file is (D74).
    public struct CameraFile: VideoFileEntry {
        public var name: String
        public var camera: String
        /// AVFoundation's unique ID of the camera.
        public var cameraUniqueID: String
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
            name: String, camera: String, cameraUniqueID: String, frameSize: FrameSize, start: Double, timecode: String,
            guideTracks: [String] = []
        ) {
            self.name = name
            self.camera = camera
            self.cameraUniqueID = cameraUniqueID
            self.frameSize = [frameSize.width, frameSize.height]
            self.start = start
            end = nil
            self.timecode = timecode
            state = .recording
            self.guideTracks = guideTracks
            framesRepeatedForLateness = 0
        }

        private enum CodingKeys: String, CodingKey {
            case name, camera, cameraUniqueID, frameSize, start, end, timecode, state, guideTracks, framesRepeatedForLateness
        }

        /// `end` is written as null while the file is being written.
        public func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(name, forKey: .name)
            try container.encode(camera, forKey: .camera)
            try container.encode(cameraUniqueID, forKey: .cameraUniqueID)
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
        /// The audio source's clock drift at the file's end, in parts per
        /// million, positive when its clock runs fast: the same the status
        /// window and `--debug` show; nil until the file ends, and when it
        /// was not measured.
        public var clockDriftPpm: Double?
        /// The seconds of sound the clock drift correction added to the file
        /// (negative: removed); nil until the file ends.
        public var clockDriftCorrection: Double?
        /// An audio input's input volume at the file's start, 0 to 1; nil
        /// when it cannot be read, and for the system audio, which has none (D69).
        public var inputVolume: Double?
        /// The file's audio delays (D80), one entry per change; empty when
        /// never set, as for the system audio.
        public var delays: [Delay]

        /// From `at` seconds of the file on, its sound is `delay` seconds
        /// later than the recording's anchor's, negative when earlier (D77, D80).
        public struct Delay: Codable, Equatable, Sendable {
            public var at: Double
            public var delay: Double

            public init(at: Double, delay: Double) {
                self.at = at
                self.delay = delay
            }
        }

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
            inputVolume = nil
            delays = []
        }

        /// The file ended with `correction` seconds of sound added and the
        /// clock drift `ppm`, if measured: `clockDriftCorrection` to 0.0001 s,
        /// `clockDriftPpm` to a tenth of a ppm, neither negative zero.
        public mutating func clockDrift(correction: Double, ppm: Double?) {
            clockDriftCorrection = Self.withoutNegativeZero((correction * 10_000).rounded() / 10_000)
            clockDriftPpm = ppm.map { Self.withoutNegativeZero(($0 * 10).rounded() / 10) }
        }

        private static func withoutNegativeZero(_ value: Double) -> Double { value == 0 ? 0 : value }

        private enum CodingKeys: String, CodingKey {
            case name, audioSource, audioSourceUID, channels, start, end, timecode, state, clockDriftPpm, clockDriftCorrection,
                 inputVolume, delays
        }

        /// A file listed before `delays` existed reads with none: earlier recordings' delays are not read (D80).
        public init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            name = try container.decode(String.self, forKey: .name)
            audioSource = try container.decode(String.self, forKey: .audioSource)
            audioSourceUID = try container.decodeIfPresent(String.self, forKey: .audioSourceUID)
            channels = try container.decode(Channels.self, forKey: .channels)
            start = try container.decode(Double.self, forKey: .start)
            end = try container.decodeIfPresent(Double.self, forKey: .end)
            timecode = try container.decode(String.self, forKey: .timecode)
            state = try container.decode(State.self, forKey: .state)
            clockDriftPpm = try container.decodeIfPresent(Double.self, forKey: .clockDriftPpm)
            clockDriftCorrection = try container.decodeIfPresent(Double.self, forKey: .clockDriftCorrection)
            inputVolume = try container.decodeIfPresent(Double.self, forKey: .inputVolume)
            delays = try container.decodeIfPresent([Delay].self, forKey: .delays) ?? []
        }

        /// `end`, `clockDriftPpm` and `clockDriftCorrection` are written as null until known;
        /// `audioSourceUID` and `inputVolume`, null when it cannot be read, only for an audio input.
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
            if audioSourceUID != nil { try container.encode(inputVolume, forKey: .inputVolume) }
            try container.encode(delays, forKey: .delays)
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
        /// Every file is finalized, no file was ended by a failure and no camera stalled.
        case ok
        /// A file is not finalized or was ended by a failure, or a camera stalled (`RecordingEvent.Kind.isFailure`).
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
    /// The screen files; `files` in the JSON lists them with the camera
    /// files and the audio files, in the order of their start.
    public var files: [ScreenFile]
    public var cameraFiles: [CameraFile]
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
        cameraFiles = []
        audioFiles = []
        events = []
        problems = []
    }

    private enum CodingKeys: String, CodingKey {
        case app, state, started, ended, result, cpu, settings, files, events, problems
    }

    /// One entry of `files`: an audio file has `audioSource`, a camera file `camera`, a screen file neither.
    private enum FileEntry: Codable {
        case screen(ScreenFile)
        case camera(CameraFile)
        case audio(AudioFile)

        private enum Keys: String, CodingKey { case audioSource, camera }

        init(from decoder: any Decoder) throws {
            let keys = try decoder.container(keyedBy: Keys.self)
            self = if keys.contains(.audioSource) {
                .audio(try AudioFile(from: decoder))
            } else if keys.contains(.camera) {
                .camera(try CameraFile(from: decoder))
            } else {
                .screen(try ScreenFile(from: decoder))
            }
        }

        func encode(to encoder: any Encoder) throws {
            switch self {
            case .screen(let file): try file.encode(to: encoder)
            case .camera(let file): try file.encode(to: encoder)
            case .audio(let file): try file.encode(to: encoder)
            }
        }

        var start: Double {
            switch self {
            case .screen(let file): file.start
            case .camera(let file): file.start
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
        cameraFiles = entries.compactMap { if case .camera(let file) = $0 { file } else { nil } }
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
        let entries = files.map(FileEntry.screen) + cameraFiles.map(FileEntry.camera) + audioFiles.map(FileEntry.audio)
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

    /// Whether nothing was lost: every file is finalized, no file was
    /// ended by a failure and no camera stalled (`isFailure`). A problem
    /// told alone changes nothing (D47).
    public var endedWell: Bool {
        files.allSatisfy { $0.state == .finalized } && cameraFiles.allSatisfy { $0.state == .finalized }
            && audioFiles.allSatisfy { $0.state == .finalized }
            && !events.contains(where: \.event.isFailure)
    }

    /// An audio file started: listed from now on; false when the manifest
    /// is finalized, which changes no more, or lists it already.
    public mutating func audioFileStarted(_ file: AudioFile) -> Bool {
        guard state != .finalized, !audioFiles.contains(where: { $0.name == file.name }) else { return false }
        audioFiles.append(file)
        return true
    }

    /// An audio file ended: its entry as it ended, keeping the audio delays
    /// set while it was written; false once finalized.
    public mutating func audioFileEnded(_ file: AudioFile) -> Bool {
        guard state != .finalized else { return false }
        if let index = audioFiles.firstIndex(where: { $0.name == file.name }) {
            var file = file
            file.delays = audioFiles[index].delays
            audioFiles[index] = file
        } else {
            audioFiles.append(file)
        }
        return true
    }

    /// The newest file, the latest to start, of each audio input among `uids`, by name, with its device's UID;
    /// a file that ended stays its device's newest until the next one starts (D80).
    public func newestAudioInputFiles(of uids: Set<String>) -> [String: String] {
        let newest = Dictionary(audioFiles.filter { $0.audioSourceUID.map(uids.contains) == true }.map { ($0.audioSourceUID!, $0) }) {
            $1.start >= $0.start ? $1 : $0
        }
        return Dictionary(uniqueKeysWithValues: newest.map { ($0.value.name, $0.key) })
    }

    /// An audio file's audio delay from `at` seconds of the recording on (D80), to 0.1 ms, at a millisecond of
    /// the file, not before its start: a new entry when it differs from the latest; false when it does not,
    /// once finalized and for a file not listed.
    public mutating func audioDelaySet(_ entry: AudioDelays.Entry, at: Double, file name: String) -> Bool {
        guard state != .finalized, let index = audioFiles.firstIndex(where: { $0.name == name }) else { return false }
        let delay = (entry.delay * 10_000).rounded() / 10_000
        guard audioFiles[index].delays.last?.delay != delay else { return false }
        let since = (max(0, at - audioFiles[index].start) * 1000).rounded() / 1000
        audioFiles[index].delays.append(.init(at: since, delay: delay == 0 ? 0 : delay))
        return true
    }

    /// The file's audio delays replaced, with hindsight at Stop (D80) or cleared at a start-over (D89); the entries
    /// before, nil when unchanged.
    public mutating func audioDelaysReplaced(_ delays: [AudioFile.Delay], file name: String) -> [AudioFile.Delay]? {
        guard state != .finalized, let index = audioFiles.firstIndex(where: { $0.name == name }),
              audioFiles[index].delays != delays else { return nil }
        defer { audioFiles[index].delays = delays.map { .init(at: $0.at, delay: $0.delay == 0 ? 0 : $0.delay) } }
        return audioFiles[index].delays
    }

    /// Events reported by a capture; false once finalized.
    public mutating func record(_ new: [RecordingEvent]) -> Bool {
        guard state != .finalized else { return false }
        events += new
        return true
    }

    /// The recording ends: its end time, its result and its CPU use; a
    /// result of `problems` never comes with empty `problems` (D47). A
    /// recording log that did not end complete on disk, a problem told
    /// before, makes the result `problems` too (D64).
    public mutating func finalize(ended date: Date, timeZone: TimeZone, cpu: CPU? = nil, recordingLogWritten: Bool = true) {
        state = .finalized
        ended = Self.timestamp(date, timeZone: timeZone)
        problems += untoldProblems
        result = endedWell && recordingLogWritten ? .ok : .problems
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
                error: "\(first.problem.text) (\(count), see events)", errorDetail: first.problemErrorDetail)]
        }
        let notFinalized = files.filter { $0.state != .finalized }.map { ($0.name, $0.end ?? $0.start) }
            + cameraFiles.filter { $0.state != .finalized }.map { ($0.name, $0.end ?? $0.start) }
            + audioFiles.filter { $0.state != .finalized }.map { ($0.name, $0.end ?? $0.start) }
        guard let (name, at) = notFinalized.first else { return [] }
        return [RecordingProblem(
            atSeconds: at, problem: "A file was not finalized and nothing was told while recording", error: ErrorDetail(message: name))]
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
        case cameraConnected = "camera connected"
        case cameraDisconnected = "camera disconnected"
        case cameraFrameSizeChanged = "camera frame size changed"
        case cameraOrientationChanged = "camera orientation changed"
        case defaultCameraChanged = "default camera changed"
        case cameraStreamFailed = "camera stream failed"
        case cameraStalled = "camera stalled"
        case cameraStallEnded = "camera stall ended"
        case cameraFileWriterFellBehind = "camera file writer fell behind"
        case cameraFileWriterFailed = "camera file writer failed"
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
        case audioInputVolumeChanged = "audio input volume changed"
        case noAudioStarted = "no audio started"
        case noAudioStopped = "no audio stopped"
        /// Written by releases before D90 only, read so their recordings' manifests still load.
        case audioInputLeftTheGuideTrack = "audio input left the guide track"

        /// The events of a file ended by a failure, and a camera's stall,
        /// which loses picture: they make the result `problems` and `msr
        /// record` exit 3 (D47). An audio input that disconnects, a gap, a
        /// change of the input volume and no audio are none.
        public var isFailure: Bool {
            switch self {
            case .screenStreamFailed, .screenShowsAnotherScreensPicture, .screenFileWriterFellBehind,
                 .screenFileWriterFailed, .cameraStreamFailed, .cameraStalled, .cameraFileWriterFellBehind, .cameraFileWriterFailed, .diskFull,
                 .audioInputFailed, .systemAudioFailed, .audioFileWriterFailed,
                 .audioFileWriterFellBehind: true
            default: false
            }
        }
    }

    /// A `from` or a `to`: a frame size, an audio input's name, or an input volume.
    public enum Value: Codable, Equatable, Sendable, ExpressibleByArrayLiteral, ExpressibleByStringLiteral {
        case frameSize([Int])
        case name(String)
        /// 0 to 1.
        case volume(Double)

        public init(arrayLiteral elements: Int...) { self = .frameSize(elements) }
        public init(stringLiteral value: String) { self = .name(value) }

        public init(from decoder: any Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let size = try? container.decode([Int].self) {
                self = .frameSize(size)
            } else if let volume = try? container.decode(Double.self) {
                self = .volume(volume)
            } else {
                self = .name(try container.decode(String.self))
            }
        }

        public func encode(to encoder: any Encoder) throws {
            var container = encoder.singleValueContainer()
            switch self {
            case .frameSize(let size): try container.encode(size)
            case .name(let name): try container.encode(name)
            case .volume(let volume): try container.encode(volume)
            }
        }

        /// "1670x1080", the name, or the volume, "0.42".
        public var text: String {
            switch self {
            case .frameSize(let size): size.map(String.init).joined(separator: "x")
            case .name(let name): name
            case .volume(let volume): String(format: "%g", volume)
            }
        }
    }

    /// Seconds from the recording's start, to the millisecond.
    public var at: Double
    public var event: Kind
    /// The screen the event is about, where it is about one.
    public var screen: String?
    /// The camera the event is about, where it is about one.
    public var camera: String?
    /// The audio source the event is about, where it is about one.
    public var audioSource: String?
    /// For `screen frame size changed`, `camera frame size changed` and `camera orientation changed`: the old and the new frame size;
    /// for `default microphone changed`: the old and the new default
    /// microphone, absent where there was or is none, and as such for `default
    /// camera changed`; for `audio input
    /// volume changed`: the old and the new input volume.
    public var from: Value?
    public var to: Value?
    /// For `audio input gap` and `camera stall ended`: its length in seconds, to the millisecond.
    public var length: Double?
    /// For `screen mirroring started`: the screen it mirrors.
    public var mirrors: String?
    /// For `audio input left the guide track`, written before D90: its file's offset in seconds from the staying
    /// group's earliest input, to 0.0001 s, negative when earlier (D79).
    public var offset: Double?
    /// For a failure (`screen stream failed`, `audio input failed` and the
    /// like) and a failing writer: why, with its full chain.
    public var errorDetail: ErrorDetail?

    /// `errorDetail` as one line, `error` in the manifest.
    public var error: String? { errorDetail?.text }

    public init(at nanoseconds: Int64, event: Kind, screen: String? = nil, camera: String? = nil, audioSource: String? = nil) {
        at = (Double(nanoseconds) / 1_000_000).rounded() / 1000
        self.event = event
        self.screen = screen
        self.camera = camera
        self.audioSource = audioSource
    }

    /// The screen, camera or audio source the event is about, if any.
    public var subject: String? { screen ?? camera ?? audioSource }

    /// The event as a problem told to the person, at its time.
    public var problem: RecordingProblem {
        let what = screen.map { "Screen \($0)" } ?? camera.map { "Camera \($0)" } ?? audioSource.map { "Audio source \($0)" }
            ?? "The recording"
        return RecordingProblem(atSeconds: at, problem: what, error: problemErrorDetail)
    }

    /// The error detail of the event as a problem: the event's name, with its error under it.
    var problemErrorDetail: ErrorDetail {
        ErrorDetail(message: event.rawValue, underlying: errorDetail.map { [$0] } ?? [])
    }

    private enum CodingKeys: String, CodingKey {
        case at, event, screen, camera, audioSource, from, to, length, mirrors, offset, error, errorDetail
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        at = try container.decode(Double.self, forKey: .at)
        event = try container.decode(Kind.self, forKey: .event)
        screen = try container.decodeIfPresent(String.self, forKey: .screen)
        camera = try container.decodeIfPresent(String.self, forKey: .camera)
        audioSource = try container.decodeIfPresent(String.self, forKey: .audioSource)
        from = try container.decodeIfPresent(Value.self, forKey: .from)
        to = try container.decodeIfPresent(Value.self, forKey: .to)
        length = try container.decodeIfPresent(Double.self, forKey: .length)
        mirrors = try container.decodeIfPresent(String.self, forKey: .mirrors)
        offset = try container.decodeIfPresent(Double.self, forKey: .offset)
        // A manifest written before D64 has only the `error` text: kept as the recorder's own.
        errorDetail = try container.decodeIfPresent(ErrorDetail.self, forKey: .errorDetail)
            ?? container.decodeIfPresent(String.self, forKey: .error).map { ErrorDetail(message: $0) }
    }

    /// `error` and `errorDetail` are left out, like every other field, where there is none.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(at, forKey: .at)
        try container.encode(event, forKey: .event)
        try container.encodeIfPresent(screen, forKey: .screen)
        try container.encodeIfPresent(camera, forKey: .camera)
        try container.encodeIfPresent(audioSource, forKey: .audioSource)
        try container.encodeIfPresent(from, forKey: .from)
        try container.encodeIfPresent(to, forKey: .to)
        try container.encodeIfPresent(length, forKey: .length)
        try container.encodeIfPresent(mirrors, forKey: .mirrors)
        try container.encodeIfPresent(offset, forKey: .offset)
        try container.encodeIfPresent(error, forKey: .error)
        try container.encodeIfPresent(errorDetail, forKey: .errorDetail)
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
    /// The error with its full chain; nil exactly when `error` is nil.
    public var errorDetail: ErrorDetail?

    public init(at nanoseconds: Int64, problem: String, error: ErrorDetail?) {
        self.init(at: nanoseconds, problem: problem, error: error?.text, errorDetail: error)
    }

    /// `at` in seconds from the recording's start, as a manifest entry has it.
    public init(atSeconds seconds: Double, problem: String, error: ErrorDetail?) {
        self.init(at: Int64((seconds * 1_000_000_000).rounded()), problem: problem, error: error)
    }

    /// An error text that says more than its error detail, such as a count.
    init(atSeconds seconds: Double, problem: String, error: String, errorDetail: ErrorDetail) {
        self.init(at: Int64((seconds * 1_000_000_000).rounded()), problem: problem, error: error, errorDetail: errorDetail)
    }

    private init(at nanoseconds: Int64, problem: String, error: String?, errorDetail: ErrorDetail?) {
        at = (Double(nanoseconds) / 1_000_000).rounded() / 1000
        self.problem = problem
        self.error = error
        self.errorDetail = errorDetail
    }

    /// The problem as the person reads it.
    public var text: String { error.map { "\(problem): \($0)" } ?? problem }

    private enum CodingKeys: String, CodingKey { case at, problem, error, errorDetail }

    /// `error` and `errorDetail` are written as null when there is none.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(at, forKey: .at)
        try container.encode(problem, forKey: .problem)
        try container.encode(error, forKey: .error)
        try container.encode(errorDetail, forKey: .errorDetail)
    }
}

/// A screen file or a camera file, as the writer path keeps its entry
/// (`VideoFileTicker<RecordingManifest.ScreenFile>`): the two are made the same way (D74).
public protocol VideoFileEntry: Codable, Equatable, Sendable {
    /// "Screen" or "Camera": the word its problems name the file and the source by.
    static var sourceWord: String { get }
    /// The event of its failing writer.
    static var writerFailedEvent: RecordingEvent.Kind { get }
    /// Where an event names its source.
    static var eventSubject: WritableKeyPath<RecordingEvent, String?> { get }
    /// Where the recording manifest lists such files.
    static var manifestFiles: WritableKeyPath<RecordingManifest, [Self]> { get }
    var name: String { get }
    var frameSize: [Int] { get }
    var start: Double { get }
    var end: Double? { get set }
    var state: RecordingManifest.State { get set }
    var framesRepeatedForLateness: Int { get set }
}

extension RecordingManifest.ScreenFile {
    public static let sourceWord = "Screen"
    public static let writerFailedEvent = RecordingEvent.Kind.screenFileWriterFailed
    public static var eventSubject: WritableKeyPath<RecordingEvent, String?> { \.screen }
    public static var manifestFiles: WritableKeyPath<RecordingManifest, [Self]> { \.files }
}

extension RecordingManifest.CameraFile {
    public static let sourceWord = "Camera"
    public static let writerFailedEvent = RecordingEvent.Kind.cameraFileWriterFailed
    public static var eventSubject: WritableKeyPath<RecordingEvent, String?> { \.camera }
    public static var manifestFiles: WritableKeyPath<RecordingManifest, [Self]> { \.cameraFiles }
}
