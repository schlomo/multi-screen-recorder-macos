/// The window's section "What will be recorded", from the settings, the
/// devices connected now and the free space in the output folder, as data
/// the view renders: one table, the screen rows then the audio rows with
/// the system audio last and the total row, and a line of what the
/// required recording hours need. GB/h max is the encoder's ceiling, the
/// most a source can write (D53).
public struct WhatWillBeRecorded: Equatable, Sendable {
    public static let columns = ["Source", "Looks like", "Drawn at", "Records at", "GB/h max"]
    /// GB/h max of a source not recorded, shown dimmed.
    static let notRecorded = "0"
    /// GB/h max of a recorded source whose rate cannot be told.
    static let unknown = "?"
    static let cannotBeRead = "cannot be read"

    public struct Screen: Equatable, Sendable {
        public var number: Int
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

    /// An audio input, or the system audio as the last row.
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
    }

    /// The total GB/h max, and what the required recording hours need.
    public struct Total: Equatable, Sendable {
        public var gigabytesPerHour: String
        /// "2 hours need 4.3 GB, 3.1 GB free."
        public var need: String
    }

    /// Set when the screens cannot be read; it stands in place of the Screens table.
    public var screensError: String?
    public var screens: [Screen]
    /// Set when the audio inputs cannot be read; the Audio table then has no row for them.
    public var audioError: String?
    public var audio: [Audio]
    /// Nil unless the screens and the audio inputs the recording records can be read.
    public var total: Total?
    public var outputFolder: String
    public var continuity: String

    public init(
        screensError: String?, screens: [Screen], audioError: String?, audio: [Audio], total: Total?,
        outputFolder: String, continuity: String
    ) {
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
        outputFolder: OutputFolderProbe?
    ) {
        self.init(
            screensError: nil, screens: [], audioError: nil, audio: [], total: nil,
            outputFolder: "Files go to \(settings.outputFolder)",
            continuity: "Recording continues when screens or audio sources change.")
        switch readScreens {
        case .success(let screenInfos):
            screens = numberScreens(screenInfos).map { Self.screen($0, settings: settings) }
            if case .success(let audioInputs) = audioInputsToJudge(readAudioInputs, settings: settings),
               let bytesPerHour = DiskEstimate.bytesPerHour(
                settings: settings, screens: screenInfos, audioInputs: audioInputs) {
                total = Self.total(bytesPerHour, settings: settings, outputFolder: outputFolder)
            }
        case .failure(let error):
            screensError = "The screens cannot be read: \(error)"
        }
        switch readAudioInputs {
        case .success(let audioInputs):
            var number = 0
            audio = audioInputs.map { input in
                let isRecorded = AudioTracker.records(input, settings: settings)
                if isRecorded { number += 1 }
                return Self.audio(input, number: isRecorded ? number : nil, settings: settings)
            }
        case .failure(let error):
            audioError = "The audio inputs cannot be read: \(error)"
        }
        audio.append(Audio(
            source: .systemAudio(isRecorded: settings.systemAudio), channels: "stereo", isRecorded: settings.systemAudio,
            gigabytesPerHour: settings.systemAudio
                ? DiskEstimate.gigabytesPerHour(DiskEstimate.systemAudioFileBytesPerHour) : Self.notRecorded))
    }

    /// What the ready check's probes found, as the window and `msr check` show it.
    public init(settings: Settings, facts: ReadyCheckFacts) {
        self.init(
            settings: settings, screens: facts.screens, audioInputs: facts.audioInputs,
            outputFolder: facts.outputFolder)
    }

    /// An input whose channels cannot be read says so; its GB/h max is "?" if it is recorded.
    private static func audio(_ input: AudioInputInfo, number: Int?, settings: Settings) -> Audio {
        let isRecorded = number != nil
        let source = SourceCell.audioInput(number, name: input.shownName)
        return switch input.channelCount {
        case .success(let count):
            Audio(source: source, channels: count == 1 ? "1 channel" : "\(count) channels", isRecorded: isRecorded,
                  gigabytesPerHour: isRecorded
                      ? DiskEstimate.gigabytesPerHour(DiskEstimate.audioInputFileBytesPerHour(channelCount: count))
                      : notRecorded)
        case .failure:
            Audio(source: source, channels: cannotBeRead, isRecorded: isRecorded,
                  gigabytesPerHour: isRecorded ? unknown : notRecorded)
        }
    }

    private static func screen(_ numbered: NumberedScreen, settings: Settings) -> Screen {
        let frameSize = settings.effectiveResolution.frameSize(forLooksLike: numbered.screen.pointSize)
        return Screen(
            number: numbered.number, name: numbered.screen.name,
            looksLike: "\(numbered.screen.pointSize)", drawnAt: "\(numbered.screen.pixelSize)",
            recordsAt: "\(frameSize)",
            gigabytesPerHour: DiskEstimate.gigabytesPerHour(
                DiskEstimate.screenFileBytesPerHour(frameSize: frameSize, settings: settings)))
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
                isRecorded: true)
        }
    }

    /// The audio rows of the table, the system audio last: no Looks like and Drawn at.
    public var audioRows: [Row] {
        audio.map {
            Row(source: $0.source, values: ["", "", $0.channels, $0.gigabytesPerHour], isRecorded: $0.isRecorded)
        }
    }

    /// The table's last row: the total GB/h max; nil without a total.
    public var totalRow: Row? {
        total.map { Row(source: nil, values: ["", "", "", $0.gigabytesPerHour], isRecorded: true) }
    }

    /// The text `msr check` prints: the window's one table with its total
    /// row and the line of what the hours need, its columns aligned and the
    /// GB/h max column on the right. An error that stands for rows is a
    /// line above the table.
    public var text: String {
        var lines = ["What will be recorded"]
        if let screensError { lines.append("  \(screensError)") }
        if let audioError { lines.append("  \(audioError)") }
        let rows = (screenRows + audioRows + [totalRow].compactMap(\.self)).map(\.cells)
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
        let rule = "  " + String(repeating: "─", count: widths.reduce(0, +) + 2 * (widths.count - 1))
        lines += screenRows.map { line($0.cells) }
        if !screenRows.isEmpty { lines.append(rule) }
        lines += audioRows.map { line($0.cells) }
        if let total, let totalRow {
            lines += [rule, line(totalRow.cells), "  \(total.need)"]
        }
        lines.append("  \(outputFolder)")
        return lines.joined(separator: "\n") + "\n"
    }
}
