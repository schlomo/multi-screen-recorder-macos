import Foundation

/// The status window of a running recording (D46): a row per screen and
/// per audio source with its files, the data written and its state, and a
/// line with the elapsed time, the data, the files and the free space.
public enum RecordingStatusTable {
    /// "1:07:00" for 1 hour 7 minutes: h:mm:ss (D47).
    public static func elapsed(_ seconds: Double) -> String {
        let whole = Int(seconds)
        return String(format: "%d:%02d:%02d", whole / 3600, whole / 60 % 60, whole % 60)
    }

    public static let columns = ["Source", "Records at", "Files", "Written", "State"]

    public struct Row: Equatable, Sendable {
        public var source: SourceCell
        public var recordsAt: String
        public var files: Int
        /// The size of its files on disk, "350 MB" or "1.3 GB".
        public var written: String
        public var state: String

        public init(source: SourceCell, recordsAt: String, files: Int, written: String, state: String) {
            self.source = source
            self.recordsAt = recordsAt
            self.files = files
            self.written = written
            self.state = state
        }

        /// The cells after Source.
        public var values: [String] { [recordsAt, String(files), written, state] }
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

    /// The audio sources' rows, below the screens': Records at is the
    /// channels of the source's newest audio file.
    public static func audioRows(sources: [AudioTracker.Source], files: [RecordingManifest.AudioFile], bytes: [String: Int64]) -> [Row] {
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
            return Row(source: cell, recordsAt: channels, files: own.count, written: written, state: text(source.state))
        }
    }

    /// The files' sizes together; "?" when one cannot be read.
    private static func writtenText(_ sizes: [Int64?]) -> String {
        sizes.contains(nil) ? "?" : DiskEstimate.megabytesOrGigabytes(Double(sizes.compactMap(\.self).reduce(0, +)))
    }

    static func text(_ state: AudioTracker.Source.State) -> String {
        switch state {
        case .recording: "recording"
        case .waiting: "waiting"
        case .failedRetrying: "failed, retrying"
        case .diskFull: "disk full"
        case .disconnected: "disconnected"
        case .notRecorded: "not recorded"
        case .asleep: "asleep"
        }
    }

    static func text(_ state: ScreenTracker.Source.State) -> String {
        switch state {
        case .recording: "recording"
        case .waiting: "waiting"
        case .failedRetrying: "failed, retrying"
        case .showsAnotherScreen: "shows another screen"
        case .diskFull: "disk full"
        case .mirroring: "mirroring"
        case .disconnected: "disconnected"
        case .asleep: "asleep"
        }
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
