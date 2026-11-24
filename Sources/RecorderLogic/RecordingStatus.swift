/// What the person is shown of a running recording: the Dock badge shows
/// "!" when something needs them; the status window lists the problems (recorder.md, "The app").
public struct RecordingStatus: Equatable, Sendable {
    public var isLowOnDisk = false
    /// The problems whose call to action was given (D84): something the person has to do.
    public var problemsCalledToAction: [String] = []

    public init() {}

    public var needsAttention: Bool {
        isLowOnDisk || !problemsCalledToAction.isEmpty
    }

    /// "!" when something needs the person, otherwise none (D47).
    public var badge: String? { needsAttention ? "!" : nil }
}
