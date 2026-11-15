/// What the person is shown of a running recording: the Dock badge shows
/// the elapsed time until something needs them; the status window lists
/// the problems (recorder.md, "The app").
public struct RecordingStatus: Equatable, Sendable {
    public var isLowOnDisk = false
    /// The display whose file ended because it showed another display's picture, until it is tried again.
    public var displayShowingAnotherDisplaysPicture: String?
    /// What went wrong that the recording could not handle by itself, such as
    /// a manifest that cannot be written or a failing writer.
    public var problems: [String] = []

    public init() {}

    public var needsAttention: Bool {
        isLowOnDisk || displayShowingAnotherDisplaysPicture != nil || !problems.isEmpty
    }

    /// "!" when something needs the person, otherwise the elapsed time as
    /// h:mm, such as "0:05" or "1:07" (D46).
    public func badge(elapsedSeconds: Double) -> String {
        needsAttention ? "!" : Self.hoursAndMinutes(elapsedSeconds)
    }

    /// "1:07" for 1 hour 7 minutes.
    public static func hoursAndMinutes(_ seconds: Double) -> String {
        let minutes = Int(seconds / 60)
        return "\(minutes / 60):" + (minutes % 60 < 10 ? "0" : "") + "\(minutes % 60)"
    }
}
