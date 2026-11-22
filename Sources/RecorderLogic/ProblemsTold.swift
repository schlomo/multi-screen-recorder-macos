/// What a problem is, for telling a repeating one once (D46).
public enum ProblemKind: Hashable, Sendable {
    case manifestNotWritten
    /// The timeline file cannot be written at Stop.
    case timelineFileNotWritten
    /// The recording log cannot be created or written; clears when writing it works again.
    case recordingLogNotWritten
    case screensNotRead
    case freeSpaceNotRead
    /// A screen, by its UUID, whose screen file a failure ended (its
    /// stream failed or lost its capture source again without a screen
    /// change, its writer fell behind, it showed another screen's
    /// picture); clears when a file of it starts.
    case screenNotCaptured(String)
    /// A camera, by its unique ID, whose camera file a failure ended; clears when a file of it starts (D74).
    case cameraNotCaptured(String)
    /// The Camera permission is not granted while a camera is to be recorded (D74).
    case cameraPermissionMissing
    /// `msr record` could not show its Dock icon.
    case dockIconNotShown
    case audioInputsNotRead
    /// An audio input that is to be recorded and cannot be, by its name.
    case audioInputNotRecordable(String)
    /// An audio source whose capture failed, by its name; clears when a file of it starts.
    case audioSourceFailed(String)
    /// An audio file whose writer failed, by its name.
    case audioFileFailed(String)
    /// An audio file whose writer failed and that lacks what its writer was given, by its name (D66).
    case audioFileLost(String)
    /// An audio input whose input volume the status window's slider could not set, by its name; clears when a set works (D69).
    case inputVolumeNotSet(String)
    /// An audio input whose input volume changes cannot be followed, by its name; clears when following it works (D69).
    case inputVolumeNotFollowed(String)
}

/// The problems a recording has told: each goes into the recording
/// manifest, which is written at once, unless writing it is the problem;
/// one of a kind that was told and has not cleared since is not told again.
public struct ProblemsTold: Sendable {
    public enum Outcome: Equatable, Sendable {
        case tell(writeManifest: Bool)
        /// The same kind stands since it was told: nothing to do.
        case alreadyTold
        /// The manifest is finalized and changes no more: told only on
        /// standard error and in the unified log (D64).
        case afterTheEnd
    }

    private var standing: Set<ProblemKind> = []

    public init() {}

    public mutating func add(_ problem: RecordingProblem, kind: ProblemKind, to manifest: inout RecordingManifest) -> Outcome {
        guard manifest.state != .finalized else { return .afterTheEnd }
        guard standing.insert(kind).inserted else { return .alreadyTold }
        manifest.problems.append(problem)
        return .tell(writeManifest: kind != .manifestNotWritten)
    }

    /// The kind went away: it is told again when it comes back.
    public mutating func cleared(_ kind: ProblemKind) {
        standing.remove(kind)
    }
}
