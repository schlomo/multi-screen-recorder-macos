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
    /// A camera, by its unique ID, whose stream stalled; clears when its frames come again or a file of it starts (D74).
    case cameraStalled(String)
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

extension ProblemKind {
    /// Whether the problem can end while the recording goes on, so its line
    /// turns orange once it recovered (D78). A failure cost a file split and a gap: it stays red.
    var canRecover: Bool {
        switch self {
        case .cameraStalled, .recordingLogNotWritten, .manifestNotWritten, .screensNotRead, .audioInputsNotRead,
             .freeSpaceNotRead, .cameraPermissionMissing, .inputVolumeNotSet, .inputVolumeNotFollowed:
            true
        case .timelineFileNotWritten, .screenNotCaptured, .cameraNotCaptured, .dockIconNotShown, .audioInputNotRecordable,
             .audioSourceFailed, .audioFileFailed, .audioFileLost:
            false
        }
    }
}

/// A line of the status window's problems: red while ongoing, orange once recovered (D78).
public struct ProblemLine: Equatable, Sendable {
    public var text: String
    public var isRecovered: Bool

    public init(text: String, isRecovered: Bool) {
        self.text = text
        self.isRecovered = isRecovered
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

    /// A problem as told, with when it began and, once cleared, ended, in nanoseconds since the start.
    private struct Told: Sendable {
        var kind: ProblemKind
        var problem: RecordingProblem
        var began: Int64
        var ended: Int64?
    }

    private var told: [Told] = []

    public init() {}

    public mutating func add(_ problem: RecordingProblem, kind: ProblemKind, to manifest: inout RecordingManifest) -> Outcome {
        guard manifest.state != .finalized else { return .afterTheEnd }
        guard !told.contains(where: { $0.kind == kind && $0.ended == nil }) else { return .alreadyTold }
        manifest.problems.append(problem)
        let at = Int64((problem.at * 1_000_000_000).rounded())
        // A stall is told once the camera delivered no frame for the stall limit: it began that much earlier.
        let began = if case .cameraStalled = kind { max(0, at - RecorderValues.cameraStallLimit.nanoseconds) } else { at }
        told.append(Told(kind: kind, problem: problem, began: began, ended: nil))
        return .tell(writeManifest: kind != .manifestNotWritten)
    }

    /// The kind went away at `now`: it is told again when it comes back. A
    /// stall's `length` says when it began (its end minus its length).
    public mutating func cleared(_ kind: ProblemKind, at now: Int64, length: Int64? = nil) {
        guard let index = told.lastIndex(where: { $0.kind == kind && $0.ended == nil }) else { return }
        told[index].ended = now
        if let length { told[index].began = max(0, now - length) }
    }

    /// The status window's lines, in the order told; the stalls of a camera share the line of its first.
    public func lines(now: Int64) -> [ProblemLine] {
        var lines: [ProblemLine] = []
        var stallLines: [String: Int] = [:]
        for (index, entry) in told.enumerated() {
            if case .cameraStalled(let uniqueID) = entry.kind {
                guard stallLines[uniqueID] == nil else { continue }
                stallLines[uniqueID] = lines.count
                lines.append(Self.stallLine(told[index...].filter { $0.kind == entry.kind }, now: now))
            } else if !entry.kind.canRecover {
                lines.append(ProblemLine(text: entry.problem.text, isRecovered: false))
            } else {
                let what = entry.problem.problem
                let why = entry.problem.error.map { ": \($0)" } ?? ""
                let line = if let ended = entry.ended {
                    ProblemLine(
                        text: "\(what) for \(Self.seconds(ended - entry.began)) at \(Self.time(entry.began)), recovered\(why)",
                        isRecovered: true)
                } else {
                    ProblemLine(text: "\(what) since \(Self.time(entry.began))\(why)", isRecovered: false)
                }
                lines.append(line)
            }
        }
        return lines
    }

    private static func stallLine(_ stalls: [Told], now: Int64) -> ProblemLine {
        let source = stalls[0].problem.problem
        let isRecovered = stalls.allSatisfy { $0.ended != nil }
        if stalls.count == 1, let stall = stalls.first {
            return if let ended = stall.ended {
                ProblemLine(text: "\(source) stalled \(seconds(ended - stall.began)) at \(time(stall.began)), recovered", isRecovered: true)
            } else {
                ProblemLine(text: "\(source) stalled since \(time(stall.began))", isRecovered: false)
            }
        }
        let total = stalls.reduce(Int64(0)) { $0 + ($1.ended ?? now) - $1.began }
        return ProblemLine(
            text: "\(source) stalled \(stalls.count) times, \(seconds(total)) in total" + (isRecovered ? ", recovered" : ""),
            isRecovered: isRecovered)
    }

    /// "0:53" since the start, "1:02:03" from an hour on.
    private static func time(_ nanoseconds: Int64) -> String {
        let whole = Int(nanoseconds / 1_000_000_000)
        return whole < 3600 ? String(format: "%d:%02d", whole / 60, whole % 60) : RecordingStatusTable.elapsed(Double(whole))
    }

    /// "7.4 s" below 10 s, "12 s" from there on.
    private static func seconds(_ nanoseconds: Int64) -> String {
        let seconds = Double(nanoseconds) / 1_000_000_000
        return String(format: seconds < 10 ? "%.1f s" : "%.0f s", seconds)
    }
}
