import AppKit
import RecorderLogic

/// Where Report a problem opens things: the browser and Finder.
@MainActor
protocol ReportOpener {
    /// Whether the browser took the link.
    func open(_ url: URL) -> Bool
    func reveal(_ files: [URL])
}

@MainActor
struct Workspace: ReportOpener {
    func open(_ url: URL) -> Bool { NSWorkspace.shared.open(url) }
    func reveal(_ files: [URL]) { NSWorkspace.shared.activateFileViewerSelecting(files) }
}

/// Report a problem in the notice of the last recording's problems (D64):
/// the new problem report with what went wrong, from the recording's
/// recording manifest, in the browser, and its recording manifest and
/// recording log in Finder. The app opens no connection itself (D15).
struct ProblemReportAction {
    let recordingFolder: URL
    let version: String

    var issueURL: URL {
        ProblemReport.issueURL(whatWentWrong: whatWentWrong, version: version)
    }

    /// The recording manifest and the recording log that are there.
    var files: [URL] {
        [RecordingNames.manifest, RecordingNames.recordingLog]
            .map { recordingFolder.appending(path: $0) }
            .filter { FileManager.default.fileExists(atPath: $0.path(percentEncoded: false)) }
    }

    /// What the recording manifest tells went wrong, or why it cannot be read.
    private var whatWentWrong: [(at: Double, line: String)] {
        let manifest: RecordingManifest
        do {
            manifest = try RecordingManifest(json: Data(contentsOf: recordingFolder.appending(path: RecordingNames.manifest)))
        } catch {
            return [(0, "\(RecordingNames.manifest) cannot be read: \(ErrorDetail(error).text)")]
        }
        let notEnded = manifest.ended == nil ? [(0.0, RecordingSummary.manifestNotWrittenLine)] : []
        return RecordingSummary.whatWentWrong(manifest) + notEnded
    }

    /// Opens the link and shows the files; the link if the browser did not take it.
    @MainActor
    func run(opener: some ReportOpener) -> URL? {
        let url = issueURL
        opener.reveal(files)
        return opener.open(url) ? nil : url
    }
}
