import AppKit
import CoreServices
import RecorderCore
import RecorderLogic

/// A running recording as the person sees it, in the app and for `msr
/// record` alike: the Dock icon's badge with the elapsed minutes, "!" and a
/// bouncing icon when something needs the person, and the question "Stop
/// recording?" listing the problems (D45). `msr record` also says each on
/// standard error.
@MainActor
final class RecordingSession: RecorderObserver {
    private(set) var recorder: Recorder?
    private let tellOnStandardError: Bool
    private var status = RecordingStatus()
    private var badgeTask: Task<Void, Never>?
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
        guard let recorder else { return nil }
        let summary = await recorder.stop()
        NSApp.dockTile.badgeLabel = nil
        return summary
    }

    /// Asks "Stop recording?", listing the problems; true for Stop.
    func askToStop() -> Bool {
        let alert = NSAlert()
        alert.messageText = "Stop recording?"
        if let details = status.stopQuestionDetails { alert.informativeText = details }
        alert.addButton(withTitle: "Stop")
        alert.addButton(withTitle: "Continue")
        NSApp.activate()
        return alert.runModal() == .alertFirstButtonReturn
    }

    private func updateBadge() {
        guard let recorder, !isStopping else { return }
        NSApp.dockTile.badgeLabel = status.badge(elapsedSeconds: recorder.elapsedSeconds)
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

    func recorder(_ recorder: Recorder, problem: String) {
        if tellOnStandardError { standardError(problem) }
        status.problems.append(problem)
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
    /// Ask "Stop recording?".
    case ask
    /// Logout, restart or shutdown: finalize, then quit.
    case finalizeWithoutAsking
    /// Logout, restart or shutdown while Stop is in progress: quit once it is done.
    case waitForTheStop
    /// A quit while Stop is in progress: Stop quits anyway.
    case ignore

    init(isStopping: Bool, endsTheSession: Bool) {
        self = switch (isStopping, endsTheSession) {
        case (false, false): .ask
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
