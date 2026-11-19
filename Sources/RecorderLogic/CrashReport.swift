import Foundation

/// Choosing the crash report to offer, and the new-issue link that reports it.
/// The app opens the link in the browser and opens no connection itself (D15).
public enum CrashReport {
    private static var nameShape: Regex<Substring> { #/msr-[0-9]{4}-[0-9]{2}-[0-9]{2}-[0-9]{6}/# }
    public static let nameSuffix = ".ips"
    public static let template = "crash-report.yml"
    /// The ids of the fields in `.github/ISSUE_TEMPLATE/crash-report.yml` the link fills.
    public static let versionField = "version"
    public static let macOSField = "macos"
    /// The unified log of the last 2 hours, for the form's optional field "log" (D46), and in the
    /// README for a crash outside a recording.
    public static let logCommand = #"log show --last 2h --predicate 'subsystem == "org.schapiro.multiscreenrecorder" and process == "msr"'"#
    /// The informative text of the crash report dialog: a crash while recording left the recording's
    /// recording manifest and recording log (D64).
    public static let dialogText = "You can report it on GitHub, which needs a GitHub account. Your browser opens a new issue, and Finder shows a copy of the crash report as a text file for you to drag into it. Issues are public, and a crash report contains your Mac's user name: check it before you attach it.\n\nIf it quit while recording, attach that recording's \(RecordingNames.manifest) and \(RecordingNames.recordingLog) from its recording folder too: they show what happened up to the crash."

    /// The newest crash report of `msr` among `fileNames`, if it is newer than
    /// `lastOffered`. Only names of exactly the shape `msr-YYYY-MM-DD-HHMMSS.ips`
    /// count, and they sort chronologically.
    public static func toOffer(fileNames: [String], lastOffered: String?) -> String? {
        let newest = fileNames
            .filter { $0.hasSuffix(nameSuffix) && $0.dropLast(nameSuffix.count).wholeMatch(of: nameShape) != nil }
            .max()
        guard let newest, lastOffered.map({ newest > $0 }) ?? true else { return nil }
        return newest
    }

    /// The name of the text copy of a crash report, which GitHub accepts as
    /// an attachment where it refuses `.ips`: `msr-….ips` becomes `msr-….txt`.
    public static func textCopyName(crashReportName: String) -> String {
        let base = crashReportName.hasSuffix(nameSuffix) ? String(crashReportName.dropLast(nameSuffix.count)) : crashReportName
        return base + ".txt"
    }

    public static func issueURL(crashReportName: String, version: String, macOSVersion: String) -> URL {
        var components = URLComponents(url: GitHubRepository.issues.appending(path: "new"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "template", value: template),
            URLQueryItem(name: "title", value: "Crash: \(crashReportName)"),
            URLQueryItem(name: versionField, value: version),
            URLQueryItem(name: macOSField, value: macOSVersion),
        ]
        // URLComponents leaves & = + # unencoded in values; the form needs them encoded.
        let allowed = CharacterSet.urlQueryAllowed.subtracting(CharacterSet(charactersIn: "&=+#"))
        components.percentEncodedQuery = components.queryItems!.map { item in
            "\(item.name)=\(item.value!.addingPercentEncoding(withAllowedCharacters: allowed)!)"
        }.joined(separator: "&")
        return components.url!
    }
}
