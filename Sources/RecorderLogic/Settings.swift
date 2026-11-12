import Foundation

/// Which audio inputs are recorded.
public enum AudioMode: String, CaseIterable, Sendable {
    case none
    case defaultMicrophone = "default-microphone"
}

/// A key of the settings file; each has a flag of the same name in kebab case.
public enum SettingKey: String, CaseIterable, Sendable {
    case resolution
    case audioMode
    case systemAudio
    case outputFolder
    case readyCheckHours
    case lowDiskWarningMinutes

    public var flagName: String {
        "--" + rawValue.replacing(/[A-Z]/) { "-" + $0.output.lowercased() }
    }
}

public struct Settings: Equatable, Sendable {
    public var resolution: RecordingResolution
    public var audioMode: AudioMode
    public var systemAudio: Bool
    /// As written in the settings file, possibly starting with `~`.
    public var outputFolder: String
    public var readyCheckHours: Double
    public var lowDiskWarningMinutes: Double

    public init(
        resolution: RecordingResolution,
        audioMode: AudioMode,
        systemAudio: Bool,
        outputFolder: String,
        readyCheckHours: Double,
        lowDiskWarningMinutes: Double
    ) {
        self.resolution = resolution
        self.audioMode = audioMode
        self.systemAudio = systemAudio
        self.outputFolder = outputFolder
        self.readyCheckHours = readyCheckHours
        self.lowDiskWarningMinutes = lowDiskWarningMinutes
    }

    public static let defaults = Settings(
        resolution: .p1080,
        audioMode: .defaultMicrophone,
        systemAudio: true,
        outputFolder: "~/Movies/Multi Screen Recorder",
        readyCheckHours: 2,
        lowDiskWarningMinutes: 20
    )

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

public enum SettingsError: Error, Equatable, Sendable, CustomStringConvertible {
    case notJSON(String)
    case notAnObject
    case unknownKey(String)
    case invalidValue(key: String, expected: String)
    case invalidFlagValue(flag: String, value: String, expected: String)
    case unreadable(String)
    case unwritable(String)

    public var description: String {
        switch self {
        case .notJSON(let reason): "not valid JSON (\(reason))"
        case .notAnObject: "not a JSON object"
        case .unknownKey(let key): "unknown key \"\(key)\""
        case .invalidValue(let key, let expected): "invalid value for \"\(key)\", expected \(expected)"
        case .invalidFlagValue(let flag, let value, let expected):
            "invalid value \"\(value)\" for \(flag), expected \(expected)"
        case .unreadable(let reason): "cannot be read (\(reason))"
        case .unwritable(let reason): "cannot be written (\(reason))"
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

extension Settings {
    /// Reads a settings file's content. A missing key keeps its default, so a
    /// file written before a key existed stays valid.
    public init(json data: Data) throws(SettingsError) {
        let object: [String: JSONValue]
        do {
            object = try JSONDecoder().decode([String: JSONValue].self, from: data)
        } catch {
            if (try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])) != nil {
                throw .notAnObject
            }
            throw .notJSON(String(describing: error))
        }
        var settings = Settings.defaults
        for (name, value) in object.sorted(by: { $0.key < $1.key }) {
            guard let key = SettingKey(rawValue: name) else { throw .unknownKey(name) }
            try settings.set(key, fromJSON: value)
        }
        self = settings
    }

    private mutating func set(_ key: SettingKey, fromJSON value: JSONValue) throws(SettingsError) {
        func invalid(_ expected: String) -> SettingsError { .invalidValue(key: key.rawValue, expected: expected) }
        switch (key, value) {
        case (.resolution, .string(let text)):
            guard let parsed = RecordingResolution(rawValue: text) else { throw invalid(Expected.resolution) }
            resolution = parsed
        case (.resolution, _): throw invalid(Expected.resolution)
        case (.audioMode, .string(let text)):
            guard let parsed = AudioMode(rawValue: text) else { throw invalid(Expected.audioMode) }
            audioMode = parsed
        case (.audioMode, _): throw invalid(Expected.audioMode)
        case (.systemAudio, .bool(let flag)): systemAudio = flag
        case (.systemAudio, _): throw invalid(Expected.jsonSwitch)
        case (.outputFolder, .string(let text)):
            guard let parsed = validFolder(text) else { throw invalid(Expected.folder) }
            outputFolder = parsed
        case (.outputFolder, _): throw invalid(Expected.folder)
        case (.readyCheckHours, .number(let number)):
            guard let parsed = validPositive(number) else { throw invalid(Expected.positiveNumber) }
            readyCheckHours = parsed
        case (.readyCheckHours, _): throw invalid(Expected.positiveNumber)
        case (.lowDiskWarningMinutes, .number(let number)):
            guard let parsed = validPositive(number) else { throw invalid(Expected.positiveNumber) }
            lowDiskWarningMinutes = parsed
        case (.lowDiskWarningMinutes, _): throw invalid(Expected.positiveNumber)
        }
    }

    /// The settings file's content: keys in a fixed order, two-space indent.
    public var json: String {
        let lines = [
            (SettingKey.resolution, jsonString(resolution.rawValue)),
            (.audioMode, jsonString(audioMode.rawValue)),
            (.systemAudio, systemAudio ? "true" : "false"),
            (.outputFolder, jsonString(outputFolder)),
            (.readyCheckHours, jsonNumber(readyCheckHours)),
            (.lowDiskWarningMinutes, jsonNumber(lowDiskWarningMinutes)),
        ].map { "  \(jsonString($0.0.rawValue)): \($0.1)" }
        return "{\n" + lines.joined(separator: ",\n") + "\n}\n"
    }

    /// The settings with command-line flag values applied, keyed by setting.
    public func applying(flags: [SettingKey: String]) throws(SettingsError) -> Settings {
        var settings = self
        for key in SettingKey.allCases {
            guard let text = flags[key] else { continue }
            func invalid(_ expected: String) -> SettingsError {
                .invalidFlagValue(flag: key.flagName, value: text, expected: expected)
            }
            switch key {
            case .resolution:
                guard let parsed = RecordingResolution(rawValue: text) else { throw invalid(Expected.resolution) }
                settings.resolution = parsed
            case .audioMode:
                guard let parsed = AudioMode(rawValue: text) else { throw invalid(Expected.audioMode) }
                settings.audioMode = parsed
            case .systemAudio:
                switch text {
                case "on": settings.systemAudio = true
                case "off": settings.systemAudio = false
                default: throw invalid(Expected.flagSwitch)
                }
            case .outputFolder:
                guard let parsed = validFolder(text) else { throw invalid(Expected.folder) }
                settings.outputFolder = parsed
            case .readyCheckHours:
                guard let parsed = Double(text).flatMap(validPositive) else { throw invalid(Expected.positiveNumber) }
                settings.readyCheckHours = parsed
            case .lowDiskWarningMinutes:
                guard let parsed = Double(text).flatMap(validPositive) else { throw invalid(Expected.positiveNumber) }
                settings.lowDiskWarningMinutes = parsed
            }
        }
        return settings
    }
}

private func jsonString(_ text: String) -> String {
    var escaped = "\""
    for scalar in text.unicodeScalars {
        switch scalar {
        case "\"": escaped += "\\\""
        case "\\": escaped += "\\\\"
        case "\n": escaped += "\\n"
        case "\r": escaped += "\\r"
        case "\t": escaped += "\\t"
        case _ where scalar.value < 0x20: escaped += String(format: "\\u%04x", scalar.value)
        default: escaped.unicodeScalars.append(scalar)
        }
    }
    return escaped + "\""
}

private func jsonNumber(_ number: Double) -> String {
    if number == number.rounded(), abs(number) < 1e15 { return String(Int(number)) }
    return String(number)
}

// MARK: - The file

public struct SettingsFileError: Error, Sendable, CustomStringConvertible {
    public let fileURL: URL
    public let problem: SettingsError

    public var description: String { "Settings file \(fileURL.path(percentEncoded: false)): \(problem)" }
}

/// The settings file, written with the defaults on first load.
public struct SettingsFile: Sendable {
    public let url: URL

    public init(url: URL) {
        self.url = url
    }

    public static func standard(homeFolder: URL) -> SettingsFile {
        SettingsFile(url: homeFolder.appending(
            path: "Library/Application Support/Multi Screen Recorder/settings.json"))
    }

    public func load() throws(SettingsFileError) -> Settings {
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else {
            try save(.defaults)
            return .defaults
        }
        do throws(SettingsError) {
            let data: Data
            do { data = try Data(contentsOf: url) } catch { throw SettingsError.unreadable(error.localizedDescription) }
            return try Settings(json: data)
        } catch {
            throw SettingsFileError(fileURL: url, problem: error)
        }
    }

    public func save(_ settings: Settings) throws(SettingsFileError) {
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(settings.json.utf8).write(to: url, options: .atomic)
        } catch {
            throw SettingsFileError(fileURL: url, problem: .unwritable(error.localizedDescription))
        }
    }
}
