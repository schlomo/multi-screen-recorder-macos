import Foundation

/// What the app remembers between starts and the person never edits, kept
/// in the state file apart from the settings.
public struct AppState: Codable, Equatable, Sendable {
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
        AppState(lastOfferedCrashReport: crashReportName)
    }

    /// The state file's content, laid out like the settings file's.
    public var json: Data {
        let lines = [lastOfferedCrashReport.map { "  \(jsonString("lastOfferedCrashReport")): \(jsonString($0))" }].compactMap { $0 }
        return Data(("{\n" + lines.joined(separator: ",\n") + (lines.isEmpty ? "" : "\n") + "}\n").utf8)
    }
}
