/// What a problem is, for telling a repeating one once (D46).
public enum ProblemKind: Hashable, Sendable {
    case manifestNotWritten
    case displaysNotRead
    case freeSpaceNotRead
    case crashMarkerNotRemoved
}

/// The problems a recording has told: each goes into the recording
/// manifest, which is written at once, unless writing it is the problem;
/// one of a kind that was told and has not cleared since is not told again.
public struct ProblemsTold: Sendable {
    public enum Outcome: Equatable, Sendable {
        case tell(writeManifest: Bool)
        /// The same kind stands since it was told: nothing to do.
        case alreadyTold
    }

    private var standing: Set<ProblemKind> = []

    public init() {}

    public mutating func add(_ problem: RecordingProblem, kind: ProblemKind, to manifest: inout RecordingManifest) -> Outcome {
        guard standing.insert(kind).inserted else { return .alreadyTold }
        manifest.problems.append(problem)
        return .tell(writeManifest: kind != .manifestNotWritten)
    }

    /// The kind went away: it is told again when it comes back.
    public mutating func cleared(_ kind: ProblemKind) {
        standing.remove(kind)
    }
}
