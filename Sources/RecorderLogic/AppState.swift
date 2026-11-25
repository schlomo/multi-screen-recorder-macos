import Foundation

/// What the app remembers between starts and the person never edits, kept
/// in the state file apart from the settings.
public struct AppState: Codable, Equatable, Sendable {
    private enum CodingKeys: String, CodingKey { case lastOfferedCrashReport, lastRecording }

    /// The last recording, as it ended at Stop, in the app or `msr record` (D64).
    public struct LastRecording: Codable, Equatable, Sendable {
        private enum CodingKeys: String, CodingKey { case folder, result, noticeWanted, noticeShown }

        /// The recording folder's path.
        public var folder: String
        /// The manifest's result; kept for a release before D84, which shows the notice by it.
        public var result: RecordingManifest.Result
        /// Whether the app's next start shows the notice of its problems: it asks to report it (D84).
        public var noticeWanted: Bool
        /// Whether a start of the app has shown the notice of its problems.
        public var noticeShown: Bool

        public init(folder: String, result: RecordingManifest.Result, noticeWanted: Bool, noticeShown: Bool = false) {
            self.folder = folder
            self.result = result
            self.noticeWanted = noticeWanted
            self.noticeShown = noticeShown
        }

        /// A state file of a release before D84 has `result` without `noticeWanted`: no notice.
        public init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            folder = try container.decode(String.self, forKey: .folder)
            result = try container.decode(RecordingManifest.Result.self, forKey: .result)
            noticeWanted = try container.decodeIfPresent(Bool.self, forKey: .noticeWanted) ?? false
            noticeShown = try container.decode(Bool.self, forKey: .noticeShown)
        }
    }

    /// The name of the newest crash report the app has offered to report.
    public var lastOfferedCrashReport: String?
    public var lastRecording: LastRecording?

    public static let empty = AppState(lastOfferedCrashReport: nil)

    public init(lastOfferedCrashReport: String?, lastRecording: LastRecording? = nil) {
        self.lastOfferedCrashReport = lastOfferedCrashReport
        self.lastRecording = lastRecording
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

    /// The state with the recording that just ended as the last one.
    public func recorded(folder: String, result: RecordingManifest.Result, noticeWanted: Bool) -> AppState {
        var state = self
        state.lastRecording = LastRecording(folder: folder, result: result, noticeWanted: noticeWanted)
        return state
    }

    /// The recording folder whose problems the app's start tells: the last
    /// recording's, if it wants the notice, its notice was not shown yet, and the folder is still there.
    public func problemsNoticeFolder(folderExists: (String) -> Bool) -> String? {
        guard let lastRecording, lastRecording.noticeWanted, !lastRecording.noticeShown,
              folderExists(lastRecording.folder)
        else { return nil }
        return lastRecording.folder
    }

    /// The state with the last recording's notice marked as shown.
    public func showingProblemsNotice() -> AppState {
        var state = self
        state.lastRecording?.noticeShown = true
        return state
    }

    /// The state file's content, written like the settings file.
    public func jsonData() throws -> Data {
        try prettyJSON(self)
    }
}
