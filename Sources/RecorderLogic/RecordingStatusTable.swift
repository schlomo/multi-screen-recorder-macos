import Foundation

/// The status window of a running recording (D46): a row per screen, per
/// camera (D74) and per audio source with its files, the data written, its state and its
/// clock drift (an audio row also has its level meter and input volume,
/// which the window draws, D69), and a line with the elapsed time, the data, the files and the free space.
public enum RecordingStatusTable {
    /// "1:07:00" for 1 hour 7 minutes: h:mm:ss (D47).
    public static func elapsed(_ seconds: Double) -> String {
        let whole = Int(seconds)
        return String(format: "%d:%02d:%02d", whole / 3600, whole / 60 % 60, whole % 60)
    }

    public static let columns = ["Source", "Records at", "Files", "Written", "State", "Clock drift"]
    /// The columns the window draws after the text columns, for the audio
    /// rows: the level meter and the input volume's slider (D69).
    public static let audioColumns = ["Level", "Input volume"]

    public struct Row: Equatable, Sendable {
        public var source: SourceCell
        public var recordsAt: String
        public var files: Int
        /// The size of its files on disk, "350 MB" or "1.3 GB".
        public var written: String
        public var state: String
        /// An audio source's clock drift and its correction, "-116 ppm (+34.9 ms)"; empty for a screen.
        public var clockDrift: String
        /// The audio source of an audio row, for its level meter and its input volume (D69); nil for a screen.
        public var audioSource: AudioTracker.SourceID?
        /// The mouse-over: the source's details and its live facts (`SourceDetails`), its label first.
        public var details: String

        public init(
            source: SourceCell, recordsAt: String, files: Int, written: String, state: String, clockDrift: String = "",
            audioSource: AudioTracker.SourceID? = nil, details: String = ""
        ) {
            self.details = details
            self.source = source
            self.recordsAt = recordsAt
            self.files = files
            self.written = written
            self.state = state
            self.clockDrift = clockDrift
            self.audioSource = audioSource
        }

        /// The cells after Source.
        public var values: [String] { [recordsAt, String(files), written, state, clockDrift] }
    }

    /// `bytes`: each screen file's size on disk, by its name; a file
    /// without one makes its screen's Written "?".
    public static func rows(sources: [ScreenTracker.Source], files: [RecordingManifest.ScreenFile], bytes: [String: Int64]) -> [Row] {
        sources.map { source in
            let own = files.filter { $0.screenUUID == source.uuid }
            let sizes = own.map { bytes[$0.name] }
            let written = writtenText(sizes)
            let frameSize: FrameSize? = if case .recording(let size) = source.state { size } else {
                own.last.map { FrameSize(width: $0.frameSize[0], height: $0.frameSize[1]) }
            }
            return Row(
                source: .screen(source.number, name: source.name),
                recordsAt: frameSize.map { "\($0.width)×\($0.height)" } ?? "",
                files: own.count,
                written: written,
                state: text(source.state))
        }
    }

    /// The cameras' rows, below the screens', as a screen's: `bytes` by the camera file's name.
    public static func cameraRows(
        sources: [CameraTracker.Source], files: [RecordingManifest.CameraFile], bytes: [String: Int64]
    ) -> [Row] {
        sources.map { source in
            let own = files.filter { $0.cameraUniqueID == source.uniqueID }
            let frameSize: FrameSize? = switch source.state {
            case .recording(let size), .stalled(let size): size
            default: own.last.map { FrameSize(width: $0.frameSize[0], height: $0.frameSize[1]) }
            }
            return Row(
                source: .camera(source.number, name: source.name),
                recordsAt: frameSize.map { "\($0.width)×\($0.height)" } ?? "",
                files: own.count,
                written: writtenText(own.map { bytes[$0.name] }),
                state: text(source.state))
        }
    }

    /// Without the Camera permission, a row for each camera the camera mode
    /// would record, not numbered: macOS grants it per app, so no camera is recorded (D74).
    public static func cameraRowsWithoutPermission(_ cameras: [CameraInfo]) -> [Row] {
        cameras.map { camera in
            Row(source: .camera(nil, name: camera.name), recordsAt: "", files: 0, written: "",
                state: StateText.noCameraPermission.rawValue)
        }
    }

    /// The audio sources' rows, below the cameras': Records at is the
    /// channels of the source's newest audio file; `clockDrift` the latest
    /// clock drift correction status of each source's running capture.
    public static func audioRows(
        sources: [AudioTracker.Source], files: [RecordingManifest.AudioFile], bytes: [String: Int64],
        clockDrift: [AudioTracker.SourceID: ClockDriftCorrection.Status]
    ) -> [Row] {
        sources.map { source in
            let own = files.filter { file in
                switch source.id {
                case .input(let uid): file.audioSourceUID == uid
                case .systemAudio: file.audioSourceUID == nil
                }
            }
            let sizes = own.map { bytes[$0.name] }
            let written = writtenText(sizes)
            let channels: String = switch own.last?.channels {
            case .mono(let count): count == 1 ? "1 channel" : "\(count) channels"
            case .stereo: "stereo"
            case nil: ""
            }
            let cell: SourceCell = source.id == .systemAudio
                ? .systemAudio(isRecorded: true) : .audioInput(source.number, name: source.name)
            return Row(
                source: cell, recordsAt: channels, files: own.count, written: written, state: text(source.state),
                clockDrift: source.state == .recording || source.state == .noAudio ? clockDriftText(clockDrift[source.id]) : "", audioSource: source.id)
        }
    }

    /// "-116 ppm (+34.9 ms)": the clock drift and the sound added so far;
    /// `measuring (+0.3 ms)` while the clock drift is not known but a
    /// correction is applied, and `measuring` before any.
    public static func clockDriftText(_ status: ClockDriftCorrection.Status?) -> String {
        let correction = status.map { ClockDriftText.signed($0.applied * 1000, decimals: 1, unit: "ms") }
        guard let status, let ppm = status.clockDriftPpm else {
            guard let correction, correction != "0 ms" else { return measuring }
            return "\(measuring) (\(correction))"
        }
        return "\(ClockDriftText.signed(ppm, decimals: 0, unit: "ppm")) (\(correction!))"
    }

    public static let measuring = "measuring"

    /// The files' sizes together; "?" when one cannot be read.
    private static func writtenText(_ sizes: [Int64?]) -> String {
        sizes.contains(nil) ? "?" : DiskEstimate.megabytesOrGigabytes(Double(sizes.compactMap(\.self).reduce(0, +)))
    }

    /// Every text the State column can show; the window sizes the column from them.
    public enum StateText: String, CaseIterable, Sendable {
        case recording
        case noAudio = "no audio"
        case waiting
        case failedRetrying = "failed, retrying"
        case showsAnotherScreen = "shows another screen"
        case diskFull = "disk full"
        case mirroring
        case disconnected
        case notRecorded = "not recorded"
        case asleep
        case noCameraPermission = "no Camera permission"
        case stalled
    }

    static func text(_ state: AudioTracker.Source.State) -> String {
        let text: StateText = switch state {
        case .recording: .recording
        case .noAudio: .noAudio
        case .waiting: .waiting
        case .failedRetrying: .failedRetrying
        case .diskFull: .diskFull
        case .disconnected: .disconnected
        case .notRecorded: .notRecorded
        case .asleep: .asleep
        }
        return text.rawValue
    }

    static func text(_ state: CameraTracker.Source.State) -> String {
        let text: StateText = switch state {
        case .recording: .recording
        case .stalled: .stalled
        case .waiting: .waiting
        case .failedRetrying: .failedRetrying
        case .diskFull: .diskFull
        case .disconnected: .disconnected
        case .notRecorded: .notRecorded
        case .asleep: .asleep
        }
        return text.rawValue
    }

    static func text(_ state: ScreenTracker.Source.State) -> String {
        let text: StateText = switch state {
        case .recording: .recording
        case .waiting: .waiting
        case .failedRetrying: .failedRetrying
        case .showsAnotherScreen: .showsAnotherScreen
        case .diskFull: .diskFull
        case .mirroring: .mirroring
        case .disconnected: .disconnected
        case .asleep: .asleep
        }
        return text.rawValue
    }

    /// "Recording 1:07:00 · 1.3 GB in 3 files · 120.4 GB free", below 1 GB
    /// in MB; "? GB" when
    /// a file's size cannot be read (`bytesWritten` nil), and without the
    /// free space when it cannot be read.
    public static func line(elapsedSeconds: Double, bytesWritten: Int64?, files: Int, freeBytes: Int64?) -> String {
        let written = bytesWritten.map { DiskEstimate.megabytesOrGigabytes(Double($0)) } ?? "? GB"
        var line = "Recording \(elapsed(elapsedSeconds))"
            + " · \(written) in \(files) file\(files == 1 ? "" : "s")"
        if let freeBytes { line += " · \(DiskEstimate.megabytesOrGigabytes(Double(freeBytes))) free" }
        return line
    }
}
