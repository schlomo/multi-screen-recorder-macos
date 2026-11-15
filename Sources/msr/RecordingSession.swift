import AppKit
import CoreServices
import RecorderCore
import RecorderLogic

/// A running recording as the person sees it, in the app and for `msr
/// record` alike: the Dock icon's badge with the elapsed time, "!" and a
/// bouncing icon when something needs the person, and the status window
/// with the problems (D45, D46). `msr record` also says each event and
/// problem on standard error.
@MainActor
final class RecordingSession: RecorderObserver {
    private(set) var recorder: Recorder?
    private let tellOnStandardError: Bool
    private var status = RecordingStatus()
    private var badgeTask: Task<Void, Never>?
    private let statusWindow = StatusWindow()
    /// Stop is in progress: a Dock click or a quit does nothing more.
    private(set) var isStopping = false

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
        isStopping = true
        badgeTask?.cancel()
        statusWindow.close()
        guard let recorder else { return nil }
        let summary = await recorder.stop()
        NSApp.dockTile.badgeLabel = nil
        return summary
    }

    /// Opens the status window; its Stop calls `onStop`.
    func showStatus(onStop: @escaping () -> Void) {
        guard !isStopping else { return }
        refreshStatusWindow()
        statusWindow.show(onStop: onStop)
    }

    private func updateBadge() {
        guard let recorder, !isStopping else { return }
        NSApp.dockTile.badgeLabel = status.badge(elapsedSeconds: recorder.elapsedSeconds)
        if statusWindow.isOpen { refreshStatusWindow() }
    }

    private func refreshStatusWindow() {
        guard let recorder else { return }
        let (rows, line) = recorder.status()
        statusWindow.model.rows = rows
        statusWindow.model.line = line
        statusWindow.model.problems = status.problems
    }

    private func needsAttention() {
        NSApp.requestUserAttention(.criticalRequest)
        updateBadge()
    }

    func recorder(_ recorder: Recorder, lowDiskSpace: Bool) {
        status.isLowOnDisk = lowDiskSpace
        if lowDiskSpace { needsAttention() } else { updateBadge() }
    }

    func recorder(_ recorder: Recorder, displayShowsAnotherDisplaysPicture display: String?) {
        status.displayShowingAnotherDisplaysPicture = display
        if let display, tellOnStandardError {
            standardError("The display \(display) shows another display's picture: its display file ended,"
                + " and it is recorded again after its next change.")
        }
        updateBadge()
    }

    func recorder(_ recorder: Recorder, eventLine: String) {
        if tellOnStandardError { standardError(eventLine) }
    }

    func recorder(_ recorder: Recorder, problem: RecordingProblem) {
        if tellOnStandardError { standardError(problem.text) }
        status.problems.append(problem.text)
        needsAttention()
    }
}

/// Whether a quit comes from logout, restart or shutdown, by the quit Apple
/// event's reason (`kAEQuitReason`): those finalize without asking.
func quitEndsTheSession(reason: OSType?) -> Bool {
    guard let reason else { return false }
    let endingTheSession = [kAELogOut, kAEReallyLogOut, kAEShowRestartDialog, kAEShowShutdownDialog, kAERestart, kAEShutDown]
    return endingTheSession.contains { OSType($0) == reason }
}

/// What a quit does while a recording runs.
enum QuitDecision: Equatable {
    /// Open the status window, whose Stop ends the recording.
    case showStatus
    /// Logout, restart or shutdown: finalize, then quit.
    case finalizeWithoutAsking
    /// Logout, restart or shutdown while Stop is in progress: quit once it is done.
    case waitForTheStop
    /// A quit while Stop is in progress: Stop quits anyway.
    case ignore

    init(isStopping: Bool, endsTheSession: Bool) {
        self = switch (isStopping, endsTheSession) {
        case (false, false): .showStatus
        case (false, true): .finalizeWithoutAsking
        case (true, true): .waitForTheStop
        case (true, false): .ignore
        }
    }
}

/// The reason of the quit Apple event being handled now, if any.
@MainActor
func currentQuitReason() -> OSType? {
    NSAppleEventManager.shared().currentAppleEvent?
        .attributeDescriptor(forKeyword: AEKeyword(kAEQuitReason))?.enumCodeValue
}

func standardError(_ line: String) {
    FileHandle.standardError.write(Data("\(line)\n".utf8))
}
