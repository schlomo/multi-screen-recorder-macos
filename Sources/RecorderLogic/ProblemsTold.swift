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
    /// A camera, by its unique ID, whose stream stalled; clears when its frames come again, a file of it starts or its
    /// capture ends (D74, D78).
    case cameraStalled(String)
    /// The Camera permission is not granted while a camera is to be recorded (D74).
    case cameraPermissionMissing
    /// `msr record` could not show its Dock icon.
    case dockIconNotShown
    case audioInputsNotRead
    /// The audio inputs' changes cannot be followed (the device list's listener failed): it never ends.
    case audioInputChangesNotFollowed
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
    /// A video file a full disk ended; clears when there is room again.
    case diskFull
    /// A screen file or a camera file whose writer failed and that lacks what its writer was given, by its name (D66).
    case videoFileLost(String)
    /// A screen file or a camera file whose guide tracks end before its video, by its name: the video is intact.
    case guideTracksCut(String)
}

extension ProblemKind {
    /// Whether its line is red (D78, the owner's rule): something broken that a person must fix,
    /// or a recording not usable as it is. Red while it lasts and its source is not recorded or
    /// saved, or a person must act; a damaged file and changes of the audio inputs not followed
    /// always. Orange, a hiccup in a recording that worked: everything once it is over, and always
    /// what never touches what is recorded, and a stall, whose file goes on.
    func isRed(ongoing: Bool) -> Bool {
        switch self {
        case .audioFileLost, .videoFileLost, .audioInputChangesNotFollowed, .audioInputNotRecordable:
            true
        case .dockIconNotShown, .inputVolumeNotSet, .inputVolumeNotFollowed, .timelineFileNotWritten, .cameraStalled,
             .guideTracksCut:
            false
        case .diskFull, .cameraPermissionMissing, .screenNotCaptured, .cameraNotCaptured, .audioSourceFailed, .audioFileFailed,
             .recordingLogNotWritten, .manifestNotWritten, .freeSpaceNotRead, .screensNotRead, .audioInputsNotRead:
            ongoing
        }
    }
}

extension ProblemKind {
    /// The kind's own words in its line (D78); `source` names the screen or camera a kind keyed by its ID is of.
    func phrase(source: String?) -> String {
        switch self {
        case .manifestNotWritten: "Recording manifest not written"
        case .timelineFileNotWritten: "Timeline file not written"
        case .recordingLogNotWritten: "Recording log not written"
        case .screensNotRead: "Screens not read"
        case .freeSpaceNotRead: "Free space not read"
        case .screenNotCaptured(let uuid): "Screen \(source ?? uuid) not captured"
        case .cameraNotCaptured(let uniqueID): "Camera \(source ?? uniqueID) not captured"
        case .cameraStalled(let uniqueID): "Camera \(source ?? uniqueID) stalled"
        case .cameraPermissionMissing: "Camera permission missing"
        case .dockIconNotShown: "Dock icon not shown"
        case .audioInputsNotRead: "Audio inputs not read"
        case .audioInputChangesNotFollowed: "Changes of the audio inputs not followed"
        case .audioInputNotRecordable(let name): "Audio input \(name) not recordable"
        case .audioSourceFailed(let name): "\(name) not captured"
        case .audioFileFailed(let name): "File \(name) failed"
        case .audioFileLost(let name), .videoFileLost(let name): "File \(name) incomplete"
        case .inputVolumeNotSet(let name): "Input volume of \(name) not set"
        case .inputVolumeNotFollowed(let name): "Input volume of \(name) not followed"
        case .diskFull: "Disk full"
        case .guideTracksCut(let name): "Guide tracks of \(name) cut"
        }
    }
}

/// A line of the status window's problems: red when broken, orange for a hiccup (D78).
public struct ProblemLine: Equatable, Sendable {
    public var text: String
    public var isRed: Bool

    public init(text: String, isRed: Bool) {
        self.text = text
        self.isRed = isRed
    }
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

    /// How a problem that lasted ended.
    public enum Ending: Sendable {
        case recovered
        /// Its source went away.
        case disconnected
    }

    /// A problem as told, with when it began and, once over, ended, in nanoseconds since the start.
    private struct Told: Sendable {
        var kind: ProblemKind
        var problem: RecordingProblem
        var source: String?
        var began: Int64
        var ended: Int64?
        var ending = Ending.recovered
    }

    private var told: [Told] = []

    public init() {}

    /// Into the manifest and the window's lines. `source` names the screen or camera of a kind keyed by its ID;
    /// `endedAt`: already over when told, as a failure of a file after a newer file of its source started.
    public mutating func add(
        _ problem: RecordingProblem, kind: ProblemKind, source: String? = nil, endedAt: Int64? = nil,
        to manifest: inout RecordingManifest
    ) -> Outcome {
        guard manifest.state != .finalized else { return .afterTheEnd }
        guard !isOngoing(kind) else { return .alreadyTold }
        manifest.problems.append(problem)
        show(problem, kind: kind, source: source, endedAt: endedAt)
        return .tell(writeManifest: kind != .manifestNotWritten)
    }

    /// Into the window's lines only, for a problem the manifest already lists (a video file's end); none while
    /// one of its kind lasts.
    public mutating func show(_ problem: RecordingProblem, kind: ProblemKind, source: String? = nil, endedAt: Int64? = nil) {
        guard !isOngoing(kind) else { return }
        let at = Int64((problem.at * 1_000_000_000).rounded())
        // A stall is told once the camera delivered no frame for the stall limit: it began that much earlier.
        let began = if case .cameraStalled = kind { max(0, at - RecorderValues.cameraStallLimit.nanoseconds) } else { at }
        told.append(Told(kind: kind, problem: problem, source: source, began: began, ended: endedAt.map { max($0, began) }))
    }

    private func isOngoing(_ kind: ProblemKind) -> Bool { told.contains { $0.kind == kind && $0.ended == nil } }

    /// The kind went away at `now`: it is told again when it comes back. A
    /// stall's `length` says when it began (its end minus its length).
    public mutating func cleared(_ kind: ProblemKind, at now: Int64, length: Int64? = nil, ending: Ending = .recovered) {
        guard let index = told.lastIndex(where: { $0.kind == kind && $0.ended == nil }) else { return }
        told[index].ended = now
        told[index].ending = ending
        if let length { told[index].began = max(0, now - length) }
    }

    /// The status window's lines, one per kind (a kind names its source): red first, then
    /// orange, each newest first (D78).
    public func lines(now: Int64) -> [ProblemLine] {
        var kinds: [ProblemKind] = []
        for entry in told.reversed() where !kinds.contains(entry.kind) { kinds.append(entry.kind) }
        let lines = kinds.map { kind in Self.line(told.filter { $0.kind == kind }, now: now) }
        return lines.filter(\.isRed) + lines.filter { !$0.isRed }
    }

    /// `<phrase> since 0:53`, `<phrase> for 7.4 s at 0:53, recovered` (or `, then disconnected`),
    /// `<phrase> 3 times, 12 s in total[, recovered]`, then the latest error after a colon, `latest: ` before it
    /// when the errors differ; a stall reads `stalled 7.4 s`, without its error, always the same.
    private static func line(_ repeats: [Told], now: Int64) -> ProblemLine {
        let latest = repeats[repeats.count - 1]
        let isStall = if case .cameraStalled = latest.kind { true } else { false }
        let phrase = latest.kind.phrase(source: latest.source)
        let errors = repeats.map(\.problem.error)
        let why = isStall ? "" : latest.problem.error.map { ": " + (Set(errors).count > 1 ? "latest: " : "") + $0 } ?? ""
        let ending = latest.ending == .recovered ? "recovered" : "then disconnected"
        let text = if repeats.count > 1 {
            "\(phrase) \(repeats.count) times, \(seconds(repeats.reduce(Int64(0)) { $0 + ($1.ended ?? now) - $1.began })) in total"
                + (latest.ended == nil ? "" : ", \(ending)")
        } else if let ended = latest.ended {
            "\(phrase) \(isStall ? "" : "for ")\(seconds(ended - latest.began)) at \(time(latest.began)), \(ending)"
        } else {
            "\(phrase) since \(time(latest.began))"
        }
        return ProblemLine(text: text + why, isRed: latest.kind.isRed(ongoing: latest.ended == nil))
    }

    /// "0:53" since the start, "1:02:03" from an hour on.
    private static func time(_ nanoseconds: Int64) -> String {
        let whole = Int(nanoseconds / 1_000_000_000)
        return whole < 3600 ? String(format: "%d:%02d", whole / 60, whole % 60) : RecordingStatusTable.elapsed(Double(whole))
    }

    /// "7.4 s" below 10 s as rounded, "12 s" from there, "1:05" from a minute on.
    private static func seconds(_ nanoseconds: Int64) -> String {
        let tenths = (Double(nanoseconds) / 100_000_000).rounded()
        guard tenths >= 100 else { return String(format: "%.1f s", tenths / 10) }
        let whole = max(10, Int((Double(nanoseconds) / 1_000_000_000).rounded()))
        return whole < 60 ? "\(whole) s" : time(Int64(whole) * 1_000_000_000)
    }
}
