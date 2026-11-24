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
    /// An audio input, by its UID, whose file is out of the "Audio inputs" guide track, `source` naming the
    /// input and the note its offset; ends when it rejoins, its file ends or it disconnects (D79).
    case audioInputOutOfTheGuideTrack(String)
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
             .guideTracksCut, .audioInputOutOfTheGuideTrack:
            false
        case .diskFull, .cameraPermissionMissing, .screenNotCaptured, .cameraNotCaptured, .audioSourceFailed, .audioFileFailed,
             .recordingLogNotWritten, .manifestNotWritten, .freeSpaceNotRead, .screensNotRead, .audioInputsNotRead,
             .audioInputSilentAfterGaps:
            ongoing
        }
    }
}

/// What a person has to do about a problem (D84, the owner's rule): only a problem with one bounces the Dock
/// icon, sets the badge and counts in `msr record`'s status line; one without stays quiet, listed in the status
/// window, `recording.json` and the recording log.
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
        case .diskFull, .manifestNotWritten, .timelineFileNotWritten, .recordingLogNotWritten: .freeUpDiskSpace
        case .cameraPermissionMissing: .grantThePermission
        case .audioInputSilentAfterGaps: .unplugAndPlugInAgain
        case .audioFileLost, .videoFileLost: .reportIt
        case .screenNotCaptured, .cameraNotCaptured, .audioSourceFailed, .audioFileFailed, .audioInputNotRecordable,
             .audioInputChangesNotFollowed:
            .startAgainAndReportIt
        case .cameraStalled, .audioInputOutOfTheGuideTrack, .guideTracksCut, .dockIconNotShown, .inputVolumeNotSet,
             .inputVolumeNotFollowed, .screensNotRead, .audioInputsNotRead, .freeSpaceNotRead:
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
        case .audioInputOutOfTheGuideTrack(let uid), .audioInputSilentAfterGaps(let uid): source ?? uid
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
        /// What its line says besides its source, for a kind whose line is its own (D79).
        var note: String?
        /// Its call to action was given (D84).
        var calledToAction = false
    }

    private var told: [Told] = []

    public init() {}

    /// Into the manifest and the window's lines, unless one of its kind told before has not ended; a line only
    /// shown does not keep it from the manifest. `source` names the screen or camera of a kind keyed by its ID;
    /// `endedAt`: already over when told, for a failure that ends with a new file (`endsWithANewFile`) after a
    /// newer file of its source started, or after its source went away (`ending`).
    public mutating func add(
        _ problem: RecordingProblem, kind: ProblemKind, source: String? = nil, note: String? = nil, endedAt: Int64? = nil,
        ending: Ending = .recovered, to manifest: inout RecordingManifest
    ) -> Outcome {
        guard manifest.state != .finalized else { return .afterTheEnd }
        guard !told.contains(where: { $0.kind == kind && $0.ended == nil && $0.isTold }) else { return .alreadyTold }
        manifest.problems.append(problem)
        if let shown = told.lastIndex(where: { $0.kind == kind && $0.ended == nil }) {
            told[shown].problem = problem
            told[shown].isTold = true
        } else {
            show(problem, kind: kind, source: source, endedAt: endedAt, ending: ending)
            told[told.count - 1].isTold = true
            told[told.count - 1].note = note
        }
        return .tell(writeManifest: kind != .manifestNotWritten)
    }

    /// Into the window's lines only, for a problem the manifest already lists (a video file's end); none while
    /// one of its kind lasts. `endedAt` as for `add`.
    public mutating func show(
        _ problem: RecordingProblem, kind: ProblemKind, source: String? = nil, endedAt: Int64? = nil, ending: Ending = .recovered
    ) {
        guard !told.contains(where: { $0.kind == kind && $0.ended == nil }) else { return }
        let at = Int64((problem.at * 1_000_000_000).rounded())
        // A stall is told once the camera delivered no frame for the stall limit: it began that much earlier.
        let began = if case .cameraStalled = kind { max(0, at - RecorderValues.cameraStallLimit.nanoseconds) } else { at }
        let ended = kind.endsWithANewFile ? endedAt.map { max($0, began) } : nil
        told.append(Told(kind: kind, problem: problem, source: source, began: began, ended: ended, ending: ending))
    }

    /// The kind went away at `now`: it is told again when it comes back. A
    /// stall's `length` says when it began (its end minus its length).
    public mutating func cleared(_ kind: ProblemKind, at now: Int64, length: Int64? = nil, ending: Ending = .recovered) {
        guard let index = told.lastIndex(where: { $0.kind == kind && $0.ended == nil }) else { return }
        told[index].ended = now
        told[index].ending = ending
        if let length { told[index].began = max(0, now - length) }
    }

    /// The problems whose call to action falls due at `now`, each given once (D84): at once, or for a source that
    /// fails once it lasted `unrecoveredAfter` without ending.
    public mutating func callsToAction(now: Int64, unrecoveredAfter: Duration = RecorderValues.unrecoveredAfter) -> [RecordingProblem] {
        var due: [RecordingProblem] = []
        for index in told.indices where !told[index].calledToAction && told[index].kind.callToAction != nil {
            let entry = told[index]
            if entry.kind.callsToActionOnlyUnrecovered, entry.ended != nil || now - entry.began < unrecoveredAfter.nanoseconds { continue }
            told[index].calledToAction = true
            due.append(entry.problem)
        }
        return due
    }

    /// When the next call to action of a failing source falls due, if it lasts that long (D84).
    public func nextCallToAction(unrecoveredAfter: Duration = RecorderValues.unrecoveredAfter) -> Int64? {
        told.filter { !$0.calledToAction && $0.ended == nil && $0.kind.callsToActionOnlyUnrecovered }
            .map { $0.began + unrecoveredAfter.nanoseconds }.min()
    }

    /// A call to action given that includes "report it": the recording asks to report it once it ended (D84).
    public var asksToReportIt: Bool {
        told.contains { $0.calledToAction && $0.kind.callToAction?.includesReportIt == true }
    }

    /// The status window's lines, one per kind (a kind names its source): red first, then
    /// orange, each newest first (D78).
    public func lines(now: Int64) -> [ProblemLine] {
        var kinds: [ProblemKind] = []
        for entry in told.reversed() where !kinds.contains(entry.kind) { kinds.append(entry.kind) }
        let lines = kinds.map { kind in Self.line(told.filter { $0.kind == kind }, now: now) }
        return lines.filter(\.isRed) + lines.filter { !$0.isRed }
    }

    /// `<phrase> since 0:53`, `<phrase> for 7.4 s at 0:53, recovered` (or `, then disconnected`, `, stopped`: the `Ending`),
    /// `<phrase> 3 times, 12 s in total[, <ending>]`, then the latest error after a colon, `latest: ` before it
    /// when the errors differ; a stall reads `stalled 7.4 s`, without its error, always the same; an input out of
    /// the guide track has its own (`outOfTheGuideTrack`).
    private static func line(_ repeats: [Told], now: Int64) -> ProblemLine {
        let latest = repeats[repeats.count - 1]
        if case .audioInputOutOfTheGuideTrack = latest.kind { return outOfTheGuideTrack(latest) }
        if case .audioInputSilentAfterGaps = latest.kind { return silentAfterGaps(latest, now: now) }
        let isStall = if case .cameraStalled = latest.kind { true } else { false }
        let phrase = latest.kind.phrase(source: latest.source)
        let errors = repeats.map(\.problem.error)
        let why = isStall ? "" : latest.problem.error.map { ": " + (Set(errors).count > 1 ? "latest: " : "") + $0 } ?? ""
        let ending = text(latest.ending)
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

    /// An input out of the guide track, the latest time, orange: "Audio 2 Mic A 553 ms late, not in the guide track;
    /// its own audio track is recorded", once over "Audio 2 Mic A was not in the guide track from 0:50 to 1:40 (553 ms
    /// late); its own audio track is recorded" (D79).
    private static func outOfTheGuideTrack(_ latest: Told) -> ProblemLine {
        let input = latest.kind.phrase(source: latest.source), note = latest.note ?? ""
        let text = if let ended = latest.ended {
            "\(input) was not in the guide track from \(time(latest.began)) to \(time(ended)) (\(note)); its own audio track is recorded"
        } else {
            "\(input) \(note), not in the guide track; its own audio track is recorded"
        }
        return ProblemLine(text: text, isRed: false)
    }

    /// An input silent right after its gaps, the latest time: "Audio 3 BRIO sends only silence since its gaps at
    /// 0:25; unplug and plug it in again", red; once over "Audio 3 BRIO sent only silence for 1:05 after its gaps
    /// at 0:25, recovered" (or the other `Ending`), orange (D81).
    private static func silentAfterGaps(_ latest: Told, now: Int64) -> ProblemLine {
        let input = latest.kind.phrase(source: latest.source), gaps = latest.note ?? ""
        guard let ended = latest.ended else {
            return ProblemLine(text: "\(input) sends only silence since its gaps at \(gaps); unplug and plug it in again", isRed: true)
        }
        return ProblemLine(
            text: "\(input) sent only silence for \(seconds(ended - latest.began)) after its gaps at \(gaps), \(text(latest.ending))",
            isRed: false)
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
