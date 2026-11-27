import Foundation
import RecorderCore

/// Where each text of `msr record` goes: standard output carries the
/// recording folder's path and nothing else; everything for people goes
/// to standard error through the one writer; `--quiet` leaves out all of
/// it but the errors, the problems whose call to action was given and the
/// summary that asks for attention (D91). A failure is told once: by its
/// event's line, or by its problem when no event tells it (D65).
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
        /// A failure event's line, or the count of its repeats.
        case failureEvent
        case problem
        /// A problem whose failure event's line tells it: not printed.
        case problemOfAnEvent
        /// A problem's call to action, given: its own line only with `--quiet`, where its problem's is not (D91).
        case callToAction
        case summary
        /// The summary of a run that exits 3 or asks to report it: `--quiet` still tells it.
        case summaryAlwaysTold
        case error

        static func readyCheck(isReady: Bool) -> Kind { isReady ? .readyCheckPassed : .readyCheckFailed }

        static func summary(endedWithError: Bool, asksToReportIt: Bool) -> Kind {
            endedWithError || asksToReportIt ? .summaryAlwaysTold : .summary
        }
    }

    enum Destination: Equatable {
        case standardOutput
        case standardError
        case nowhere
    }

    let quiet: Bool
    private let standardOutput: (String) -> Void
    private let standardError: StandardErrorWriter

    /// For `msr record`: `--quiet` as given, standard output and standard error as the process's.
    init(
        record: CommandLineInterface.Record,
        standardOutput: @escaping (String) -> Void = { print($0); fflush(stdout) },
        standardError: StandardErrorWriter = .shared
    ) {
        self.init(quiet: record.quiet, standardOutput: standardOutput, standardError: standardError)
    }

    init(quiet: Bool, standardOutput: @escaping (String) -> Void, standardError: StandardErrorWriter) {
        self.quiet = quiet
        self.standardOutput = standardOutput
        self.standardError = standardError
    }

    func destination(of kind: Kind) -> Destination {
        switch kind {
        case .recordingFolder: .standardOutput
        case .readyCheckFailed, .summaryAlwaysTold, .error: .standardError
        case .problemOfAnEvent: .nowhere
        case .callToAction: quiet ? .standardError : .nowhere
        case .banner, .whatWillBeRecorded, .readyCheckPassed, .recordingFolderNotice, .stopMessage, .event, .failureEvent, .problem,
             .summary:
            quiet ? .nowhere : .standardError
        }
    }

    /// The text with its newlines, where its kind goes.
    func tell(_ kind: Kind, _ text: String) {
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
