import Foundation

/// This product's repository on GitHub.
public enum GitHubRepository {
    public static let url = URL(string: "https://github.com/schlomo/multi-screen-recorder-macos")!
    public static let issues = url.appending(path: "issues")
}

/// Choosing the crash report to offer, and the new-issue link that reports it.
/// The app opens the link in the browser and opens no connection itself (D15).
public enum CrashReport {
    private static var nameShape: Regex<Substring> { #/msr-[0-9]{4}-[0-9]{2}-[0-9]{2}-[0-9]{6}/# }
    public static let nameSuffix = ".ips"
    public static let template = "crash-report.yml"
    /// The ids of the fields in `.github/ISSUE_TEMPLATE/crash-report.yml` the link fills.
    public static let versionField = "version"
    public static let macOSField = "macos"

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
