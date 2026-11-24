/// The status line of `msr record` on a terminal: one line, redrawn once a
/// second, of what the status window shows.
public enum StatusLine {
    /// "1 problem · Recording 0:12:34 · 1.2 GB in 7 files · 143.8 GB free · CPU 23 % · 2 screens, 5 audio";
    /// with a camera being recorded "2 screens, 1 camera, 5 audio";
    /// `line` is the window's line, `rows` its table: the sources being recorded are the rows that say
    /// "recording", and a stalled camera, whose file is still written.
    /// The problems are the status's `problems`, those whose call to action was given (D84); none are not mentioned.
    public static func text(line: String, cpu: String?, rows: [RecordingStatusTable.Row], status: RecordingStatus) -> String {
        let written: Set = [RecordingStatusTable.StateText.recording.rawValue, RecordingStatusTable.StateText.stalled.rawValue]
        let recording = rows.filter { written.contains($0.state) }
        let screens = recording.filter { $0.source.kind == .screen }.count
        let cameras = recording.filter { $0.source.kind == .camera }.count
        let audioSources = recording.count - screens - cameras
        let problems = status.problems.count
        let sources = [count(screens, "screen")] + (cameras == 0 ? [] : [count(cameras, "camera")]) + ["\(audioSources) audio"]
        return [problems == 0 ? nil : count(problems, "problem"), line, cpu, sources.joined(separator: ", ")]
            .compactMap(\.self).joined(separator: " · ")
    }

    /// The text cut to the terminal's width minus 1, so it never wraps; a
    /// width that is unknown (nil or 0) is taken as 80 columns.
    public static func fit(_ text: String, width: Int?) -> String {
        let columns = width.flatMap { $0 > 0 ? $0 : nil } ?? 80
        return String(text.prefix(columns - 1))
    }

    private static func count(_ number: Int, _ noun: String) -> String {
        "\(number) \(noun)\(number == 1 ? "" : "s")"
    }
}
