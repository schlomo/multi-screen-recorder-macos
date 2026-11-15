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

    public var json: Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try! encoder.encode(self)
    }
}
