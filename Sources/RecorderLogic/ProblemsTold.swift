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
    /// change, its writer failed or fell behind, it showed another screen's
    /// picture); ends when a file of it starts, or when it is disconnected (D78).
    case screenNotCaptured(String)
    /// A camera, by its unique ID, whose camera file a failure ended (its stream or its writer failed); ends when a
    /// file of it starts, or when it is disconnected (D74, D78).
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
    /// An audio input, by its UID, whose no audio began right after its gaps, `source` naming the input and
    /// the note its gaps' time; ends when its sound returns or it disconnects (D81).
    case audioInputSilentAfterGaps(String)
    /// A video file a full disk ended; clears when there is room again.
    case diskFull
    /// A screen file or a camera file whose writer failed and that lacks what its writer was given, by its name (D66).
    case videoFileLost(String)
    /// A screen file or a camera file whose guide tracks end before its video, by its name: the video is intact.
    case guideTracksCut(String)
}

/// What a person has to do about a problem (D84, D91, the owner's rule): only a problem whose call to action was
/// given shows a line in the status window, bounces the Dock icon, sets the badge, counts in `msr record`'s status
/// line and makes the result `problems`; one without stays quiet, listed in `recording.json` and the recording log.
public enum CallToAction: Equatable, Sendable {
    case freeUpDiskSpace
    case grantThePermission
    case unplugAndPlugInAgain
    /// A file is incomplete.
    case reportIt
    /// Stop and start the recording again, or unplug and plug in the device again, and report it.
    case startAgainAndReportIt

    /// Whether it asks for a report: only then does the recording ask to report it once it ended (D84).
    public var includesReportIt: Bool { self == .reportIt || self == .startAgainAndReportIt }
}

extension ProblemKind {
    /// Its call to action, nil for none (D84).
    public var callToAction: CallToAction? {
        switch self {
        case .diskFull, .manifestNotWritten, .recordingLogNotWritten: .freeUpDiskSpace
        case .cameraPermissionMissing: .grantThePermission
        case .audioInputSilentAfterGaps: .unplugAndPlugInAgain
        case .audioFileLost, .videoFileLost: .reportIt
        case .screenNotCaptured, .cameraNotCaptured, .audioSourceFailed, .audioFileFailed, .audioInputNotRecordable,
             .audioInputChangesNotFollowed:
            .startAgainAndReportIt
        case .cameraStalled, .guideTracksCut, .dockIconNotShown, .inputVolumeNotSet,
             .inputVolumeNotFollowed, .screensNotRead, .audioInputsNotRead, .freeSpaceNotRead, .timelineFileNotWritten:
            nil
        }
    }

    /// A source that fails: its call to action only once it lasted `RecorderValues.unrecoveredAfter` without
    /// ending, as most come back by themselves (D84).
    var callsToActionOnlyUnrecovered: Bool {
        switch self {
        case .screenNotCaptured, .cameraNotCaptured, .audioSourceFailed, .audioFileFailed, .audioInputNotRecordable: true
        default: false
        }
    }
}

extension ProblemKind {
    /// A failure that ends with a new file of its source: a file's failure told after a newer file of its
    /// source started is over when told (D78).
    var endsWithANewFile: Bool {
        switch self {
        case .screenNotCaptured, .cameraNotCaptured, .audioFileFailed: true
        default: false
        }
    }

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
        case .audioInputSilentAfterGaps(let uid): source ?? uid
        }
    }
}

/// The problems a recording has told and the status window's lines: a told
/// problem goes into the recording manifest, which is written at once, unless
/// writing it is the problem; one of a kind that was told and has not ended
/// since is not told again. Some are only shown (`show`): the manifest lists
/// them already.
public struct ProblemsTold: Sendable {
    public enum Outcome: Equatable, Sendable {
        case tell(writeManifest: Bool)
        /// The same kind stands since it was told: nothing to do.
        case alreadyTold
        /// The manifest is finalized and changes no more: told only on
        /// standard error and in the unified log (D64).
        case afterTheEnd
    }

    /// How a problem ended (D78).
    public enum Ending: Sendable {
        /// Its source works again: frames come, a new file of it started, a read or a write works.
        case recovered
        /// Its source went away.
        case disconnected
        /// Its capture ended without recovering and without a disconnect: Stop, out of the camera mode,
        /// the camera suspended, or the capture ended by a failure.
        case stopped
    }

    /// A problem as told, with when it began and, once over, ended, in nanoseconds since the start.
    private struct Told: Sendable {
        var kind: ProblemKind
        var problem: RecordingProblem
        var source: String?
        var began: Int64
        var ended: Int64?
        var ending = Ending.recovered
        /// Told with `add`, not only shown: a tell of its kind waits for it to end.
        var isTold = false
        /// What its line says besides its source, for a kind whose line is its own (D81).
        var note: String?
        /// Its call to action was given (D84).
        var calledToAction = false
        /// None whatever its kind: a problem whose call to action another one gives, another screen's picture or
        /// the tail of a file a full disk cut short (D84).
        var withoutCallToAction = false
    }

    private var told: [Told] = []

    public init() {}

    /// Into the manifest and the window's lines, unless one of its kind told before has not ended; a line only
    /// shown does not keep it from the manifest. `source` names the screen or camera of a kind keyed by its ID;
    /// `endedAt`: already over when told, for a failure that ends with a new file (`endsWithANewFile`) after a
    /// newer file of its source started, or after its source went away (`ending`); `withoutCallToAction` for a
    /// problem whose call to action another one gives, such as a screen that showed another screen's picture or a
    /// file a full disk cut short (D84); a tell without it replaces a lasting line that has
    /// it, told or only shown, its wait starting then.
    public mutating func add(
        _ problem: RecordingProblem, kind: ProblemKind, source: String? = nil, note: String? = nil, endedAt: Int64? = nil,
        ending: Ending = .recovered, withoutCallToAction: Bool = false, to manifest: inout RecordingManifest
    ) -> Outcome {
        guard manifest.state != .finalized else { return .afterTheEnd }
        let lasting = told.lastIndex(where: { $0.kind == kind && $0.ended == nil })
        // A failure of its own after another screen's picture replaces that told line.
        if let lasting, told[lasting].isTold, !(told[lasting].withoutCallToAction && !withoutCallToAction) { return .alreadyTold }
        manifest.problems.append(problem)
        if let shown = lasting {
            told[shown].problem = problem
            told[shown].isTold = true
            if told[shown].withoutCallToAction && !withoutCallToAction {
                // A failure of its own after another screen's picture: its wait counts from now.
                told[shown].began = Int64((problem.at * 1_000_000_000).rounded())
            }
            told[shown].withoutCallToAction = withoutCallToAction
        } else {
            show(problem, kind: kind, source: source, endedAt: endedAt, ending: ending, withoutCallToAction: withoutCallToAction)
            told[told.count - 1].isTold = true
            told[told.count - 1].note = note
        }
        return .tell(writeManifest: kind != .manifestNotWritten)
    }

    /// Into the window's lines only, for a problem the manifest already lists (a video file's end); none while
    /// one of its kind lasts. `endedAt` as for `add`.
    public mutating func show(
        _ problem: RecordingProblem, kind: ProblemKind, source: String? = nil, endedAt: Int64? = nil, ending: Ending = .recovered,
        withoutCallToAction: Bool = false
    ) {
        guard !told.contains(where: { $0.kind == kind && $0.ended == nil }) else { return }
        let began = Int64((problem.at * 1_000_000_000).rounded())
        let ended = kind.endsWithANewFile ? endedAt.map { max($0, began) } : nil
        told.append(Told(
            kind: kind, problem: problem, source: source, began: began, ended: ended, ending: ending, withoutCallToAction: withoutCallToAction))
    }

    /// The kind went away at `now`: it is told again when it comes back.
    public mutating func cleared(_ kind: ProblemKind, at now: Int64, ending: Ending = .recovered) {
        guard let index = told.lastIndex(where: { $0.kind == kind && $0.ended == nil }) else { return }
        told[index].ended = now
        told[index].ending = ending
    }

    /// The problems whose call to action falls due at `now`, each given once (D84): at once, or for a source that
    /// fails once it lasted `unrecoveredAfter`, though it ended since; `atStop`, also once it is still failing.
    public mutating func callsToAction(
        now: Int64, unrecoveredAfter: Duration = RecorderValues.unrecoveredAfter, atStop: Bool = false
    ) -> [RecordingProblem] {
        var due: [RecordingProblem] = []
        for index in told.indices where !told[index].calledToAction && !told[index].withoutCallToAction && told[index].kind.callToAction != nil {
            let entry = told[index]
            let lasted = (entry.ended ?? now) - entry.began >= unrecoveredAfter.nanoseconds || (atStop && entry.ended == nil)
            if entry.kind.callsToActionOnlyUnrecovered, !lasted { continue }
            told[index].calledToAction = true
            due.append(entry.problem)
        }
        return due
    }

    /// When the next call to action of a failing source falls due, if it lasts that long (D84).
    public func nextCallToAction(unrecoveredAfter: Duration = RecorderValues.unrecoveredAfter) -> Int64? {
        told.filter { !$0.calledToAction && !$0.withoutCallToAction && $0.ended == nil && $0.kind.callsToActionOnlyUnrecovered }
            .map { $0.began + unrecoveredAfter.nanoseconds }.min()
    }

    /// The problems whose call to action was given and that have not ended: what the badge and `msr record`'s
    /// count show; once a problem ended, nothing is left to do (D84).
    public var callsToActionOngoing: [RecordingProblem] {
        told.filter { $0.calledToAction && $0.ended == nil }.map(\.problem)
    }

    /// A call to action was given: the recording's result is `problems` (D91).
    public var gaveACallToAction: Bool { told.contains(where: \.calledToAction) }

    /// A call to action given that includes "report it": the recording asks to report it once it ended (D84).
    public var asksToReportIt: Bool {
        told.contains { $0.calledToAction && $0.kind.callToAction?.includesReportIt == true }
    }

    /// The status window's lines, one per kind (a kind names its source), newest first, of the problems whose
    /// call to action was given: one without shows nothing (D78, D91).
    public func lines(now: Int64) -> [String] {
        let shown = told.filter(\.calledToAction)
        var kinds: [ProblemKind] = []
        for entry in shown.reversed() where !kinds.contains(entry.kind) { kinds.append(entry.kind) }
        return kinds.map { kind in Self.line(shown.filter { $0.kind == kind }, now: now) }
    }

    /// `<phrase> since 0:53`, `<phrase> for 7.4 s at 0:53, recovered` (or `, then disconnected`, `, stopped`: the `Ending`),
    /// `<phrase> 3 times, 12 s in total[, <ending>]`, then the latest error after a colon, `latest: ` before it
    /// when the errors differ; an input silent after its gaps has its own (`silentAfterGaps`).
    private static func line(_ repeats: [Told], now: Int64) -> String {
        let latest = repeats[repeats.count - 1]
        if case .audioInputSilentAfterGaps = latest.kind { return silentAfterGaps(latest, now: now) }
        let phrase = latest.kind.phrase(source: latest.source)
        let errors = repeats.map(\.problem.error)
        let why = latest.problem.error.map { ": " + (Set(errors).count > 1 ? "latest: " : "") + $0 } ?? ""
        let ending = text(latest.ending)
        let text = if repeats.count > 1 {
            "\(phrase) \(repeats.count) times, \(seconds(repeats.reduce(Int64(0)) { $0 + ($1.ended ?? now) - $1.began })) in total"
                + (latest.ended == nil ? "" : ", \(ending)")
        } else if let ended = latest.ended {
            "\(phrase) for \(seconds(ended - latest.began)) at \(time(latest.began)), \(ending)"
        } else {
            "\(phrase) since \(time(latest.began))"
        }
        return text + why
    }

    /// An input silent right after its gaps, the latest time: "Audio 3 BRIO sends only silence since its gaps at
    /// 0:25; unplug and plug it in again"; once over "Audio 3 BRIO sent only silence for 1:05 after its gaps
    /// at 0:25, recovered" (or the other `Ending`) (D81).
    private static func silentAfterGaps(_ latest: Told, now: Int64) -> String {
        let input = latest.kind.phrase(source: latest.source), gaps = latest.note ?? ""
        guard let ended = latest.ended else {
            return "\(input) sends only silence since its gaps at \(gaps); unplug and plug it in again"
        }
        return "\(input) sent only silence for \(seconds(ended - latest.began)) after its gaps at \(gaps), \(text(latest.ending))"
    }

    private static func text(_ ending: Ending) -> String {
        switch ending {
        case .recovered: "recovered"
        case .disconnected: "then disconnected"
        case .stopped: "stopped"
        }
    }

    /// The time of the first `audio input gap` of `noAudio`'s input from `silenceAfterGapsTime` before its
    /// zeros began (`noAudioTime` before it) up to it, in seconds; nil without one: no audio right after gaps (D81).
    public static func gapsBefore(_ noAudio: RecordingEvent, in events: [RecordingEvent]) -> Double? {
        let from = noAudio.at - Double(RecorderValues.noAudioTime.nanoseconds + RecorderValues.silenceAfterGapsTime.nanoseconds) / 1e9
        return events.filter { $0.event == .audioInputGap && $0.audioSource == noAudio.audioSource && (from...noAudio.at).contains($0.at) }
            .map(\.at).min()
    }

    /// "0:53" since the start, "1:02:03" from an hour on.
    public static func time(_ nanoseconds: Int64) -> String {
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
