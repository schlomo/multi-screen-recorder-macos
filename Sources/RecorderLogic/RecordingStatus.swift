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

    public var needsAttention: Bool {
        isLowOnDisk || screenShowingAnotherScreensPicture != nil || !problems.isEmpty
    }

    /// "!" when something needs the person, otherwise none (D47).
    public var badge: String? { needsAttention ? "!" : nil }
}
