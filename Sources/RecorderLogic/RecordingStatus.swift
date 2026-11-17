/// What the person is shown of a running recording: the Dock badge shows
/// "!" when something needs them; the status window lists the problems (recorder.md, "The app").
public struct RecordingStatus: Equatable, Sendable {
    public var isLowOnDisk = false
    /// The screen whose file ended because it showed another screen's picture, until it is tried again.
    public var screenShowingAnotherScreensPicture: String?
    /// What went wrong that the recording could not handle by itself, such as
    /// a manifest that cannot be written or a failing writer.
    public var problems: [String] = []

    public init() {}

    /// What needs the person: each problem, low disk space and a screen showing another screen's picture.
    public var attentionCount: Int {
        problems.count + (isLowOnDisk ? 1 : 0) + (screenShowingAnotherScreensPicture != nil ? 1 : 0)
    }

    public var needsAttention: Bool { attentionCount > 0 }

    /// "!" when something needs the person, otherwise none (D47).
    public var badge: String? { needsAttention ? "!" : nil }
}
