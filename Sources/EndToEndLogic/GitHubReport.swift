/// The run's report in GitHub's own formats: an annotation per failed or
/// stopped scenario (a workflow command, on standard output) and the job
/// summary's table.
public enum GitHubReport {
    /// One scenario's line in the job summary.
    public struct Row: Sendable, Equatable {
        public var scenario: String
        /// `ok`, `FAIL` or `STOP`.
        public var result: String
        public var seconds: Int?
        public var margin: String?
        public var firstFailure: String?
        /// The screenshots that could not be taken: evidence, not a failure.
        public var notes: String?

        public init(scenario: String, result: String, seconds: Int?, margin: String?, firstFailure: String?,
                    notes: String? = nil) {
            self.scenario = scenario
            self.result = result
            self.seconds = seconds
            self.margin = margin
            self.firstFailure = firstFailure
            self.notes = notes
        }
    }

    /// `::error title=<title>::<message>`, escaped as GitHub's workflow
    /// commands require: `%`, CR and LF everywhere, `:` and `,` in a property.
    public static func annotation(title: String, message: String) -> String {
        "::error title=\(escapeProperty(title))::\(escapeData(message))"
    }

    static func escapeData(_ text: String) -> String {
        escape(text, ["%": "%25", "\r": "%0D", "\n": "%0A"])
    }

    static func escapeProperty(_ text: String) -> String {
        escape(text, ["%": "%25", "\r": "%0D", "\n": "%0A", ":": "%3A", ",": "%2C"])
    }

    /// By Unicode scalar: CR LF is one Character in Swift.
    private static func escape(_ text: String, _ table: [Unicode.Scalar: String]) -> String {
        text.unicodeScalars.map { table[$0] ?? String($0) }.joined()
    }

    /// The job summary's Markdown: the verdict and one row per scenario.
    public static func summary(rows: [Row], verdict: String) -> String {
        let lines = rows.map { row in
            let cells = [row.scenario, row.result, row.seconds.map { "\($0) s" } ?? "", row.margin ?? "", row.firstFailure ?? "", row.notes ?? ""]
            return "| " + cells.map(cell).joined(separator: " | ") + " |"
        }
        return (["## End-to-end tests", "", verdict, "", "| Scenario | Result | Time | Margin | First failure | Evidence notes |", "|---|---|---|---|---|---|"]
            + lines + [""]).joined(separator: "\n")
    }

    private static func cell(_ text: String) -> String {
        escape(text, ["|": "\\|", "\r": " ", "\n": " "]).replacing("  ", with: " ")
    }
}
