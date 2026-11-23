import Foundation

/// The outcome of asking for a permission and proving the grant.
public enum PermissionProbe: Equatable, Sendable {
    case granted
    case notGranted
    /// Granted, but the proof failed, for the given reason: the error detail's text.
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
    /// Nil when the recording records neither a screen nor the system
    /// audio, so it was not asked (`ReadyCheck.needsScreenRecording`).
    public var screenRecording: PermissionProbe?
    /// Whether the Microphone permission is granted; nil when the recording
    /// records no audio input, so it was not asked.
    public var microphoneGranted: Bool?
    public var screens: Result<[ScreenInfo], DeviceReadError>
    public var audioInputs: Result<[AudioInputInfo], DeviceReadError>
    public var outputFolder: OutputFolderProbe
    /// Whether the Camera permission is granted; nil when the recording
    /// records no connected camera, so it was not asked (D74).
    public var cameraGranted: Bool?
    public var cameras: [CameraInfo]

    public init(
        screenRecording: PermissionProbe?,
        microphoneGranted: Bool?,
        screens: Result<[ScreenInfo], DeviceReadError>,
        audioInputs: Result<[AudioInputInfo], DeviceReadError>,
        outputFolder: OutputFolderProbe,
        cameraGranted: Bool? = nil,
        cameras: [CameraInfo] = []
    ) {
        self.screenRecording = screenRecording
        self.microphoneGranted = microphoneGranted
        self.screens = screens
        self.audioInputs = audioInputs
        self.outputFolder = outputFolder
        self.cameraGranted = cameraGranted
        self.cameras = cameras
    }
}

extension ReadyCheckFacts {
    /// The cameras a recording may record: none when the Camera permission is denied, as macOS grants it per app.
    var camerasRecordable: [CameraInfo] { cameraGranted == false ? [] : cameras }
}

public struct ReadyCheckItem: Equatable, Sendable {
    public var title: String
    public var passed: Bool
    public var fix: String?
    /// The fix is shown though the item passed: a denied Camera permission, which records no camera (D74).
    public var showsFixWhenPassed: Bool

    public init(title: String, passed: Bool, fix: String?, showsFixWhenPassed: Bool = false) {
        self.title = title
        self.passed = passed
        self.fix = fix
        self.showsFixWhenPassed = showsFixWhenPassed
    }

    /// The fix to show under the item: a failing item's, or one shown though it passed.
    public var shownFix: String? { !passed || showsFixWhenPassed ? fix : nil }
}

public struct ReadyCheckResult: Equatable, Sendable {
    public var items: [ReadyCheckItem]

    public var isReady: Bool { items.allSatisfy(\.passed) }

    private static let fixLabel = "      Fix: "
    private static let lineWidth = 80

    /// The text `msr check` prints; a long fix wraps at 80 columns under its first line's text.
    public var text: String {
        var lines: [String] = []
        for item in items {
            lines.append((item.passed ? "ok    " : "FAIL  ") + item.title)
            if let fix = item.shownFix {
                let wrapped = wrappedLines(fix, width: Self.lineWidth - Self.fixLabel.count)
                lines.append(Self.fixLabel + (wrapped.first ?? ""))
                lines += wrapped.dropFirst().map { String(repeating: " ", count: Self.fixLabel.count) + $0 }
            }
        }
        lines.append(isReady ? "Ready." : "Not ready.")
        return lines.joined(separator: "\n") + "\n"
    }
}

public enum ReadyCheck {
    static let screenRecordingTitle = "Screen & System Audio Recording permission"
    static let microphoneTitle = "Microphone permission"
    static let cameraTitle = "Camera permission"
    static let restartNote = "quit Multi Screen Recorder and start it again. "
    static let terminalNote = "If it was started from a terminal, then the terminal app needs the permission."

    /// Whether a recording with these settings records at least one audio
    /// input that could be listed. Without one, such as on a Mac with no
    /// audio input, the Microphone permission is no part of the check.
    public static func recordsAudioInput(
        _ audioInputs: Result<[AudioInputInfo], DeviceReadError>, settings: Settings
    ) -> Bool {
        guard case .success(let inputs) = audioInputs else { return false }
        return inputs.contains { AudioTracker.records($0, settings: settings) }
    }

    /// Whether a recording with these settings records at least one of the
    /// cameras connected: only then the Camera permission is asked for and
    /// part of the check (D74).
    public static func recordsCamera(_ cameras: [CameraInfo], settings: Settings) -> Bool {
        cameras.contains { CameraTracker.records($0, settings: settings) }
    }

    /// Whether a recording with these settings needs the Screen & System
    /// Audio Recording permission: for the screens and for the system
    /// audio. Audio only with no system audio, the microphone alone, does not.
    public static func needsScreenRecording(_ settings: Settings) -> Bool {
        settings.effectiveResolution.recordsScreens || settings.systemAudio
    }

    /// The item of a recording that would record nothing: no screen at the
    /// recording resolution None, no system audio and no audio input.
    static let nothingToRecordItem = ReadyCheckItem(
        title: "Nothing to record: the recording resolution None records no screen, and no audio source is recorded",
        passed: false,
        fix: "choose another recording resolution (--resolution), turn on the system audio (--system-audio on) "
            + "or record a connected microphone (--audio-mode)")

    /// One item per cause: the screen permission and the screens only when
    /// they are needed (at the recording resolution None only for the system
    /// audio, which needs a main screen), a free disk space item only
    /// when the screens and the audio inputs a recording records could be
    /// read and the output folder is usable. A recording that would record
    /// nothing is not ready.
    public static func evaluate(_ facts: ReadyCheckFacts, settings: Settings) -> ReadyCheckResult {
        var items: [ReadyCheckItem] = []
        if needsScreenRecording(settings) {
            items.append(screenRecordingItem(facts.screenRecording ?? .notGranted))
        }
        if recordsAudioInput(facts.audioInputs, settings: settings) {
            items.append(microphoneItem(granted: facts.microphoneGranted ?? false))
        }
        if recordsCamera(facts.cameras, settings: settings) {
            items.append(cameraItem(granted: facts.cameraGranted ?? false))
        }
        let recordsScreens = settings.effectiveResolution.recordsScreens
        if recordsScreens {
            items.append(screensItem(facts.screens))
        } else if needsScreenRecording(settings) {
            items.append(systemAudioScreensItem(facts.screens))
        }
        items.append(audioItem(facts.audioInputs, settings: settings))
        if !recordsScreens, !settings.systemAudio,
           case .success(let inputs) = audioInputsToJudge(facts.audioInputs, settings: settings),
           !inputs.contains(where: { AudioTracker.records($0, settings: settings) }) {
            items.append(nothingToRecordItem)
        }
        items.append(outputFolderItem(facts.outputFolder, settings: settings))
        if case .success(let screens) = screensToJudge(facts.screens, settings: settings),
           case .usable(let freeSpace) = facts.outputFolder,
           case .success(let audioInputs) = audioInputsToJudge(facts.audioInputs, settings: settings),
           let bytesPerHour = DiskEstimate.bytesPerHour(
               settings: settings, screens: screens, audioInputs: audioInputs, cameras: facts.camerasRecordable) {
            items.append(diskItem(freeSpace, bytesPerHour: bytesPerHour, settings: settings))
        }
        return ReadyCheckResult(items: items)
    }

    private static func screenRecordingItem(_ probe: PermissionProbe) -> ReadyCheckItem {
        let fix = "allow it in System Settings › Privacy & Security › Screen & System Audio Recording. "
            + "If it is still missing after that, " + restartNote + terminalNote
        return switch probe {
        case .granted: ReadyCheckItem(title: screenRecordingTitle, passed: true, fix: nil)
        case .notGranted: ReadyCheckItem(title: screenRecordingTitle, passed: false, fix: fix)
        case .failed(let reason):
            ReadyCheckItem(title: "\(screenRecordingTitle): the screen list could not be read (\(reason))",
                           passed: false, fix: fix)
        }
    }

    private static func microphoneItem(granted: Bool) -> ReadyCheckItem {
        ReadyCheckItem(
            title: microphoneTitle, passed: granted,
            fix: granted ? nil : "allow it in System Settings › Privacy & Security › Microphone, then "
                + restartNote + terminalNote)
    }

    /// Denied, it passes: the recording records no camera, and the fix says how to change that (D74).
    private static func cameraItem(granted: Bool) -> ReadyCheckItem {
        ReadyCheckItem(
            title: granted ? cameraTitle : "\(cameraTitle) denied: no camera is recorded", passed: true,
            fix: granted ? nil : "allow it in System Settings › Privacy & Security › Camera, then " + restartNote + terminalNote
                + " Or record no camera: turn off Auto and move the Camera mode slider to None (--camera-mode none).",
            showsFixWhenPassed: !granted)
    }

    private static func screensItem(_ screens: Result<[ScreenInfo], DeviceReadError>) -> ReadyCheckItem {
        switch screens {
        case .success(let screens):
            ReadyCheckItem(title: "Screens: \(screens.count)", passed: !screens.isEmpty, fix: "connect a screen")
        case .failure(let error):
            ReadyCheckItem(title: "Screens: cannot be read (\(ErrorDetail(error).text))", passed: false,
                           fix: "reconnect the screens, then check again")
        }
    }

    /// At the recording resolution None with the system audio: no screen is
    /// recorded, but the system audio is captured through the main screen.
    private static func systemAudioScreensItem(_ screens: Result<[ScreenInfo], DeviceReadError>) -> ReadyCheckItem {
        let need = ", none recorded (the system audio needs the main screen)"
        let turnOff = "turn off the system audio (--system-audio off)"
        return switch screens {
        case .success(let screens):
            ReadyCheckItem(title: "Screens: \(screens.count)\(need)", passed: screens.contains(where: \.isMain),
                           fix: "connect a screen, or \(turnOff)")
        case .failure(let error):
            ReadyCheckItem(title: "Screens: cannot be read (\(ErrorDetail(error).text))\(need)", passed: false,
                           fix: "reconnect the screens, then check again, or \(turnOff)")
        }
    }

    private static func audioItem(
        _ readAudioInputs: Result<[AudioInputInfo], DeviceReadError>, settings: Settings
    ) -> ReadyCheckItem {
        let cannotBeRead = { (error: DeviceReadError) in
            ReadyCheckItem(title: "Audio: cannot be read (\(ErrorDetail(error).text))", passed: false,
                           fix: "reconnect the audio inputs, then check again")
        }
        let audioInputs: [AudioInputInfo]
        switch audioInputsToJudge(readAudioInputs, settings: settings) {
        case .success(let inputs): audioInputs = inputs
        case .failure(let error): return cannotBeRead(error)
        }
        if case .failure(let error) = unreadableRecordedInputs(audioInputs, settings: settings).first?.channelCount {
            return cannotBeRead(error)
        }
        // The recorded audio sources, in the order of the table of what will be recorded.
        let recorded = WhatWillBeRecorded(settings: settings, screens: .success([]), audioInputs: .success(audioInputs), outputFolder: nil)
            .audio.filter(\.isRecorded)
        var sources = recorded.map { $0.source.kind == .systemAudio ? "system audio" : $0.name }
        // A Mac without an audio input is ready in every audio mode: the screens and the system audio are recorded.
        let noMicrophone = settings.effectiveAudioMode != .none && !recorded.contains { $0.source.kind == .audioInput }
        if noMicrophone { sources.append("no microphone recorded") }
        if !settings.systemAudio, noMicrophone { sources.append("no system audio") }
        return ReadyCheckItem(
            title: "Audio: " + (sources.isEmpty ? "none" : sources.joined(separator: ", ")),
            passed: true, fix: nil)
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
        hours == 1 ? "1 hour" : "\(numberText(hours)) hours"
    }

    /// A whole number below 1e15 without a fraction, any other as Swift writes it.
    private static func numberText(_ number: Double) -> String {
        if number == number.rounded(), abs(number) < 1e15 { return String(Int(number)) }
        return String(number)
    }
}
