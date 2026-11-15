import Foundation

/// The status window of a running recording (D46): a row per display with
/// its files, the data written and its state, and a line with the elapsed
/// time, the data, the files and the free space.
public enum RecordingStatusTable {
    public static let columns = ["Source", "Records at", "Files", "GB written", "State"]

    public struct Row: Equatable, Sendable {
        public var source: String
        public var recordsAt: String
        public var files: Int
        public var gigabytesWritten: String
        public var state: String

        public init(source: String, recordsAt: String, files: Int, gigabytesWritten: String, state: String) {
            self.source = source
            self.recordsAt = recordsAt
            self.files = files
            self.gigabytesWritten = gigabytesWritten
            self.state = state
        }

        public var cells: [String] { [source, recordsAt, String(files), gigabytesWritten, state] }
    }

    /// `bytes`: each display file's size on disk, by its name; a file
    /// without one makes its display's GB written "?".
    public static func rows(sources: [DisplayTracker.Source], files: [RecordingManifest.DisplayFile], bytes: [String: Int64]) -> [Row] {
        sources.map { source in
            let own = files.filter { $0.displayUUID == source.uuid }
            let sizes = own.map { bytes[$0.name] }
            let written: String = sizes.contains(nil) ? "?" : String(format: "%.1f", Double(sizes.compactMap(\.self).reduce(0, +)) / 1_000_000_000)
            let frameSize: FrameSize? = if case .recording(let size) = source.state { size } else {
                own.last.map { FrameSize(width: $0.frameSize[0], height: $0.frameSize[1]) }
            }
            return Row(
                source: source.number.map { "\($0) \(source.name)" } ?? source.name,
                recordsAt: frameSize.map { "\($0.width)×\($0.height)" } ?? "",
                files: own.count,
                gigabytesWritten: written,
                state: text(source.state))
        }
    }

    static func text(_ state: DisplayTracker.Source.State) -> String {
        switch state {
        case .recording: "recording"
        case .waiting: "waiting"
        case .failedRetrying: "failed, retrying"
        case .showsAnotherDisplay: "shows another display"
        case .diskFull: "disk full"
        case .mirroring: "mirroring"
        case .disconnected: "disconnected"
        case .asleep: "asleep"
        }
    }

    /// "Recording 1:07 · 1.3 GB in 3 files · 120.4 GB free"; "? GB" when
    /// a file's size cannot be read (`bytesWritten` nil), and without the
    /// free space when it cannot be read.
    public static func line(elapsedSeconds: Double, bytesWritten: Int64?, files: Int, freeBytes: Int64?) -> String {
        let written = bytesWritten.map { DiskEstimate.gigabytes(Double($0)) } ?? "? GB"
        var line = "Recording \(RecordingStatus.hoursAndMinutes(elapsedSeconds))"
            + " · \(written) in \(files) file\(files == 1 ? "" : "s")"
        if let freeBytes { line += " · \(DiskEstimate.gigabytes(Double(freeBytes))) free" }
        return line
    }
}
