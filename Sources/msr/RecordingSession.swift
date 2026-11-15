import AppKit
import RecorderCore
import RecorderLogic

/// A running recording as the person sees it, in the app and for `msr
/// record` alike: the Dock icon's badge with the elapsed minutes, "!" for
/// low disk space or a display showing another display's picture, and the
/// question "Stop recording?" (D45).
@MainActor
final class RecordingSession: RecorderObserver {
    private(set) var recorder: Recorder?
    private let tellOnStandardError: Bool
    private var isLowOnDisk = false
    private var displayShowingAnother: String?
    private var badgeTask: Task<Void, Never>?

    /// Starts the recording; `tellOnStandardError` for `msr record`.
    init(settings: Settings, homeFolder: URL, tellOnStandardError: Bool) throws(RecorderStartError) {
        self.tellOnStandardError = tellOnStandardError
        recorder = try Recorder(
            settings: settings, homeFolder: homeFolder, app: "Multi Screen Recorder \(runningVersion)", observer: self)
        updateBadge()
        badgeTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                self?.updateBadge()
            }
        }
    }

    var folder: URL? { recorder?.folder }

    /// Ends the recording; the summary of what it wrote.
    func stop() async -> RecordingSummary? {
        badgeTask?.cancel()
        guard let recorder else { return nil }
        let summary = await recorder.stop()
        NSApp.dockTile.badgeLabel = nil
        return summary
    }

    /// Asks "Stop recording?"; true for Stop.
    static func askToStop() -> Bool {
        let alert = NSAlert()
        alert.messageText = "Stop recording?"
        alert.addButton(withTitle: "Stop")
        alert.addButton(withTitle: "Continue")
        NSApp.activate()
        return alert.runModal() == .alertFirstButtonReturn
    }

    private func updateBadge() {
        guard let recorder else { return }
        NSApp.dockTile.badgeLabel = isLowOnDisk || displayShowingAnother != nil
            ? "!" : String(Int(recorder.elapsedSeconds / 60))
    }

    func recorder(_ recorder: Recorder, lowDiskSpace: Bool) {
        isLowOnDisk = lowDiskSpace
        if lowDiskSpace { NSApp.requestUserAttention(.criticalRequest) }
        updateBadge()
    }

    func recorder(_ recorder: Recorder, displayShowsAnotherDisplaysPicture display: String?) {
        displayShowingAnother = display
        if let display, tellOnStandardError {
            standardError("The display \(display) shows another display's picture: its display file ended,"
                + " and it is recorded again after its next change.")
        }
        updateBadge()
    }

    func recorder(_ recorder: Recorder, problem: String) {
        standardError(problem)
    }
}

func standardError(_ line: String) {
    FileHandle.standardError.write(Data("\(line)\n".utf8))
}
