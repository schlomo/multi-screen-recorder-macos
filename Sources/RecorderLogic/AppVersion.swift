/// The version a build carries in its bundle's Info.plist, written by
/// `scripts/build-app`.
public struct AppVersion: Equatable, Sendable, CustomStringConvertible {
    public static let versionKey = "MSRVersion"
    public static let commitKey = "MSRCommit"

    /// The full version string, such as `0.3.0-pr2+a1b2c3d`; nil outside a bundle.
    public let version: String?
    public let commit: String?

    public init(infoDictionary: [String: Any]?) {
        version = infoDictionary?[Self.versionKey] as? String
        commit = infoDictionary?[Self.commitKey] as? String
    }

    public var description: String {
        guard let version else { return "development build (not bundled)" }
        return "\(version) (\(commit ?? "commit missing from Info.plist"))"
    }
}
