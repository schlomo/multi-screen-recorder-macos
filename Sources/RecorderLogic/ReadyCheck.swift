import Foundation

/// The outcome of asking for a permission and proving the grant.
public enum PermissionProbe: Equatable, Sendable {
    case granted
    case notGranted
    /// Granted, but the proof failed, for the given reason.
    case failed(String)
}

public enum FreeSpace: Equatable, Sendable {
    case bytes(Int64)
    case unreadable(String)
}

/// Whether a file can be written into the output folder, and if so the
/// free space there.
public enum OutputFolderProbe: Equatable, Sendable {
    case usable(FreeSpace)
    case unusable(String)
}

/// What the probes found on this Mac, for the ready check to judge.
public struct ReadyCheckFacts: Sendable {
    public var screenRecording: PermissionProbe
    /// Nil when the audio mode needs no microphone, so it was not probed.
    public var microphone: PermissionProbe?
    public var displays: Result<[DisplayInfo], DeviceReadError>
    public var audioInputs: [AudioInputInfo]
    public var outputFolder: OutputFolderProbe

    public init(
        screenRecording: PermissionProbe,
        microphone: PermissionProbe?,
        displays: Result<[DisplayInfo], DeviceReadError>,
        audioInputs: [AudioInputInfo],
        outputFolder: OutputFolderProbe
    ) {
        self.screenRecording = screenRecording
        self.microphone = microphone
        self.displays = displays
        self.audioInputs = audioInputs
        self.outputFolder = outputFolder
    }
}

public struct ReadyCheckItem: Equatable, Sendable {
    public var title: String
    public var passed: Bool
    public var fix: String?

    public init(title: String, passed: Bool, fix: String?) {
        self.title = title
        self.passed = passed
        self.fix = fix
    }
}

public struct ReadyCheckResult: Equatable, Sendable {
    public var items: [ReadyCheckItem]

    public var isReady: Bool { items.allSatisfy(\.passed) }

    /// The text `msr check` prints.
    public var text: String {
        var lines: [String] = []
        for item in items {
            lines.append((item.passed ? "ok    " : "FAIL  ") + item.title)
            if !item.passed, let fix = item.fix {
                lines.append("      Fix: \(fix)")
            }
        }
        lines.append(isReady ? "Ready." : "Not ready.")
        return lines.joined(separator: "\n") + "\n"
    }
}

public enum ReadyCheck {
    static let screenRecordingTitle = "Screen & System Audio Recording permission"
    static let microphoneTitle = "Microphone permission"
    static let terminalNote = "; started from a terminal, the terminal app needs it"

    /// One item per cause: a free disk space item appears only when the
    /// displays and the audio inputs a recording records could be read and
    /// the output folder is usable.
    public static func evaluate(_ facts: ReadyCheckFacts, settings: Settings) -> ReadyCheckResult {
        var items = [screenRecordingItem(facts.screenRecording)]
        if settings.audioMode != .none {
            items.append(microphoneItem(facts.microphone ?? .notGranted))
        }
        items.append(displaysItem(facts.displays))
        items.append(audioItem(facts.audioInputs, settings: settings))
        items.append(outputFolderItem(facts.outputFolder, settings: settings))
        if case .success(let displays) = facts.displays, case .usable(let freeSpace) = facts.outputFolder,
           let bytesPerHour = DiskEstimate.bytesPerHour(settings: settings, displays: displays, audioInputs: facts.audioInputs) {
            items.append(diskItem(freeSpace, bytesPerHour: bytesPerHour, settings: settings))
        }
        return ReadyCheckResult(items: items)
    }

    private static func screenRecordingItem(_ probe: PermissionProbe) -> ReadyCheckItem {
        let fix = "allow it in System Settings › Privacy & Security › Screen & System Audio Recording,"
            + " then start again" + terminalNote
        return switch probe {
        case .granted: ReadyCheckItem(title: screenRecordingTitle, passed: true, fix: nil)
        case .notGranted: ReadyCheckItem(title: screenRecordingTitle, passed: false, fix: fix)
        case .failed(let reason):
            ReadyCheckItem(title: "\(screenRecordingTitle): the display list could not be read (\(reason))",
                           passed: false, fix: fix)
        }
    }

    private static func microphoneItem(_ probe: PermissionProbe) -> ReadyCheckItem {
        switch probe {
        case .granted:
            ReadyCheckItem(title: microphoneTitle, passed: true, fix: nil)
        case .notGranted:
            ReadyCheckItem(title: microphoneTitle, passed: false,
                           fix: "allow it in System Settings › Privacy & Security › Microphone" + terminalNote)
        case .failed(let reason):
            ReadyCheckItem(title: "\(microphoneTitle): the default microphone could not be opened (\(reason))",
                           passed: false, fix: "check the input in System Settings › Sound")
        }
    }

    private static func displaysItem(_ displays: Result<[DisplayInfo], DeviceReadError>) -> ReadyCheckItem {
        switch displays {
        case .success(let displays):
            ReadyCheckItem(title: "Displays: \(displays.count)", passed: !displays.isEmpty, fix: "connect a display")
        case .failure(let error):
            ReadyCheckItem(title: "Displays: cannot be read (\(error))", passed: false,
                           fix: "reconnect the displays, then check again")
        }
    }

    private static func audioItem(_ audioInputs: [AudioInputInfo], settings: Settings) -> ReadyCheckItem {
        if case .failure(let error) = unreadableRecordedInputs(audioInputs, settings: settings).first?.channelCount {
            return ReadyCheckItem(title: "Audio: cannot be read (\(error))", passed: false,
                                  fix: "reconnect the audio inputs, then check again")
        }
        var sources: [String] = []
        var missingMicrophone = false
        if settings.audioMode == .defaultMicrophone {
            if let defaultMicrophone = audioInputs.first(where: settings.records) {
                sources.append(defaultMicrophone.label)
            } else {
                sources.append("no microphone")
                missingMicrophone = true
            }
        }
        if settings.systemAudio { sources.append("system audio") }
        return ReadyCheckItem(
            title: "Audio: " + (sources.isEmpty ? "none" : sources.joined(separator: ", ")),
            passed: !missingMicrophone,
            fix: missingMicrophone ? "connect a microphone, or set the audio mode to none (--audio-mode none)" : nil)
    }

    private static func outputFolderItem(_ probe: OutputFolderProbe, settings: Settings) -> ReadyCheckItem {
        let folder = settings.outputFolder
        return switch probe {
        case .usable:
            ReadyCheckItem(title: "Output folder: \(folder)", passed: true, fix: nil)
        case .unusable(let reason):
            ReadyCheckItem(title: "Output folder: \(folder) cannot be used (\(reason))", passed: false,
                           fix: "choose another output folder (--output-folder)")
        }
    }

    private static func diskItem(_ freeSpace: FreeSpace, bytesPerHour: Double, settings: Settings) -> ReadyCheckItem {
        let folder = settings.outputFolder
        switch freeSpace {
        case .unreadable(let reason):
            return ReadyCheckItem(
                title: "Free disk space: unknown in \(folder) (\(reason))",
                passed: false,
                fix: "choose an output folder on another disk (--output-folder)")
        case .bytes(let free):
            let needed = bytesPerHour * settings.requiredRecordingHours
            return ReadyCheckItem(
                title: "Free disk space: \(DiskEstimate.gigabytes(Double(free))) in \(folder),"
                    + " \(DiskEstimate.gigabytes(needed)) needed for \(hoursText(settings.requiredRecordingHours))",
                passed: Double(free) >= needed,
                fix: "free up space, or lower --required-recording-hours")
        }
    }

    static func hoursText(_ hours: Double) -> String {
        let number = hours == hours.rounded() ? String(Int(hours)) : String(hours)
        return hours == 1 ? "1 hour" : "\(number) hours"
    }
}
