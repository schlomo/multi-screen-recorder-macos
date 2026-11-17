/// The status line of `msr record` on a terminal: one line, redrawn once a
/// second, of what the status window shows.
public enum StatusLine {
    /// "Recording 0:01:07 · 1.3 GB in 3 files · 120.4 GB free, CPU 23 %, 2 screens, 1 audio source, no problems";
    /// `line` is the window's line, `rows` its table: the sources being recorded are the rows that say "recording".
    public static func text(line: String, cpu: String?, rows: [RecordingStatusTable.Row], problems: Int) -> String {
        let recording = rows.filter { $0.state == RecordingStatusTable.StateText.recording.rawValue }
        let screens = recording.filter { $0.source.kind == .screen }.count
        let audioSources = recording.count - screens
        return [line, cpu, count(screens, "screen"), count(audioSources, "audio source"),
                problems == 0 ? "no problems" : count(problems, "problem")]
            .compactMap(\.self).joined(separator: ", ")
    }

    /// The text cut to the terminal's width so it never wraps; whole when the width is unknown.
    public static func fit(_ text: String, width: Int?) -> String {
        guard let width else { return text }
        return String(text.prefix(max(width, 0)))
    }

    private static func count(_ number: Int, _ noun: String) -> String {
        "\(number) \(noun)\(number == 1 ? "" : "s")"
    }
}
