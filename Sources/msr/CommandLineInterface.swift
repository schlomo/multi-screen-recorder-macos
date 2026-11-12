import ArgumentParser
import Foundation
import RecorderCore
import RecorderLogic

struct CommandLineInterface: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "msr",
        abstract: "Multi Screen Recorder: records every display and audio source.",
        discussion: "Without arguments, msr starts the app.",
        subcommands: [List.self, Check.self, SettingsCommand.self, Version.self]
    )
}

/// One flag per settings key, overriding it for this run only.
struct SettingsFlags: ParsableArguments {
    @Option(help: "Recording resolution: native, 4k, 1440p, 1200p, 1080p or 720p.")
    var resolution: String?

    @Option(help: "Audio mode: none or default-microphone.")
    var audioMode: String?

    @Option(help: "System audio: on or off.")
    var systemAudio: String?

    @Option(help: "Output folder: a path starting with / or ~.")
    var outputFolder: String?

    @Option(help: "Hours of recording the free disk space must hold.")
    var requiredRecordingHours: String?

    @Option(help: "The low disk space warning threshold, in minutes.")
    var lowDiskWarningMinutes: String?

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
            _ = try Settings.defaults.applying(flags: values)
        } catch {
            throw ValidationError(error.description)
        }
    }

    /// The settings file with these flags applied.
    func effectiveSettings(from file: SettingsFile) throws -> Settings {
        try file.load().applying(flags: values)
    }
}

private func standardSettingsFile() throws -> SettingsFile {
    SettingsFile.standard(homeFolder: try homeFolder())
}

extension CommandLineInterface {
    struct List: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Show displays, audio inputs and system audio.")

        func run() async throws {
            let settings = try standardSettingsFile().load()
            let displays = await currentDisplays()
            print(renderList(
                displays: numberDisplays(displays),
                resolution: settings.resolution,
                audioInputs: currentAudioInputs(),
                systemAudioAvailable: screenRecordingIsGranted()
            ), terminator: "")
        }
    }

    struct Check: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Run the ready check and print each item.",
            discussion: "Exits 0 when ready, 1 when not.")

        @OptionGroup var flags: SettingsFlags

        func run() async throws {
            let settings = try flags.effectiveSettings(from: standardSettingsFile())
            let result = await runReadyCheck(settings: settings, homeFolder: try homeFolder())
            print(result.text, terminator: "")
            if !result.isReady { throw ExitCode(1) }
        }
    }

    struct SettingsCommand: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "settings",
            abstract: "Print the effective settings as JSON.")

        @OptionGroup var flags: SettingsFlags

        @Flag(help: "Write the flags into the settings file.")
        var save = false

        func run() async throws {
            let file = try standardSettingsFile()
            let settings = try flags.effectiveSettings(from: file)
            if save { try file.save(settings) }
            print(settings.json, terminator: "")
        }
    }

    struct Version: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Print the version and commit.")

        func run() async throws {
            print(runningVersion)
        }
    }
}
