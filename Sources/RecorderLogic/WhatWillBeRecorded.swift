/// The window's section "What will be recorded", from the settings, the
/// devices connected now and the free space in the output folder, as data
/// the view renders: a table of displays, a table of audio sources and a
/// total line.
public struct WhatWillBeRecorded: Equatable, Sendable {
    public static let displayColumns = ["Display", "Looks like", "Drawn at", "Records at", "GB/h"]
    public static let audioColumns = ["Audio", "Channels", "GB/h"]
    static let notRecorded = "not recorded"

    public struct Display: Equatable, Sendable {
        public var number: Int
        public var name: String
        public var looksLike: String
        public var drawnAt: String
        public var recordsAt: String
        public var gigabytesPerHour: String
    }

    /// An audio input, or the system audio as the last row.
    public struct Audio: Equatable, Sendable {
        public var name: String
        public var channels: String
        /// A source not recorded is shown dimmed.
        public var isRecorded: Bool
        public var gigabytesPerHour: String
    }

    /// Set when the devices cannot be read; the section then shows no rows and no total.
    public var devicesError: String?
    public var displays: [Display]
    public var audio: [Audio]
    public var total: String?
    public var outputFolder: String
    public var continuity: String

    public init(
        devicesError: String?, displays: [Display], audio: [Audio], total: String?,
        outputFolder: String, continuity: String
    ) {
        self.devicesError = devicesError
        self.displays = displays
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
            devicesError: nil, displays: [], audio: [], total: nil,
            outputFolder: "Files go to \(settings.outputFolder)",
            continuity: "Recording continues when displays or audio sources change.")
        switch (readDisplays, readAudioInputs) {
        case (.success(let displayInfos), .success(let inputs)):
            displays = numberDisplays(displayInfos).map { Self.display($0, settings: settings) }
            audio = inputs.map { input in
                let isRecorded = settings.records(input)
                return Audio(
                    name: input.label, channels: String(input.channelCount), isRecorded: isRecorded,
                    gigabytesPerHour: isRecorded
                        ? DiskEstimate.gigabytesPerHour(DiskEstimate.audioInputFileBytesPerHour(channelCount: input.channelCount))
                        : Self.notRecorded)
            }
            audio.append(Audio(
                name: "System audio", channels: "stereo", isRecorded: settings.systemAudio,
                gigabytesPerHour: settings.systemAudio
                    ? DiskEstimate.gigabytesPerHour(DiskEstimate.systemAudioFileBytesPerHour) : Self.notRecorded))
            total = Self.total(
                DiskEstimate.bytesPerHour(settings: settings, displays: displayInfos, audioInputs: inputs),
                settings: settings, outputFolder: outputFolder)
        case (.failure(let error), _), (_, .failure(let error)):
            devicesError = "The devices cannot be read: \(error)"
        }
    }

    private static func display(_ numbered: NumberedDisplay, settings: Settings) -> Display {
        let frameSize = settings.resolution.frameSize(forDisplay: numbered.display.pixelSize)
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
}
