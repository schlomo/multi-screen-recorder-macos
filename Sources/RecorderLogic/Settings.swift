import Foundation

/// Which audio inputs are recorded, as the steps of the window's slider.
public enum AudioMode: String, CaseIterable, Sendable, Encodable {
    case none
    case defaultMicrophone = "default-microphone"
    case wired
    case allInputs = "all-inputs"

    /// The word on the slider.
    public var label: String {
        switch self {
        case .none: "None"
        case .defaultMicrophone: "Default microphone"
        case .wired: "Wired"
        case .allInputs: "All"
        }
    }

    /// Said under the slider.
    public static let bluetoothAndVirtualNote =
        "Bluetooth and virtual microphones are recorded only under All, or when they are the default microphone:"
        + " recording a Bluetooth headset's microphone switches it to call quality, and a virtual microphone"
        + " often carries a copy of other sound."

    /// The position of this audio mode on the slider, which runs over `allCases`.
    public var sliderIndex: Double { indexOnSlider(of: self, in: Self.allCases) }

    /// The audio mode the slider's `position` selects (rounded, kept in range),
    /// or nil when that is this one: nothing to change, save or check.
    public func choosing(sliderPosition position: Double) -> AudioMode? {
        sliderChoice(at: position, in: Self.allCases, current: self)
    }
}

/// A key of the settings file; each has a flag of the same name in kebab case.
public enum SettingKey: String, CaseIterable, Sendable {
    case auto
    case resolution
    case audioMode
    case systemAudio
    case outputFolder
    case requiredRecordingHours
    case lowDiskWarningMinutes

    public var flagName: String {
        "--" + rawValue.replacing(/[A-Z]/) { "-" + $0.output.lowercased() }
    }
}

public struct Settings: Equatable, Sendable, Encodable {
    /// Auto mode: every display at Native and the audio mode Wired,
    /// whatever `resolution` and `audioMode` say.
    public var auto: Bool
    public var resolution: RecordingResolution
    public var audioMode: AudioMode
    public var systemAudio: Bool
    /// As written in the settings file, possibly starting with `~`.
    public var outputFolder: String
    public var requiredRecordingHours: Double
    public var lowDiskWarningMinutes: Double

    public init(
        auto: Bool,
        resolution: RecordingResolution,
        audioMode: AudioMode,
        systemAudio: Bool,
        outputFolder: String,
        requiredRecordingHours: Double,
        lowDiskWarningMinutes: Double
    ) {
        self.auto = auto
        self.resolution = resolution
        self.audioMode = audioMode
        self.systemAudio = systemAudio
        self.outputFolder = outputFolder
        self.requiredRecordingHours = requiredRecordingHours
        self.lowDiskWarningMinutes = lowDiskWarningMinutes
    }

    /// What auto mode chooses; also the defaults of the two sliders, so
    /// turning auto mode off changes nothing until a slider is moved.
    public static let autoResolution = RecordingResolution.native
    public static let autoAudioMode = AudioMode.wired

    public static let defaults = Settings(
        auto: true,
        resolution: autoResolution,
        audioMode: autoAudioMode,
        systemAudio: true,
        outputFolder: "~/Movies/Multi Screen Recorder",
        requiredRecordingHours: 2,
        lowDiskWarningMinutes: 20
    )

    /// The resolution a recording with these settings uses.
    public var effectiveResolution: RecordingResolution { auto ? Self.autoResolution : resolution }

    /// The audio mode a recording with these settings uses.
    public var effectiveAudioMode: AudioMode { auto ? Self.autoAudioMode : audioMode }

    /// Whether a recording with these settings records the audio input. The
    /// default microphone is recorded in every audio mode but none, whatever
    /// its transport.
    public func records(_ input: AudioInputInfo) -> Bool {
        switch effectiveAudioMode {
        case .none: false
        case .defaultMicrophone: input.isDefault
        case .wired: input.isDefault || input.transport.isWired
        case .allInputs: true
        }
    }

    public func outputFolderURL(homeFolder: URL) -> URL {
        if outputFolder == "~" { return homeFolder }
        if outputFolder.hasPrefix("~/") {
            return homeFolder.appending(path: String(outputFolder.dropFirst(2)), directoryHint: .isDirectory)
        }
        return URL(filePath: outputFolder, directoryHint: .isDirectory)
    }

    /// How a chosen folder is written into the settings: inside the home
    /// folder with `~`, elsewhere as an absolute path.
    public static func outputFolderSetting(for folder: URL, homeFolder: URL) -> String {
        let path = folder.standardizedFileURL.path(percentEncoded: false).trimmingSuffix("/")
        let home = homeFolder.standardizedFileURL.path(percentEncoded: false).trimmingSuffix("/")
        if path == home { return "~" }
        if path.hasPrefix(home + "/") { return "~" + path.dropFirst(home.count) }
        return path
    }
}

extension String {
    fileprivate func trimmingSuffix(_ suffix: String) -> String {
        count > suffix.count && hasSuffix(suffix) ? String(dropLast(suffix.count)) : self
    }
}

// MARK: - Errors

/// A flag the person gave that cannot be used; a usage error.
public enum SettingsError: Error, Equatable, Sendable, CustomStringConvertible {
    case invalidFlagValue(flag: String, value: String, expected: String)
    case conflictingFlags(flag: String)

    public var description: String {
        switch self {
        case .invalidFlagValue(let flag, let value, let expected):
            "invalid value \"\(value)\" for \(flag), expected \(expected)"
        case .conflictingFlags(let flag): "--auto cannot be combined with \(flag)"
        }
    }
}

// MARK: - Values

private enum Expected {
    static func oneOf(_ words: [String]) -> String { "one of " + words.joined(separator: ", ") }
    static let resolution = oneOf(RecordingResolution.allCases.map(\.rawValue))
    static let audioMode = oneOf(AudioMode.allCases.map(\.rawValue))
    static let jsonSwitch = "true or false"
    static let flagSwitch = "on or off"
    static let folder = "a folder path starting with / or ~"
    static let positiveNumber = "a number greater than 0"
}

private func validFolder(_ path: String) -> String? {
    path == "~" || path.hasPrefix("~/") || path.hasPrefix("/") ? path : nil
}

private func validPositive(_ number: Double) -> Double? {
    number.isFinite && number > 0 ? number : nil
}

/// A value as it appears in JSON, so a wrong type is reported against its key.
private enum JSONValue: Decodable {
    case bool(Bool)
    case number(Double)
    case string(String)
    case other

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else {
            self = .other
        }
    }
}

/// A key of the settings file that was not used, and why.
public struct IgnoredSetting: Equatable, Sendable {
    /// What the whole file is called when none of it can be used.
    static let wholeFile = "the whole file"

    public var key: String
    public var reason: String

    public init(key: String, reason: String) {
        self.key = key
        self.reason = reason
    }
}

/// What a settings file gave: the settings, with the default for every key
/// that is missing or was ignored, and what was ignored.
public struct SettingsRead: Equatable, Sendable {
    public var settings: Settings
    public var ignored: [IgnoredSetting]

    public init(settings: Settings, ignored: [IgnoredSetting]) {
        self.settings = settings
        self.ignored = ignored
    }

    /// The line for standard error, nil when nothing was ignored.
    public var note: String? {
        guard !ignored.isEmpty else { return nil }
        let named = ignored.map { "\($0.key) (\($0.reason))" }.joined(separator: ", ")
        return "Settings file: ignored \(named); using defaults for those."
    }
}

extension Settings {
    /// Reads a settings file's content, never refusing it: a missing key
    /// keeps its default, an unknown key or an invalid value is ignored and
    /// reported, and content that is no JSON object gives the defaults.
    public static func read(json data: Data) -> SettingsRead {
        let object: [String: JSONValue]
        do {
            object = try JSONDecoder().decode([String: JSONValue].self, from: data)
        } catch {
            let isFragment = (try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])) != nil
            return SettingsRead(
                settings: .defaults,
                ignored: [IgnoredSetting(key: IgnoredSetting.wholeFile,
                                         reason: isFragment ? "not a JSON object" : "not valid JSON")])
        }
        var settings = Settings.defaults
        var ignored: [IgnoredSetting] = []
        for (name, value) in object.sorted(by: { $0.key < $1.key }) {
            guard let key = SettingKey(rawValue: name) else {
                ignored.append(IgnoredSetting(key: name, reason: "unknown key"))
                continue
            }
            if let expected = settings.set(key, fromJSON: value) {
                ignored.append(IgnoredSetting(key: name, reason: "invalid value, expected \(expected)"))
            }
        }
        return SettingsRead(settings: settings, ignored: ignored)
    }

    /// Sets the key from its JSON value; what is expected instead when the value is invalid.
    private mutating func set(_ key: SettingKey, fromJSON value: JSONValue) -> String? {
        switch (key, value) {
        case (.auto, .bool(let flag)): auto = flag
        case (.auto, _): return Expected.jsonSwitch
        case (.resolution, .string(let text)):
            guard let parsed = RecordingResolution(rawValue: text) else { return Expected.resolution }
            resolution = parsed
        case (.resolution, _): return Expected.resolution
        case (.audioMode, .string(let text)):
            guard let parsed = AudioMode(rawValue: text) else { return Expected.audioMode }
            audioMode = parsed
        case (.audioMode, _): return Expected.audioMode
        case (.systemAudio, .bool(let flag)): systemAudio = flag
        case (.systemAudio, _): return Expected.jsonSwitch
        case (.outputFolder, .string(let text)):
            guard let parsed = validFolder(text) else { return Expected.folder }
            outputFolder = parsed
        case (.outputFolder, _): return Expected.folder
        case (.requiredRecordingHours, .number(let number)):
            guard let parsed = validPositive(number) else { return Expected.positiveNumber }
            requiredRecordingHours = parsed
        case (.requiredRecordingHours, _): return Expected.positiveNumber
        case (.lowDiskWarningMinutes, .number(let number)):
            guard let parsed = validPositive(number) else { return Expected.positiveNumber }
            lowDiskWarningMinutes = parsed
        case (.lowDiskWarningMinutes, _): return Expected.positiveNumber
        }
        return nil
    }

    /// The settings file's content, whole, in its current form.
    public func jsonData() throws -> Data {
        try prettyJSON(self)
    }

    /// The settings with command-line flag values applied, keyed by setting;
    /// `auto` is the plain flag `--auto`. A choice flag (`--resolution`,
    /// `--audio-mode`) turns auto mode off for the run; `--auto` turns it on
    /// and cannot be combined with a choice flag.
    public func applying(flags: [SettingKey: String], auto forceAuto: Bool = false) throws(SettingsError) -> Settings {
        if forceAuto, let choice = [SettingKey.resolution, .audioMode].first(where: { flags[$0] != nil }) {
            throw .conflictingFlags(flag: choice.flagName)
        }
        var settings = self
        if forceAuto { settings.auto = true }
        for key in SettingKey.allCases {
            guard let text = flags[key] else { continue }
            func invalid(_ expected: String) -> SettingsError {
                .invalidFlagValue(flag: key.flagName, value: text, expected: expected)
            }
            switch key {
            case .auto:
                break
            case .resolution:
                guard let parsed = RecordingResolution(rawValue: text) else { throw invalid(Expected.resolution) }
                settings.resolution = parsed
                settings.auto = false
            case .audioMode:
                guard let parsed = AudioMode(rawValue: text) else { throw invalid(Expected.audioMode) }
                settings.audioMode = parsed
                settings.auto = false
            case .systemAudio:
                switch text {
                case "on": settings.systemAudio = true
                case "off": settings.systemAudio = false
                default: throw invalid(Expected.flagSwitch)
                }
            case .outputFolder:
                guard let parsed = validFolder(text) else { throw invalid(Expected.folder) }
                settings.outputFolder = parsed
            case .requiredRecordingHours:
                guard let parsed = Double(text).flatMap(validPositive) else { throw invalid(Expected.positiveNumber) }
                settings.requiredRecordingHours = parsed
            case .lowDiskWarningMinutes:
                guard let parsed = Double(text).flatMap(validPositive) else { throw invalid(Expected.positiveNumber) }
                settings.lowDiskWarningMinutes = parsed
            }
        }
        return settings
    }
}

// MARK: - The file

public struct SettingsFileError: Error, Sendable, CustomStringConvertible {
    public let fileURL: URL
    public let reason: String

    public var description: String { "Settings file \(fileURL.path(percentEncoded: false)) cannot be written (\(reason))" }
}

/// The settings file: only read, never refused, and written only when a
/// person saves.
public struct SettingsFile: Sendable {
    public let url: URL

    public init(url: URL) {
        self.url = url
    }

    public static func standard(homeFolder: URL) -> SettingsFile {
        SettingsFile(url: homeFolder.appending(
            path: "Library/Application Support/Multi Screen Recorder/settings.json"))
    }

    /// What the file gives; the defaults for a missing file, which is not
    /// written, and for one that cannot be read.
    public func load() -> SettingsRead {
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else {
            return SettingsRead(settings: .defaults, ignored: [])
        }
        let data: Data
        do { data = try Data(contentsOf: url) } catch {
            return SettingsRead(
                settings: .defaults,
                ignored: [IgnoredSetting(key: IgnoredSetting.wholeFile,
                                         reason: "cannot be read: \(error.localizedDescription)")])
        }
        return Settings.read(json: data)
    }

    public func save(_ settings: Settings) throws(SettingsFileError) {
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try settings.jsonData().write(to: url, options: .atomic)
        } catch {
            throw SettingsFileError(fileURL: url, reason: error.localizedDescription)
        }
    }
}
