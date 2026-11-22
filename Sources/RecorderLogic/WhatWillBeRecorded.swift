/// The window's section "What will be recorded", from the settings, the
/// devices connected now and the free space in the output folder, as data
/// the view renders: one table, the screen rows (not recorded at the
/// recording resolution None), the camera rows (the recorded cameras by
/// number, then those not recorded) then the audio rows (the system audio (0) first when
/// it is on, the recorded inputs by number, then the sources not
/// recorded, the system audio among them when it is off) and the total
/// row, and a line of what the required recording hours need, under a
/// line of the settings. GB/h max is the encoder's ceiling, the most a
/// source can write (D53). `msr check`, `msr record` and `msr list` print
/// its `text`.
public struct WhatWillBeRecorded: Equatable, Sendable {
    public static let columns = ["Source", "Looks like", "Drawn at", "Records at", "GB/h max"]
    /// GB/h max of a source not recorded, shown dimmed, and Records at of a screen not recorded.
    static let notRecorded = "-"
    /// GB/h max of a recorded source whose rate cannot be told.
    static let unknown = "?"
    static let cannotBeRead = "cannot be read"

    public struct Screen: Equatable, Sendable {
        /// Nil for a screen not recorded: at the recording resolution None.
        public var number: Int?
        public var name: String
        public var looksLike: String
        public var drawnAt: String
        public var recordsAt: String
        public var gigabytesPerHour: String
    }

    /// One row of the table. A source not recorded is shown dimmed.
    public struct Row: Equatable, Sendable {
        /// Nil for the total row.
        public var source: SourceCell?
        /// The cells after Source.
        public var values: [String]
        public var isRecorded: Bool

        /// A cell per column, Source as text.
        public var cells: [String] { [source?.text ?? "Total"] + values }
    }

    /// A camera: a recorded one has its number, the default camera first,
    /// then in the order listed, as the recording numbers them at its start (D74).
    public struct Camera: Equatable, Sendable {
        public var source: SourceCell
        public var recordsAt: String
        public var gigabytesPerHour: String
        public var isRecorded: Bool { source.number != nil }
    }

    /// An audio input, or the system audio.
    public struct Audio: Equatable, Sendable {
        /// Recorded inputs (`AudioTracker.records`) are numbered from 1 in
        /// the order listed, as the recording numbers them at its start.
        public var source: SourceCell
        public var name: String { source.name }
        /// "1 channel", "2 channels", "stereo" or "cannot be read": the Records at cell.
        public var channels: String
        /// A source not recorded is shown dimmed.
        public var isRecorded: Bool
        public var gigabytesPerHour: String
        /// Why the channels cannot be read; `text` shows it after "cannot be read".
        public var readError: String? = nil
    }

    /// The total GB/h max, and what the required recording hours need.
    public struct Total: Equatable, Sendable {
        public var gigabytesPerHour: String
        /// "2 hours need 4.3 GB, 3.1 GB free."
        public var need: String
    }

    /// "Settings: Auto (resolution Native, audio mode Wired, camera mode All real), system audio on": the effective settings.
    public var settingsLine: String
    /// Set when the screens cannot be read; it stands in place of the Screens table.
    public var screensError: String?
    public var screens: [Screen]
    public var cameras: [Camera] = []
    /// Set when the audio inputs cannot be read; the Audio table then has no row for them.
    public var audioError: String?
    public var audio: [Audio]
    /// Nil unless the screens and the audio inputs the recording records can be read.
    public var total: Total?
    public var outputFolder: String
    public var continuity: String

    public init(
        settingsLine: String, screensError: String?, screens: [Screen], audioError: String?, audio: [Audio], total: Total?,
        outputFolder: String, continuity: String
    ) {
        self.settingsLine = settingsLine
        self.screensError = screensError
        self.screens = screens
        self.audioError = audioError
        self.audio = audio
        self.total = total
        self.outputFolder = outputFolder
        self.continuity = continuity
    }

    /// `outputFolder` is the ready check's probe of it, nil before that has run;
    /// without a usable folder and its free space the total leaves the free space out.
    public init(
        settings: Settings,
        screens readScreens: Result<[ScreenInfo], DeviceReadError>,
        audioInputs readAudioInputs: Result<[AudioInputInfo], DeviceReadError>,
        cameras cameraInfos: [CameraInfo] = [],
        outputFolder: OutputFolderProbe?
    ) {
        self.init(
            settingsLine: Self.settingsLine(settings),
            screensError: nil, screens: [], audioError: nil, audio: [], total: nil,
            outputFolder: "Files go to \(settings.outputFolder)",
            continuity: "Recording continues when screens, cameras or audio sources change.")
        switch readScreens {
        case .success(let screenInfos):
            screens = numberScreens(screenInfos).map { Self.screen($0, settings: settings) }
        case .failure(let error):
            screensError = "The screens cannot be read: \(ErrorDetail(error).text)"
        }
        if case .success(let screenInfos) = screensToJudge(readScreens, settings: settings),
           case .success(let audioInputs) = audioInputsToJudge(readAudioInputs, settings: settings),
           let bytesPerHour = DiskEstimate.bytesPerHour(
               settings: settings, screens: screenInfos, audioInputs: audioInputs, cameras: cameraInfos) {
            total = Self.total(bytesPerHour, settings: settings, outputFolder: outputFolder)
        }
        let ordered = cameraInfos.filter(\.isDefault) + cameraInfos.filter { !$0.isDefault }
        let recorded = ordered.filter { CameraTracker.records($0, settings: settings) }
        cameras = recorded.enumerated().map { Self.camera($0.element, number: $0.offset + 1, settings: settings) }
            + ordered.filter { !CameraTracker.records($0, settings: settings) }.map { Self.camera($0, number: nil, settings: settings) }
        let systemAudio = Audio(
            source: .systemAudio(isRecorded: settings.systemAudio), channels: "stereo", isRecorded: settings.systemAudio,
            gigabytesPerHour: settings.systemAudio
                ? DiskEstimate.gigabytesPerHour(DiskEstimate.systemAudioFileBytesPerHour) : Self.notRecorded)
        audio = []
        switch readAudioInputs {
        case .success(let audioInputs):
            var number = 0
            let inputs = audioInputs.map { input in
                let isRecorded = AudioTracker.records(input, settings: settings)
                if isRecorded { number += 1 }
                return Self.audio(input, number: isRecorded ? number : nil, settings: settings)
            }
            audio = inputs
        case .failure(let error):
            audioError = "The audio inputs cannot be read: \(ErrorDetail(error).text)"
        }
        // The numbered rows read 0, 1, 2 … without a gap; the inputs not recorded follow, in device order,
        // and the system audio, when it is off, goes last with the sources not recorded.
        let inputs = audio
        audio = (settings.systemAudio ? [systemAudio] : []) + inputs.filter(\.isRecorded) + inputs.filter { !$0.isRecorded }
            + (settings.systemAudio ? [] : [systemAudio])
    }

    /// "Settings: Auto (resolution Native, audio mode Wired, camera mode All real), system audio on"; with auto mode off
    /// "Settings: resolution 1080p, audio mode Default microphone (only the default microphone is recorded), camera mode
    /// None (no camera is recorded), system audio off". At the recording resolution None it says that no screen and no
    /// camera is recorded, under the audio modes None and Default microphone and the camera modes None and Default
    /// camera why the inputs and cameras are not recorded.
    static func settingsLine(_ settings: Settings) -> String {
        let resolution = settings.effectiveResolution
        let mode = settings.effectiveAudioMode
        let cameraMode = settings.effectiveCameraMode
        let resolutionReason = resolution.recordsScreens ? "" : " (no screen and no camera is recorded)"
        let modeReason = switch mode {
        case .none: " (no audio input is recorded)"
        case .defaultMicrophone: " (only the default microphone is recorded)"
        case .wired, .allInputs: ""
        }
        let cameraModeReason = switch cameraMode {
        case .none: " (no camera is recorded)"
        case .defaultCamera: " (only the default camera is recorded)"
        case .real, .allCameras: ""
        }
        let choices = "resolution \(resolution.shownName), audio mode \(mode.shownName), camera mode \(cameraMode.shownName)"
        let explained = "resolution \(resolution.shownName)\(resolutionReason), audio mode \(mode.shownName)\(modeReason)"
            + ", camera mode \(cameraMode.shownName)\(cameraModeReason)"
        return "Settings: " + (settings.auto ? "Auto (\(choices))" : explained)
            + ", system audio \(settings.systemAudio ? "on" : "off")"
    }

    /// What the ready check's probes found, as the window and `msr check` show it.
    public init(settings: Settings, facts: ReadyCheckFacts) {
        self.init(
            settings: settings, screens: facts.screens, audioInputs: facts.audioInputs, cameras: facts.cameras,
            outputFolder: facts.outputFolder)
    }

    /// An input whose channels cannot be read says so; its GB/h max is "?" if it is recorded.
    /// One not recorded says after its name why, if there is a reason (`Settings.reasonNotRecorded`): "BlackHole 2ch (virtual)".
    private static func audio(_ input: AudioInputInfo, number: Int?, settings: Settings) -> Audio {
        let isRecorded = number != nil
        let reason = settings.reasonNotRecorded(input)
        let source = SourceCell.audioInput(number, name: input.shownName + (reason.map { " (\($0))" } ?? ""))
        return switch input.channelCount {
        case .success(let count):
            Audio(source: source, channels: count == 1 ? "1 channel" : "\(count) channels", isRecorded: isRecorded,
                  gigabytesPerHour: isRecorded
                      ? DiskEstimate.gigabytesPerHour(DiskEstimate.audioInputFileBytesPerHour(channelCount: count))
                      : notRecorded)
        case .failure(let error):
            Audio(source: source, channels: cannotBeRead, isRecorded: isRecorded,
                  gigabytesPerHour: isRecorded ? unknown : notRecorded, readError: ErrorDetail(error).text)
        }
    }

    /// A camera not recorded has no number and `-` for Records at and GB/h max; after its name it says
    /// why, where its own rule leaves it out: "OBS Virtual Camera (virtual)", "(no format)", "(suspended)".
    private static func camera(_ camera: CameraInfo, number: Int?, settings: Settings) -> Camera {
        guard let number, let frameSize = camera.frameSize(resolution: settings.effectiveResolution) else {
            let leavesOutVirtual = [.defaultCamera, .real].contains(settings.effectiveCameraMode)
                && settings.effectiveResolution.recordsScreens
            let reason: String? = if camera.chosenFormat == nil { "no format" } else if camera.isVirtual && leavesOutVirtual {
                "virtual"
            } else if camera.isSuspended && settings.cameraModeIncludes(camera) && settings.effectiveResolution.recordsScreens {
                "suspended"
            } else { nil }
            return Camera(source: .camera(nil, name: camera.shownName + (reason.map { " (\($0))" } ?? "")),
                          recordsAt: notRecorded, gigabytesPerHour: notRecorded)
        }
        return Camera(
            source: .camera(number, name: camera.shownName), recordsAt: "\(frameSize)",
            gigabytesPerHour: DiskEstimate.gigabytesPerHour(DiskEstimate.videoFileBytesPerHour(frameSize: frameSize, settings: settings)))
    }

    /// At the recording resolution None a screen not recorded: no number, `-` for Records at and GB/h max.
    private static func screen(_ numbered: NumberedScreen, settings: Settings) -> Screen {
        let screen = numbered.screen
        guard settings.effectiveResolution.recordsScreens else {
            return Screen(number: nil, name: screen.name, looksLike: "\(screen.pointSize)", drawnAt: "\(screen.pixelSize)",
                          recordsAt: notRecorded, gigabytesPerHour: notRecorded)
        }
        let frameSize = settings.effectiveResolution.frameSize(forLooksLike: screen.pointSize)
        return Screen(
            number: numbered.number, name: screen.name,
            looksLike: "\(screen.pointSize)", drawnAt: "\(screen.pixelSize)",
            recordsAt: "\(frameSize)",
            gigabytesPerHour: DiskEstimate.gigabytesPerHour(
                DiskEstimate.videoFileBytesPerHour(frameSize: frameSize, settings: settings)))
    }

    /// "2.2" and "2 hours need 4.3 GB, 3.1 GB free."
    private static func total(_ bytesPerHour: Double, settings: Settings, outputFolder: OutputFolderProbe?) -> Total {
        let hours = settings.requiredRecordingHours
        let needed = "\(ReadyCheck.hoursText(hours)) \(hours == 1 ? "needs" : "need")"
            + " \(DiskEstimate.gigabytes(bytesPerHour * hours))"
        let free = if case .usable(.bytes(let bytes)) = outputFolder { ", \(DiskEstimate.gigabytes(Double(bytes))) free" } else { "" }
        return Total(gigabytesPerHour: DiskEstimate.gigabytesPerHour(bytesPerHour), need: "\(needed)\(free).")
    }

    /// The screen rows of the table; none when the screens cannot be read.
    public var screenRows: [Row] {
        screens.map {
            Row(source: .screen($0.number, name: $0.name), values: [$0.looksLike, $0.drawnAt, $0.recordsAt, $0.gigabytesPerHour],
                isRecorded: $0.number != nil)
        }
    }

    /// The camera rows of the table: no Looks like and Drawn at, which are a screen's.
    public var cameraRows: [Row] {
        cameras.map { Row(source: $0.source, values: ["", "", $0.recordsAt, $0.gigabytesPerHour], isRecorded: $0.isRecorded) }
    }

    /// The audio rows of the table, the system audio first: no Looks like and Drawn at.
    public var audioRows: [Row] {
        audio.map {
            Row(source: $0.source, values: ["", "", $0.channels, $0.gigabytesPerHour], isRecorded: $0.isRecorded)
        }
    }

    /// The digits of the highest audio number in the table, at least 1: the width of the number an audio
    /// source not recorded keeps blank in the text, and any source not recorded in the window.
    public var numberDigits: Int {
        String(audioRows.compactMap { $0.source?.number }.max() ?? 1).count
    }

    /// The table's last row: the total GB/h max; nil without a total.
    public var totalRow: Row? {
        total.map { Row(source: nil, values: ["", "", "", $0.gigabytesPerHour], isRecorded: true) }
    }

    /// The text `msr check`, `msr record` and `msr list` print: the settings line, then the window's
    /// one table with its total row and the line of what the hours need, its columns aligned and the
    /// GB/h max column on the right. An error that stands for rows is a line above the table. A source
    /// not recorded has the `Audio <n> - `, `Camera <n> - ` or `Screen <n> - ` part of its name blank.
    public var text: String {
        var lines = ["What will be recorded", "  \(settingsLine)"]
        if let screensError { lines.append("  \(screensError)") }
        if let audioError { lines.append("  \(audioError)") }
        let audioBlank = String(repeating: " ", count: SourceLabel.audioInput(0, name: "").count - 1 + numberDigits)
        let screenDigits = String(screens.compactMap(\.number).max() ?? 1).count
        let screenBlank = String(repeating: " ", count: SourceLabel.screen(0, name: "").count - 1 + screenDigits)
        let cameraDigits = String(cameras.compactMap(\.source.number).max() ?? 1).count
        let cameraBlank = String(repeating: " ", count: SourceLabel.camera(0, name: "").count - 1 + cameraDigits)
        func cells(_ row: Row) -> [String] {
            guard let source = row.source, source.number == nil else { return row.cells }
            let blank = switch source.kind {
            case .screen: screenBlank
            case .camera: cameraBlank
            case .audioInput, .systemAudio: audioBlank
            }
            return [blank + source.name] + row.values
        }
        let audioCells = zip(audio, audioRows).map { audio, row in
            var shown = cells(row)
            if let readError = audio.readError { shown[3] = "\(Self.cannotBeRead) (\(readError))" }
            return shown
        }
        let rows = screenRows.map(cells) + cameraRows.map(cells) + audioCells + [totalRow].compactMap(\.self).map(cells)
        let widths = Self.columns.indices.map { column in ([Self.columns] + rows).map { $0[column].count }.max() ?? 0 }
        func line(_ cells: [String]) -> String {
            let last = cells.count - 1
            let columns = cells.indices.map { column in
                column == last
                    ? String(repeating: " ", count: widths[column] - cells[column].count) + cells[column]
                    : padded(cells[column], widths[column])
            }
            return "  " + columns.joined(separator: "  ")
        }
        let rule = "  " + String(repeating: "─", count: widths.reduce(0, +) + 2 * (widths.count - 1))
        lines += [line(Self.columns), rule]
        lines += screenRows.map { line(cells($0)) }
        if !screenRows.isEmpty { lines.append(rule) }
        lines += cameraRows.map { line(cells($0)) }
        if !cameraRows.isEmpty { lines.append(rule) }
        lines += audioCells.map(line)
        if let total, let totalRow {
            lines += [rule, line(totalRow.cells), "  \(total.need)"]
        }
        lines.append("  \(outputFolder)")
        return lines.joined(separator: "\n") + "\n"
    }
}
