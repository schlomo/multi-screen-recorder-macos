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

    /// The app's bundle: only a crash of a program inside a bundle of this name is offered (D70).
    public static let appBundleName = "Multi Screen Recorder.app"

    /// The newest crash report of the app among `fileNames` that is newer
    /// than `lastOffered`. Only names of exactly the shape
    /// `msr-YYYY-MM-DD-HHMMSS.ips` count, and they sort chronologically; a
    /// report whose `procPath` (the path of the program that crashed) is not
    /// inside the app's bundle, such as a test run's or a stray `msr`'s, is
    /// skipped. `procPath` reads it from a report, newest first, until one is
    /// the app's.
    public static func toOffer(fileNames: [String], lastOffered: String?,
                               procPath: (String) throws -> String) rethrows -> String? {
        let candidates = fileNames
            .filter { $0.hasSuffix(nameSuffix) && $0.dropLast(nameSuffix.count).wholeMatch(of: nameShape) != nil }
            .filter { name in lastOffered.map { name > $0 } ?? true }
            .sorted(by: >)
        for name in candidates where isTheApps(procPath: try procPath(name)) { return name }
        return nil
    }

    /// Whether the program at `procPath` is inside a bundle named `appBundleName`.
    public static func isTheApps(procPath: String) -> Bool {
        procPath.split(separator: "/").dropLast().contains(Substring(appBundleName))
    }

    /// The `procPath` of a crash report: an `.ips` file is a line of JSON,
    /// its header, then the JSON of the report, which holds it.
    public static func procPath(reportText: String, reportName: String) throws(CrashReportError) -> String {
        let body = reportText.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false).dropFirst().first ?? ""
        guard let object = try? JSONSerialization.jsonObject(with: Data(body.utf8)) as? [String: Any],
              let path = object["procPath"] as? String
        else { throw CrashReportError(description: "The crash report \(reportName) names no program (procPath)") }
        return path
    }

    /// The name of the text copy of a crash report, which GitHub accepts as
    /// an attachment where it refuses `.ips`: `msr-….ips` becomes `msr-….txt`.
    public static func textCopyName(crashReportName: String) -> String {
        let base = crashReportName.hasSuffix(nameSuffix) ? String(crashReportName.dropLast(nameSuffix.count)) : crashReportName
        return base + ".txt"
    }

    public static func issueURL(crashReportName: String, version: String, macOSVersion: String) -> URL {
        IssueFormLink.url(template: template, title: "Crash: \(crashReportName)",
                          fields: [(versionField, version), (macOSField, macOSVersion)])
    }
}

public struct CrashReportError: Error, Equatable, CustomStringConvertible {
    public let description: String
}
