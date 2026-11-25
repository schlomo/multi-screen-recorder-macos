/// What `msr record` prints at its end: how long it recorded and where,
/// each file and its state (the screens by number, then the cameras by number, then the audio sources by number, the system audio first), our process's CPU use, and the events that are
/// errors.
public struct RecordingSummary: Equatable, Sendable {
    public let manifest: RecordingManifest
    public let recordingFolder: String
    public let seconds: Double
    /// Whether the finalized manifest was written; if not, the file on disk has no `ended`.
    public let manifestWritten: Bool
    /// A problem whose call to action includes "report it" was told (`ProblemsTold.asksToReportIt`, D84).
    public let problemsAskToReportIt: Bool
    /// The names of the files whose writer failed on a full disk: not finalized, they ask for no report (D84).
    public let filesEndedByAFullDisk: Set<String>

    public init(
        manifest: RecordingManifest, recordingFolder: String, seconds: Double, manifestWritten: Bool, problemsAskToReportIt: Bool,
        filesEndedByAFullDisk: Set<String>
    ) {
        self.manifest = manifest
        self.recordingFolder = recordingFolder
        self.seconds = seconds
        self.manifestWritten = manifestWritten
        self.problemsAskToReportIt = problemsAskToReportIt
        self.filesEndedByAFullDisk = filesEndedByAFullDisk
    }

    /// Ended with an error (exit 3): the manifest's result is `problems`
    /// (D47, D64), or the finalized manifest could not be written (F3).
    public var endedWithError: Bool { !manifest.endedWell || manifest.result == .problems || !manifestWritten }

    /// Whether the person is asked to report the recording, by `msr record`'s `Report it:` line and the app's
    /// next start (D84): a problem asked to report it, or data was lost, a file not finalized or the manifest
    /// without its end. A file a full disk left not finalized does not: the person was asked to free up disk space.
    public var asksToReportIt: Bool {
        let files = manifest.files.map { ($0.name, $0.state) } + manifest.cameraFiles.map { ($0.name, $0.state) }
            + manifest.audioFiles.map { ($0.name, $0.state) }
        return problemsAskToReportIt || !manifestWritten
            || files.contains { name, state in state != .finalized && !filesEndedByAFullDisk.contains(name) }
    }

    public var text: String {
        var lines = ["Recorded \(Self.elapsed(seconds: seconds)) into \(recordingFolder)"]
        let files = (manifest.files.map { ($0.start, $0.name, $0.state) } + manifest.cameraFiles.map { ($0.start, $0.name, $0.state) }
            + manifest.audioFiles.map { ($0.start, $0.name, $0.state) })
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
        lines += whatWentWrong.map(\.line)
        return lines.joined(separator: "\n") + "\n"
    }

    /// The events that are errors, then the problems, then, if `endMissing`,
    /// that the manifest has no end, each with its seconds from the start:
    /// the missing end at the latest of them, as the last thing that went wrong.
    public static func failureLines(of manifest: RecordingManifest, endMissing: Bool) -> [(at: Double, line: String)] {
        let errors = manifest.events.filter(\.event.isFailure).map { event in
            (event.at, "Error at \(elapsed(seconds: event.at)): \(event.event.rawValue)"
                + (event.subject.map { ", \($0)" } ?? "") + (event.error.map { " (\($0))" } ?? ""))
        }
        let problems = manifest.problems.map { ($0.at, "Problem at \(elapsed(seconds: $0.at)): \($0.text)") }
        let lines: [(at: Double, line: String)] = errors + problems
        guard endMissing else { return lines }
        return lines + [(lines.map(\.at).max() ?? 0, manifestNotWrittenLine)]
    }

    public static let manifestNotWrittenLine = "The recording manifest could not be written at the end: \(RecordingNames.manifest) has no end."

    /// What the summary tells went wrong, each with its seconds from the start.
    public var whatWentWrong: [(at: Double, line: String)] {
        Self.failureLines(of: manifest, endMissing: !manifestWritten)
    }

    /// The end of the summary of a recording that asks to report it (D84): the
    /// link to report it, with what went wrong, and what to attach (D64).
    public func reportText(version: String) -> String {
        "Report it: \(ProblemReport.issueURL(whatWentWrong: whatWentWrong, version: version).absoluteString)\n"
            + "Attach: \(ProblemReport.shownPath(recordingFolder))/\(RecordingNames.recordingLog) and \(RecordingNames.manifest)\n"
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
