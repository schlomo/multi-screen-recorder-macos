import AppKit
import CoreServices
import RecorderCore
import RecorderLogic

/// A running recording as the person sees it, in the app and for `msr
/// record` alike: the Dock icon's badge "!" and a bouncing icon when
/// something needs the person, and the status window with the problems
/// (D45, D46, D47). `msr record` also tells each event and
/// problem as `RecordOutput` decides and, on a terminal, draws the status line.
@MainActor
final class RecordingSession: RecorderObserver {
    private(set) var recorder: Recorder?
    private let output: RecordOutput?
    private var status = RecordingStatus()
    private var badgeTask: Task<Void, Never>?
    private let statusWindow = StatusWindow()
    /// Stop is in progress: a Dock click or a quit does nothing more.
    private(set) var isStopping = false
    private let homeFolder: URL
    /// Why the state file does not remember this recording, if it does not.
    private(set) var notRemembered: StateFileError?

    /// Starts the recording, the ready check's facts for its recording log; `output` for `msr record`.
    init(
        settings: Settings, homeFolder: URL, readyCheckFacts: ReadyCheckFacts, output: RecordOutput?
    ) throws(RecorderStartError) {
        self.output = output
        self.homeFolder = homeFolder
        recorder = try Recorder(
            settings: settings, homeFolder: homeFolder, app: "Multi Screen Recorder \(runningVersion)",
            readyCheckFacts: readyCheckFacts, observer: self)
        updateBadge()
        badgeTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                self?.updateBadge()
                self?.drawStatusLine()
            }
        }
    }

    var folder: URL? { recorder?.folder }

    /// Ends the recording and remembers it in the state file; the summary of what it wrote.
    func stop() async -> RecordingSummary? {
        isStopping = true
        badgeTask?.cancel()
        output?.endStatusLine()
        statusWindow.close()
        guard let recorder else { return nil }
        let summary = await recorder.stop()
        NSApp.dockTile.badgeLabel = nil
        remember(summary)
        return summary
    }

    /// The state file remembers the recording and how it ended, for the app's next start to offer a report (D64).
    private func remember(_ summary: RecordingSummary) {
        do {
            try StateFile(homeFolder: homeFolder).update {
                $0.recorded(folder: summary.recordingFolder, result: summary.endedWithError ? .problems : .ok)
            }
        } catch {
            notRemembered = error
            RecorderLog.error("The recording is not remembered: \(ErrorDetail(error).text)", category: "state")
            output?.tell(.error, "Error: \(ErrorDetail(error).text)\n")
        }
    }

    /// Opens the status window; its Stop calls `onStop`.
    func showStatus(onStop: @escaping () -> Void) {
        guard !isStopping else { return }
        refreshStatusWindow()
        statusWindow.show(onStop: onStop)
    }

    private func updateBadge() {
        guard recorder != nil, !isStopping else { return }
        NSApp.dockTile.badgeLabel = status.badge
        if statusWindow.isOpen { refreshStatusWindow() }
    }

    private func drawStatusLine() {
        guard let recorder else { return }
        output?.drawStatusLine(isStopping: isStopping) {
            let (rows, line, cpu) = recorder.status()
            return StatusLine.text(line: line, cpu: cpu, rows: rows, status: status)
        }
    }

    private func refreshStatusWindow() {
        guard let recorder else { return }
        let (rows, line, cpu) = recorder.status()
        statusWindow.model.rows = rows
        statusWindow.model.line = line
        statusWindow.model.cpu = cpu ?? ""

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

    func recorder(_ recorder: Recorder, screenShowsAnotherScreensPicture screen: String?) {
        status.screenShowingAnotherScreensPicture = screen
        if let screen {
            output?.tell(.event, "The screen \(screen) shows another screen's picture: its screen file ended,"
                + " and it is recorded again after its next change.\n")
        }
        updateBadge()
    }

    func recorder(_ recorder: Recorder, eventLine: String) {
        output?.tell(.event, eventLine + "\n")
    }

    func recorder(_ recorder: Recorder, problem: RecordingProblem) {
        output?.tell(.problem, problem.text + "\n")
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
