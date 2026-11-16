/// The version a build carries in its bundle's Info.plist, written by
/// `scripts/build-app`.
public struct AppVersion: Equatable, Sendable, CustomStringConvertible {
    public static let versionKey = "MSRVersion"
    public static let commitKey = "MSRCommit"
    public static let buildDateKey = "MSRBuildDate"

    /// The full version string, such as `0.20261115.3-pr2+a1b2c3d`; nil outside a bundle.
    public let version: String?
    public let commit: String?
    /// The commit date of the build, such as `2026-11-16`, in UTC as the version's date.
    public let buildDate: String?

    public init(infoDictionary: [String: Any]?) {
        version = infoDictionary?[Self.versionKey] as? String
        commit = infoDictionary?[Self.commitKey] as? String
        buildDate = infoDictionary?[Self.buildDateKey] as? String
    }

    /// What `msr check` and `msr record` print first: the name, the version
    /// as `msr version` shows it, the build date, the homepage, then an empty line.
    public var banner: String {
        "Multi Screen Recorder \(description)" + (buildDate.map { ", built \($0)" } ?? "")
            + "\n\(Homepage.url.absoluteString)\n\n"
    }

    public var description: String {
        guard let version else { return "development build (not bundled)" }
        return "\(version) (\(commit ?? "commit missing from Info.plist"))"
    }
}
