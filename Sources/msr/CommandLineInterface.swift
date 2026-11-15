import ArgumentParser
import Foundation
import RecorderCore
import RecorderLogic

struct CommandLineInterface: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "msr",
        abstract: "Multi Screen Recorder: records every display and audio source.",
        discussion: """
            Without arguments, msr starts the app. A settings flag changes the settings for that one run; only `msr settings` saves them. \
            An unset HOME makes every command that reads the settings exit 78.
            """,
        subcommands: [List.self, Check.self, Record.self, SettingsCommand.self, Version.self]
    )
}

/// One flag per settings key, changing it for this run; `msr settings` saves the result.
struct SettingsFlags: ParsableArguments {
    @Flag(help: "Auto mode for this run, whatever the settings file says: every display at Native, the audio mode Wired. Not with --resolution or --audio-mode.")
    var auto = false

    @Option(help: "Recording resolution: native, 4k, 1440p, 1200p, 1080p or 720p. Turns auto mode off for this run.")
    var resolution: String?

    @Option(help: "Audio mode: none, default-microphone, wired or all-inputs. Turns auto mode off for this run.")
    var audioMode: String?

    @Option(help: "System audio: on or off.")
    var systemAudio: String?

    @Option(help: "Output folder: a path starting with / or ~.")
    var outputFolder: String?

    @Option(help: "Hours of recording the free disk space must hold.")
    var requiredRecordingHours: String?

    @Option(help: "The low disk space warning threshold, in minutes.")
    var lowDiskWarningMinutes: String?

    /// Whether any settings flag, `--auto` included, is given.
    var isGiven: Bool { auto || !values.isEmpty }

    var values: [SettingKey: String] {
        let pairs: [(SettingKey, String?)] = [
            (.resolution, resolution),
            (.audioMode, audioMode),
            (.systemAudio, systemAudio),
            (.outputFolder, outputFolder),
            (.requiredRecordingHours, requiredRecordingHours),
            (.lowDiskWarningMinutes, lowDiskWarningMinutes),
        ]
        return Dictionary(uniqueKeysWithValues: pairs.compactMap { key, value in value.map { (key, $0) } })
    }

    func validate() throws {
        do {
            _ = try Settings.defaults.applying(flags: values, auto: auto)
        } catch {
            throw ValidationError(error.description)
        }
    }

    /// The settings file with these flags applied; what the file had ignored goes to standard error.
    func effectiveSettings(from file: SettingsFile) throws -> Settings {
        try loadSettings(from: file).applying(flags: values, auto: auto)
    }
}

/// EX_CONFIG from sysexits: an unset HOME, so the settings file cannot be
/// found. Exit 1 stays "not ready" for `msr check`.
let unsetHomeExitCode = ExitCode(78)

/// The home folder from `HOME`; unset, it prints its error and exits 78.
func homeFolderOrExit() throws -> URL {
    do {
        return try homeFolder()
    } catch let error as MissingHomeFolderError {
        FileHandle.standardError.write(Data("Error: \(error)\n".utf8))
        throw unsetHomeExitCode
    }
}

/// What the settings file gives, never refused; what it ignored is named on standard error.
func loadSettings(from file: SettingsFile) -> Settings {
    let read = file.load()
    if let note = read.note { FileHandle.standardError.write(Data("\(note)\n".utf8)) }
    return read.settings
}

func standardSettingsFile() throws -> SettingsFile {
    SettingsFile.standard(homeFolder: try homeFolderOrExit())
}

extension CommandLineInterface {
    struct List: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Show displays, audio inputs and system audio.")

        func run() async throws {
            let file = try standardSettingsFile()
            let settings = loadSettings(from: file)
            let displays = try await currentDisplays()
            let audioInputs = try currentAudioInputs()
            print(renderList(
                displays: numberDisplays(displays),
                resolution: settings.effectiveResolution,
                audioInputs: audioInputs,
                systemAudioAvailable: screenRecordingIsGranted()
            ), terminator: "")
            if !unreadableRecordedInputs(audioInputs, settings: settings).isEmpty { throw ExitCode(1) }
        }
    }

    struct Check: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Run the ready check and print each item.",
            discussion: "Prints what will be recorded, then the ready check. Exits 0 when ready, 1 when not, 78 when HOME is unset.")

        @OptionGroup var flags: SettingsFlags

        @Flag(help: "Detail on standard error and at debug level in the unified log.")
        var debug = false

        func run() async throws {
            if debug { RecorderLog.enableDebug() }
            let settings = try flags.effectiveSettings(from: standardSettingsFile())
            let home = try homeFolderOrExit()
            for line in CrashMarkers(homeFolder: home).finishLeftBehind() { standardError(line) }
            let facts = await probeReadyCheckFacts(proof: .captureOneFrame, settings: settings, homeFolder: home)
            let result = ReadyCheck.evaluate(facts, settings: settings)
            print(WhatWillBeRecorded(settings: settings, facts: facts).text, terminator: "\n")
            print(result.text, terminator: "")
            if !result.isReady { throw ExitCode(1) }
        }
    }

    struct SettingsCommand: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "settings",
            abstract: "Show the effective settings as JSON, or change them.",
            discussion: "Without flags it prints the settings. With any settings flag it saves the run's effective settings "
                + "into the settings file and prints them; the only command that writes the file.")

        @OptionGroup var flags: SettingsFlags

        func run() async throws {
            let file = try standardSettingsFile()
            let settings = try flags.effectiveSettings(from: file)
            if flags.isGiven { try file.save(settings) }
            print(String(decoding: try settings.jsonData(), as: UTF8.self), terminator: "")
        }
    }

    struct Version: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Print the version and commit.")

        func run() async throws {
            print(runningVersion)
        }
    }
}
