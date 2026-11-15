import RecorderLogic

/// What a display file's end, or the end of a capture that started none,
/// tells: the event `display file writer failed` when the reason the
/// capture ended does not already give one, and the problem for the person
/// (the Dock badge's "!", "Stop recording?", and standard error in `msr
/// record`). A failing writer and a full disk are always a problem, file or
/// no file.
struct FileEndReport: Equatable {
    var event: RecordingEvent?
    var problem: String?

    /// Nothing to tell.
    init() {}

    /// `reason` is nil when the recorder stopped the capture.
    init(reason: DisplayTracker.StreamEnd?, end: DisplayFileEnd?, display: String) {
        let reasonError: String? = switch reason {
        case .writerFailed(let error): error
        case .diskFull: "the disk is full"
        case .streamFailed, .writerFellBehind, .showsAnotherDisplay, nil: nil
        }
        if let end, let error = end.error {
            problem = "Display file \(end.file.name): \(error)"
            if reasonError == nil {
                var failed = RecordingEvent(at: 0, event: .displayFileWriterFailed, display: end.file.display)
                failed.at = end.file.end ?? end.file.start
                failed.error = error
                event = failed
            }
        } else if let reasonError {
            problem = "Display \(display): \(reasonError)"
        }
    }
}

/// Tells each capture's end once: a capture that ends by itself while the
/// recorder stops it reports its end on both paths.
struct CaptureEndReports {
    private var told: Set<Int> = []

    /// What to tell for this end of capture `captureNumber`, nil when there is nothing or it was told.
    mutating func report(
        captureNumber: Int, reason: DisplayTracker.StreamEnd?, end: DisplayFileEnd?, display: String
    ) -> FileEndReport? {
        let report = FileEndReport(reason: reason, end: end, display: display)
        guard report != FileEndReport(), told.insert(captureNumber).inserted else { return nil }
        return report
    }
}
