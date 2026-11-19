import Foundation

/// Reporting a recording that ended with an error (D64): the notice on the
/// app's next start, and the new-issue link with the problem report form,
/// filled with the version and what went wrong, the last first.
public enum ProblemReport {
    public static let template = "problem-report.yml"
    /// The ids of the fields in `.github/ISSUE_TEMPLATE/problem-report.yml` the link fills.
    public static let versionField = "version"
    public static let whatHappenedField = "what-happened"
    /// The form's own title, for the person to complete.
    public static let title = "Problem: "
    /// The longest link given to the browser, in characters; GitHub refuses
    /// a much longer one [ASSUMED: its limit is about 8 kB].
    public static let maximumLinkLength = 8000
    public static let noticeTitle = "The last recording had problems"
    public static let reportButton = "Report a problem"
    public static let dismissButton = "Dismiss"

    public static func noticeText(recordingFolder: String) -> String {
        "Its recording folder is \(recordingFolder).\n\nYou can report it on GitHub, which needs a GitHub account. Your browser opens a new issue with the version and what went wrong filled in, and Finder shows the recording's \(RecordingNames.manifest) and \(RecordingNames.recordingLog) for you to drag into it. Issues are public: both files name your screens and audio devices, and the recording folder's path can hold your Mac's user name. Check them before you attach them."
    }

    /// The link to a new problem report: as many of `whatWentWrong`, the last
    /// first, as fit in `maximumLinkLength`, saying how many more there are.
    public static func issueURL(whatWentWrong: [(at: Double, line: String)], version: String) -> URL {
        let lastFirst = whatWentWrong.enumerated()
            .sorted { ($0.element.at, $0.offset) > ($1.element.at, $1.offset) }
            .map(\.element.line)
        func link(shown: Int) -> URL {
            IssueFormLink.url(template: template, title: title, fields: [
                (versionField, version),
                (whatHappenedField, whatHappened(lastFirst: lastFirst, shown: shown)),
            ])
        }
        // The longest prefix that fits; the link grows with every line shown.
        var (fits, tooLong) = (0, lastFirst.count + 1)
        while tooLong - fits > 1 {
            let middle = (fits + tooLong) / 2
            if link(shown: middle).absoluteString.count <= maximumLinkLength { fits = middle } else { tooLong = middle }
        }
        return link(shown: fits)
    }

    static func whatHappened(lastFirst: [String], shown: Int) -> String {
        let attached = "\(RecordingNames.recordingLog) and \(RecordingNames.manifest)"
        guard !lastFirst.isEmpty else { return "The recording ended with problems; \(attached) tell what happened." }
        var lines = ["The recording ended with problems. What went wrong, the last first:"] + lastFirst.prefix(shown)
        if shown < lastFirst.count { lines.append("… and \(lastFirst.count - shown) more, in \(attached).") }
        return lines.joined(separator: "\n")
    }
}
