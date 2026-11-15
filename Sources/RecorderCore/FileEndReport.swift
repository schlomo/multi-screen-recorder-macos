import RecorderLogic

/// What a display file's end, or the end of a capture that started none,
/// tells: its event (`display file writer failed` or `disk full`), and
/// the problem for the person (the Dock badge's "!", "Stop recording?",
/// and standard error in `msr record`). A failing writer and a full disk
/// are always a problem, file or no file. The tracker writes neither
/// event: this is the one place.
struct FileEndReport: Equatable {
    var event: RecordingEvent?
    var problem: String?

    /// Nothing to tell.
    init() {}

    /// `reason` is nil when the recorder stopped the capture; `now` is the
    /// time on the shared clock, the event's time when no file ended.
    init(reason: DisplayTracker.StreamEnd?, end: DisplayFileEnd?, display: String, at now: Int64) {
        let reasonError: String? = switch reason {
        case .writerFailed(let error): error
        case .diskFull: "the disk is full"
        case .streamFailed, .writerFellBehind, .showsAnotherDisplay, nil: nil
        }
        let fileError = end?.error
        guard let error = fileError ?? reasonError else { return }
        problem = if let end, let fileError { "Display file \(end.file.name): \(fileError)" } else { "Display \(display): \(error)" }
        let time = end.map { Int64((($0.file.end ?? $0.file.start) * 1_000_000_000).rounded()) } ?? now
        var event = RecordingEvent(at: time, event: reason == .diskFull ? .diskFull : .displayFileWriterFailed, display: display)
        if event.event == .displayFileWriterFailed { event.error = error }
        self.event = event
    }
}

/// Tells each capture's end once: a capture that ends by itself while the
/// recorder stops it reports its end on both paths.
struct CaptureEndReports {
    private var told: Set<Int> = []

    /// What to tell for this end of capture `captureNumber`, nil when there is nothing or it was told.
    mutating func report(
        captureNumber: Int, reason: DisplayTracker.StreamEnd?, end: DisplayFileEnd?, display: String, at now: Int64
    ) -> FileEndReport? {
        let report = FileEndReport(reason: reason, end: end, display: display, at: now)
        guard report != FileEndReport(), told.insert(captureNumber).inserted else { return nil }
        return report
    }
}
