import RecorderLogic

/// What a video file's end, or the end of a capture that started none,
/// tells: its event (`screen file writer failed`, `camera file writer
/// failed` or `disk full`), and the problem for the person. A failing writer and a full disk are always
/// a problem, file or no file. The tracker writes neither event: this is
/// the one place.
struct FileEndReport: Equatable {
    var event: RecordingEvent?
    var problem: RecordingProblem?
    /// What a failed file lacks of what its writer was given (D66); a problem of its own.
    var lostProblem: RecordingProblem?

    /// The problem's text for guide tracks that end before the video.
    static func guideTracksCut(_ cuts: [GuideTrackCut]) -> String {
        cuts.map { cut in
            let why = switch cut.why {
            case .samplesGone: "the samples of its last mix were no longer there"
            case .writerTimedOut: "the writer did not take its last samples in time"
            }
            return "the guide track \"\(cut.guide.name)\" ends before the video: \(why)"
        }.joined(separator: "; ")
    }

    /// `reason` is nil when the recorder stopped the capture; `now` is the
    /// time on the shared clock, the time of the report when no file ended;
    /// `source` is the screen's or the camera's name.
    init<File>(reason: VideoStreamEnd?, end: VideoFileEnd<File>?, source: String, at now: Int64) {
        let word = File.sourceWord
        let reasonError: ErrorDetail? = switch reason {
        case .writerFailed(let error): error
        case .diskFull: "the disk is full"
        case .streamFailed, .captureSourceGone, .writerFellBehind, .showsAnotherScreen, nil: nil
        }
        let fileError = end?.error
        guard let error = fileError?.detail ?? reasonError else {
            if let end, !end.guideTracksCut.isEmpty {
                problem = RecordingProblem(
                    at: Int64((end.failureSeconds * 1_000_000_000).rounded()), problem: "\(word) file \(end.file.name)",
                    error: ErrorDetail(message: Self.guideTracksCut(end.guideTracksCut)))
            }
            return
        }
        let time = end.map { Int64(($0.failureSeconds * 1_000_000_000).rounded()) } ?? now
        let what = if let end, fileError != nil { "\(word) file \(end.file.name)" } else { "\(word) \(source)" }
        problem = RecordingProblem(at: time, problem: what, error: error)
        if let end, let lost = end.lost {
            lostProblem = RecordingProblem(at: time, problem: "\(word) file \(end.file.name)", error: ErrorDetail(message: lost))
        }
        let isDiskFull = reason == .diskFull || fileError?.isDiskFull == true
        var event = RecordingEvent(at: time, event: isDiskFull ? .diskFull : File.writerFailedEvent)
        event[keyPath: File.eventSubject] = source
        if !isDiskFull { event.errorDetail = error }
        self.event = event
    }
}

/// Each capture's end into the recording manifest, its event and problem
/// once: a capture that ends by itself while the recorder stops it reports
/// its end on both paths.
struct CaptureEndReports {
    private var told: Set<Int> = []

    /// Updates the file's entry, adds the event and the problem of this
    /// end of capture `captureNumber` unless it was told; the report to
    /// tell, if any: its problem for the person, told by its event when it
    /// has one (D65).
    mutating func record<File>(
        captureNumber: Int, reason: VideoStreamEnd?, end: VideoFileEnd<File>?, source: String, at now: Int64,
        into manifest: inout RecordingManifest
    ) -> FileEndReport? {
        if let end {
            if let index = manifest[keyPath: File.manifestFiles].firstIndex(where: { $0.name == end.file.name }) {
                manifest[keyPath: File.manifestFiles][index] = end.file
            } else {
                manifest[keyPath: File.manifestFiles].append(end.file)
            }
        }
        let report = FileEndReport(reason: reason, end: end, source: source, at: now)
        guard report.event != nil || report.problem != nil, told.insert(captureNumber).inserted else { return nil }
        if let event = report.event { manifest.events.append(event) }
        if let problem = report.problem { manifest.problems.append(problem) }
        if let lost = report.lostProblem { manifest.problems.append(lost) }
        return report
    }
}
