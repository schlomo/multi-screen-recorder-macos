/// What the person is shown of a running recording: the Dock badge counts
/// the minutes until something needs them, and "Stop recording?" lists the
/// problems (recorder.md, "The app").
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

    /// "!" when something needs the person, otherwise the elapsed minutes.
    public func badge(elapsedSeconds: Double) -> String {
        needsAttention ? "!" : String(Int(elapsedSeconds / 60))
    }

    /// The informative text of "Stop recording?": the problems, nil without any.
    public var stopQuestionDetails: String? {
        problems.isEmpty ? nil : problems.joined(separator: "\n\n")
    }
}
