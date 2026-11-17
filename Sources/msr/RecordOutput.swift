import RecorderCore

/// Where each text of `msr record` goes: standard output carries the
/// recording folder's path and nothing else; everything for people goes
/// to standard error through the one writer; `--quiet` leaves out all of
/// it but the failures and the problems.
struct RecordOutput {
    enum Kind: CaseIterable {
        /// The recording folder's path, when recording starts.
        case recordingFolder
        case banner
        case whatWillBeRecorded
        case readyCheckPassed
        case readyCheckFailed
        case recordingFolderNotice
        case stopMessage
        case event
        case problem
        case summary
        /// The summary of a run that exits 3.
        case summaryOfFailedRun
        case error
    }

    enum Destination: Equatable {
        case standardOutput
        case standardError
        case nowhere
    }

    let quiet: Bool
    private let standardOutput: (String) -> Void
    private let standardError: StandardErrorWriter

    init(quiet: Bool, standardOutput: @escaping (String) -> Void, standardError: StandardErrorWriter) {
        self.quiet = quiet
        self.standardOutput = standardOutput
        self.standardError = standardError
    }

    func destination(of kind: Kind) -> Destination {
        switch kind {
        case .recordingFolder: .standardOutput
        case .readyCheckFailed, .problem, .summaryOfFailedRun, .error: .standardError
        case .banner, .whatWillBeRecorded, .readyCheckPassed, .recordingFolderNotice, .stopMessage, .event, .summary:
            quiet ? .nowhere : .standardError
        }
    }

    /// The text with its newlines, where its kind goes.
    func say(_ kind: Kind, _ text: String) {
        switch destination(of: kind) {
        case .standardOutput: standardOutput(text)
        case .standardError: standardError.write(text)
        case .nowhere: break
        }
    }

    /// Draws the status line once a second while recording, on a terminal and not `--quiet`.
    func drawStatusLine(isStopping: Bool, text: () -> String) {
        guard !quiet, !isStopping, standardError.drawsStatusLine else { return }
        standardError.showStatusLine(text())
    }

    func endStatusLine() {
        standardError.endStatusLine()
    }
}
