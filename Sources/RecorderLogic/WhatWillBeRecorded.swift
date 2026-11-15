/// The window's section "What will be recorded", from the settings, the
/// devices connected now and the free space in the output folder, as data
/// the view renders: one table, the display rows then the audio rows with
/// the system audio last, and a total line.
public struct WhatWillBeRecorded: Equatable, Sendable {
    public static let columns = ["Source", "Looks like", "Drawn at", "Records at", "GB/h"]
    /// GB/h of a source not recorded, shown dimmed.
    static let notRecorded = "0"
    /// GB/h of a recorded source whose rate cannot be told.
    static let unknown = "?"
    static let cannotBeRead = "cannot be read"

    public struct Display: Equatable, Sendable {
        public var number: Int
        public var name: String
        public var looksLike: String
        public var drawnAt: String
        public var recordsAt: String
        public var gigabytesPerHour: String
    }

    /// One row of the table: a cell per column. A source not recorded is shown dimmed.
    public struct Row: Equatable, Sendable {
        public var cells: [String]
        public var isRecorded: Bool
    }

    /// An audio input, or the system audio as the last row.
    public struct Audio: Equatable, Sendable {
        public var name: String
        /// "1 channel", "2 channels", "stereo" or "cannot be read": the Records at cell.
        public var channels: String
        /// A source not recorded is shown dimmed.
        public var isRecorded: Bool
        public var gigabytesPerHour: String
    }

    /// Set when the displays cannot be read; it stands in place of the Displays table.
    public var displaysError: String?
    public var displays: [Display]
    /// Set when the audio inputs cannot be read; the Audio table then has no row for them.
    public var audioError: String?
    public var audio: [Audio]
    /// Nil unless the displays and the audio inputs the recording records can be read.
    public var total: String?
    public var outputFolder: String
    public var continuity: String

    public init(
        displaysError: String?, displays: [Display], audioError: String?, audio: [Audio], total: String?,
        outputFolder: String, continuity: String
    ) {
        self.displaysError = displaysError
        self.displays = displays
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
        displays readDisplays: Result<[DisplayInfo], DeviceReadError>,
        audioInputs readAudioInputs: Result<[AudioInputInfo], DeviceReadError>,
        outputFolder: OutputFolderProbe?
    ) {
        self.init(
            displaysError: nil, displays: [], audioError: nil, audio: [], total: nil,
            outputFolder: "Files go to \(settings.outputFolder)",
            continuity: "Recording continues when displays or audio sources change.")
        switch readDisplays {
        case .success(let displayInfos):
            displays = numberDisplays(displayInfos).map { Self.display($0, settings: settings) }
            if case .success(let audioInputs) = audioInputsToJudge(readAudioInputs, settings: settings),
               let bytesPerHour = DiskEstimate.bytesPerHour(
                settings: settings, displays: displayInfos, audioInputs: audioInputs) {
                total = Self.total(bytesPerHour, settings: settings, outputFolder: outputFolder)
            }
        case .failure(let error):
            displaysError = "The displays cannot be read: \(error)"
        }
        switch readAudioInputs {
        case .success(let audioInputs):
            audio = audioInputs.map { Self.audio($0, settings: settings) }
        case .failure(let error):
            audioError = "The audio inputs cannot be read: \(error)"
        }
        audio.append(Audio(
            name: "System audio", channels: "stereo", isRecorded: settings.systemAudio,
            gigabytesPerHour: settings.systemAudio
                ? DiskEstimate.gigabytesPerHour(DiskEstimate.systemAudioFileBytesPerHour) : Self.notRecorded))
    }

    /// What the ready check's probes found, as the window and `msr check` show it.
    public init(settings: Settings, facts: ReadyCheckFacts) {
        self.init(
            settings: settings, displays: facts.displays, audioInputs: facts.audioInputs,
            outputFolder: facts.outputFolder)
    }

    /// An input whose channels cannot be read says so; its GB/h is "?" if it is recorded.
    private static func audio(_ input: AudioInputInfo, settings: Settings) -> Audio {
        let isRecorded = settings.records(input)
        return switch input.channelCount {
        case .success(let count):
            Audio(name: input.label, channels: count == 1 ? "1 channel" : "\(count) channels", isRecorded: isRecorded,
                  gigabytesPerHour: isRecorded
                      ? DiskEstimate.gigabytesPerHour(DiskEstimate.audioInputFileBytesPerHour(channelCount: count))
                      : notRecorded)
        case .failure:
            Audio(name: input.label, channels: cannotBeRead, isRecorded: isRecorded,
                  gigabytesPerHour: isRecorded ? unknown : notRecorded)
        }
    }

    private static func display(_ numbered: NumberedDisplay, settings: Settings) -> Display {
        let frameSize = settings.effectiveResolution.frameSize(forLooksLike: numbered.display.pointSize)
        return Display(
            number: numbered.number, name: numbered.display.name,
            looksLike: "\(numbered.display.pointSize)", drawnAt: "\(numbered.display.pixelSize)",
            recordsAt: "\(frameSize)",
            gigabytesPerHour: DiskEstimate.gigabytesPerHour(
                DiskEstimate.displayFileBytesPerHour(frameSize: frameSize, settings: settings)))
    }

    /// "Total 2.2 GB/h. 2 hours need 4.3 GB, 3.1 GB free."
    private static func total(_ bytesPerHour: Double, settings: Settings, outputFolder: OutputFolderProbe?) -> String {
        let hours = settings.requiredRecordingHours
        let needed = "\(ReadyCheck.hoursText(hours)) \(hours == 1 ? "needs" : "need")"
            + " \(DiskEstimate.gigabytes(bytesPerHour * hours))"
        let free = if case .usable(.bytes(let bytes)) = outputFolder { ", \(DiskEstimate.gigabytes(Double(bytes))) free" } else { "" }
        return "Total \(DiskEstimate.gigabytesPerHour(bytesPerHour)) GB/h. \(needed)\(free)."
    }

    /// The display rows of the table; none when the displays cannot be read.
    public var displayRows: [Row] {
        displays.map {
            Row(cells: ["\($0.number) \($0.name)", $0.looksLike, $0.drawnAt, $0.recordsAt, $0.gigabytesPerHour],
                isRecorded: true)
        }
    }

    /// The audio rows of the table, the system audio last: no Looks like and Drawn at.
    public var audioRows: [Row] {
        audio.map {
            Row(cells: [$0.name, "", "", $0.channels, $0.gigabytesPerHour], isRecorded: $0.isRecorded)
        }
    }

    /// The text `msr check` prints: the window's one table and total line,
    /// its columns aligned and the GB/h column on the right. An error that
    /// stands for rows is a line above the table.
    public var text: String {
        var lines = ["What will be recorded"]
        if let displaysError { lines.append("  \(displaysError)") }
        if let audioError { lines.append("  \(audioError)") }
        let rows = (displayRows + audioRows).map(\.cells)
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
        lines.append(line(Self.columns))
        lines += displayRows.map { line($0.cells) }
        if !displayRows.isEmpty { lines.append("  " + String(repeating: "─", count: widths.reduce(0, +) + 2 * (widths.count - 1))) }
        lines += audioRows.map { line($0.cells) }
        if let total { lines.append("  \(total)") }
        lines.append("  \(outputFolder)")
        return lines.joined(separator: "\n") + "\n"
    }
}
