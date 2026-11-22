import ArgumentParser
import Foundation
import RecorderCore
import RecorderLogic

struct CommandLineInterface: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "msr",
        abstract: "Multi Screen Recorder: records every screen, camera and audio source.",
        discussion: """
            Without arguments, msr starts the app. A settings flag changes the settings for that one run; only `msr settings` saves them. \
            An unset HOME makes every command that reads the settings exit 78.
            """,
        subcommands: [List.self, Check.self, Record.self, SettingsCommand.self, Timeline.self, Version.self]
    )
}

/// One flag per settings key, changing it for this run; `msr settings` saves the result.
struct SettingsFlags: ParsableArguments {
    @Flag(help: "Auto mode for this run, whatever the settings file says: every screen at Native, the audio mode Wired, the camera mode real. Not with --resolution, --audio-mode or --camera-mode.")
    var auto = false

    @Option(help: "Recording resolution: native, 4k, 1440p, 1200p, 1080p, 720p or none (audio only: no screen and no camera is recorded). Turns auto mode off for this run.")
    var resolution: String?

    @Option(help: "Audio mode: none, default-microphone, wired or all-inputs. Turns auto mode off for this run.")
    var audioMode: String?

    @Option(help: "Camera mode: none, default-camera, real or all-cameras (virtual cameras too). Turns auto mode off for this run.")
    var cameraMode: String?

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
            (.cameraMode, cameraMode),
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
        StandardErrorWriter.shared.write("Error: \(ErrorDetail(error).text)\n")
        throw unsetHomeExitCode
    }
}

/// What the settings file gives, never refused; what it ignored is named on standard error.
func loadSettings(from file: SettingsFile) -> Settings {
    let read = file.load()
    if let note = read.note { StandardErrorWriter.shared.write("\(note)\n") }
    return read.settings
}

func standardSettingsFile() throws -> SettingsFile {
    SettingsFile.standard(homeFolder: try homeFolderOrExit())
}

extension CommandLineInterface {
    struct List: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Show what will be recorded: the settings, the screens, the cameras, the audio inputs and the system audio. Asks for no permission.")

        func run() async throws {
            let file = try standardSettingsFile()
            let settings = loadSettings(from: file)
            let screens = try await currentScreens()
            let audioInputs = try currentAudioInputs()
            print(renderList(
                settings: settings,
                screens: screens,
                audioInputs: audioInputs,
                cameras: currentCameras(),
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

        @Flag(help: "Also prints the detail lines on standard error, and writes them at debug level in the unified log.")
        var debug = false

        func run() async throws {
            if debug { RecorderLog.enableDebug() }
            let settings = try flags.effectiveSettings(from: standardSettingsFile())
            let home = try homeFolderOrExit()
            let facts = await probeReadyCheckFacts(proof: .captureOneFrame, settings: settings, homeFolder: home)
            let result = ReadyCheck.evaluate(facts, settings: settings)
            print(runningVersion.banner, terminator: "")
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

    struct Timeline: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Write a recording folder's DaVinci Resolve timeline file.",
            discussion: "Reads the folder's recording.json and writes the timeline file next to it, replacing an older one; "
                + "writes and deletes nothing else. Prints the file's path. Exits 1 with the error on standard error when "
                + "recording.json cannot be read, a file's length cannot be read or the file cannot be written.")

        @Argument(help: "The recording folder.", completion: .directory)
        var folder: String

        func run() async throws {
            do {
                let file = try await TimelineFile.write(in: URL(filePath: folder, directoryHint: .isDirectory).standardizedFileURL)
                print(file.path(percentEncoded: false))
            } catch {
                StandardErrorWriter.shared.write("Error: \(ErrorDetail(error).text)\n")
                throw ExitCode(1)
            }
        }
    }

    struct Version: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Print the version and commit.")

        func run() async throws {
            print(runningVersion)
        }
    }
}
