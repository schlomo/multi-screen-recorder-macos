/// Which audio sources show a clock drift status, in the status window and in the `--debug` block.
public enum ClockDriftShown {
    /// The sources shown that have a running capture and a report from that very capture, by number.
    /// `reports` holds each source's latest status with the number of the capture it came from;
    /// `running` the number of each source's running capture. A report of a capture that ended, or of
    /// an earlier capture of a reconnected source, is out.
    public static func sources(
        shown: [AudioTracker.Source],
        reports: [AudioTracker.SourceID: (number: Int, status: ClockDriftCorrection.Status)],
        running: [AudioTracker.SourceID: Int]
    ) -> [(source: AudioTracker.Source, status: ClockDriftCorrection.Status)] {
        shown.sorted { $0.number < $1.number }.compactMap { source in
            guard let report = reports[source.id], running[source.id] == report.number else { return nil }
            return (source, report.status)
        }
    }
}
