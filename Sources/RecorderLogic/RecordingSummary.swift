/// What `msr record` prints at its end: how long it recorded and where,
/// each file and its state (the screens by number, then the audio sources by number, the system audio first), our process's CPU use, and the events that are
/// errors.
public struct RecordingSummary: Equatable, Sendable {
    public let manifest: RecordingManifest
    public let recordingFolder: String
    public let seconds: Double
    /// Whether the finalized manifest was written; if not, the file on disk has no `ended`.
    public let manifestWritten: Bool

    public init(manifest: RecordingManifest, recordingFolder: String, seconds: Double, manifestWritten: Bool) {
        self.manifest = manifest
        self.recordingFolder = recordingFolder
        self.seconds = seconds
        self.manifestWritten = manifestWritten
    }

    /// Ended with an error (exit 3): the manifest's result is `problems`
    /// (D47), or the finalized manifest could not be written (F3).
    public var endedWithError: Bool { !manifest.endedWell || !manifestWritten }

    private var errors: [RecordingEvent] { manifest.events.filter(\.event.isFailure) }

    public var text: String {
        var lines = ["Recorded \(Self.elapsed(seconds: seconds)) into \(recordingFolder)"]
        let files = (manifest.files.map { ($0.start, $0.name, $0.state) } + manifest.audioFiles.map { ($0.start, $0.name, $0.state) })
            .enumerated().sorted { lhs, rhs in
                let (left, right) = (SourceLabel.listPosition(ofFileName: lhs.element.1), SourceLabel.listPosition(ofFileName: rhs.element.1))
                return (left.group, left.number, lhs.element.0, lhs.offset) < (right.group, right.number, rhs.element.0, rhs.offset)
            }.map(\.element)
        for (_, name, state) in files {
            lines.append("  \(name)  \(state.rawValue)")
        }
        if files.isEmpty { lines.append("  no files") }
        if let cpu = manifest.cpu {
            lines.append(String(format: "CPU %.0f %% on average, %.0f %% at the peak, of one core (this process only)",
                                cpu.averagePercent, cpu.peakPercent))
        }
        for event in errors {
            lines.append("Error at \(Self.elapsed(seconds: event.at)): \(event.event.rawValue)"
                + (event.subject.map { ", \($0)" } ?? "") + (event.error.map { " (\($0))" } ?? ""))
        }
        for problem in manifest.problems {
            lines.append("Problem at \(Self.elapsed(seconds: problem.at)): \(problem.text)")
        }
        if !manifestWritten {
            lines.append("The recording manifest could not be written at the end: \(RecordingNames.manifest) has no end.")
        }
        return lines.joined(separator: "\n") + "\n"
    }

    /// "1h02m05s", "2m05s" or "5s".
    public static func elapsed(seconds: Double) -> String {
        let whole = Int(seconds)
        let (hours, minutes, rest) = (whole / 3600, whole / 60 % 60, whole % 60)
        func two(_ value: Int) -> String { value < 10 ? "0\(value)" : "\(value)" }
        if hours > 0 { return "\(hours)h\(two(minutes))m\(two(rest))s" }
        if minutes > 0 { return "\(minutes)m\(two(rest))s" }
        return "\(rest)s"
    }
}
