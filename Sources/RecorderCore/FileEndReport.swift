import RecorderLogic

/// What a display file's end, or the end of a capture that started none,
/// tells: its event (`display file writer failed` or `disk full`), and
/// the problem for the person. A failing writer and a full disk are always
/// a problem, file or no file. The tracker writes neither event: this is
/// the one place.
struct FileEndReport: Equatable {
    var event: RecordingEvent?
    var problem: RecordingProblem?

    /// `reason` is nil when the recorder stopped the capture; `now` is the
    /// time on the shared clock, the time of the report when no file ended.
    init(reason: DisplayTracker.StreamEnd?, end: DisplayFileEnd?, display: String, at now: Int64) {
        let reasonError: String? = switch reason {
        case .writerFailed(let error): error
        case .diskFull: "the disk is full"
        case .streamFailed, .captureSourceGone, .writerFellBehind, .showsAnotherDisplay, nil: nil
        }
        let fileError = end?.error
        guard let error = fileError?.description ?? reasonError else { return }
        let time = end.map { Int64((($0.file.end ?? $0.file.start) * 1_000_000_000).rounded()) } ?? now
        let what = if let end, fileError != nil { "Display file \(end.file.name)" } else { "Display \(display)" }
        problem = RecordingProblem(at: time, problem: what, error: error)
        let isDiskFull = reason == .diskFull || fileError?.isDiskFull == true
        var event = RecordingEvent(at: time, event: isDiskFull ? .diskFull : .displayFileWriterFailed, display: display)
        if !isDiskFull { event.error = error }
        self.event = event
    }
}

/// Each capture's end into the recording manifest, its event and problem
/// once: a capture that ends by itself while the recorder stops it reports
/// its end on both paths.
struct CaptureEndReports {
    private var told: Set<Int> = []

    /// Updates the file's entry, adds the event and the problem of this
    /// end of capture `captureNumber` unless it was told; the problem to
    /// tell the person, if any.
    mutating func record(
        captureNumber: Int, reason: DisplayTracker.StreamEnd?, end: DisplayFileEnd?, display: String, at now: Int64,
        into manifest: inout RecordingManifest
    ) -> RecordingProblem? {
        if let end {
            if let index = manifest.files.firstIndex(where: { $0.name == end.file.name }) {
                manifest.files[index] = end.file
            } else {
                manifest.files.append(end.file)
            }
        }
        let report = FileEndReport(reason: reason, end: end, display: display, at: now)
        guard report.event != nil || report.problem != nil, told.insert(captureNumber).inserted else { return nil }
        if let event = report.event { manifest.events.append(event) }
        if let problem = report.problem { manifest.problems.append(problem) }
        return report.problem
    }
}
