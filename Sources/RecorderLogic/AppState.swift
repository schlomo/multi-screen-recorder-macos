import Foundation

/// What the app remembers between starts and the person never edits, kept
/// in the state file apart from the settings.
public struct AppState: Codable, Equatable, Sendable {
    private enum CodingKeys: String, CodingKey { case lastOfferedCrashReport }

    /// The name of the newest crash report the app has offered to report.
    public var lastOfferedCrashReport: String?

    public static let empty = AppState(lastOfferedCrashReport: nil)

    public init(lastOfferedCrashReport: String?) {
        self.lastOfferedCrashReport = lastOfferedCrashReport
    }

    public init(json: Data) throws {
        self = try JSONDecoder().decode(AppState.self, from: json)
    }

    /// The state with `crashReportName` marked as offered.
    public func offering(_ crashReportName: String) -> AppState {
        var state = self
        state.lastOfferedCrashReport = crashReportName
        return state
    }

    /// The state file's content, laid out like the settings file's.
    public var json: Data {
        guard let lastOfferedCrashReport else { return Data("{\n}\n".utf8) }
        let line = "  \(jsonString(CodingKeys.lastOfferedCrashReport.rawValue)): \(jsonString(lastOfferedCrashReport))"
        return Data("{\n\(line)\n}\n".utf8)
    }
}
