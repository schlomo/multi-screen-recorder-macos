import Foundation
import RecorderLogic
import Testing
@testable import msr

/// Report a problem with a stand-in for the browser and Finder: nothing is opened.
@MainActor
@Suite struct ProblemReportActionTests {
    private final class StandIn: ReportOpener {
        let browserTakesIt: Bool
        var opened: [URL] = []
        var revealed: [[URL]] = []
        init(browserTakesIt: Bool = true) { self.browserTakesIt = browserTakesIt }
        func open(_ url: URL) -> Bool { opened.append(url); return browserTakesIt }
        func reveal(_ files: [URL]) { revealed.append(files) }
    }

    private func recordingFolder() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appending(path: "report-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    private func whatHappened(_ url: URL) throws -> String? {
        let items = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        return items.first { $0.name == ProblemReport.whatHappenedField }?.value
    }

    @Test func itOpensTheReportWithTheProblemsAndShowsBothFiles() throws {
        let folder = try recordingFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        var manifest = RecordingManifest(app: "a", started: Date(), timeZone: .gmt, settings: .defaults)
        manifest.problems = [RecordingProblem(atSeconds: 65, problem: "The screens cannot be read", error: "denied")]
        manifest.finalize(ended: Date(), timeZone: .gmt)
        try manifest.jsonData().write(to: folder.appending(path: RecordingNames.manifest))
        try Data("log\n".utf8).write(to: folder.appending(path: RecordingNames.recordingLog))

        let standIn = StandIn()
        let action = ProblemReportAction(recordingFolder: folder, version: "0.20261119.1 (a1b2c3d)")
        #expect(action.run(opener: standIn) == nil)
        #expect(standIn.revealed == [[folder.appending(path: "recording.json"), folder.appending(path: "recording.log")]])
        let url = try #require(standIn.opened.first)
        #expect(standIn.opened.count == 1)
        #expect(url.absoluteString.contains("template=problem-report.yml"))
        #expect(try whatHappened(url)?.hasSuffix("\nProblem at 1m05s: The screens cannot be read: denied") == true)
    }

    @Test func anUnreadableManifestIsSaidInTheReportAndOnlyTheLogIsShown() throws {
        let folder = try recordingFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        try Data("log\n".utf8).write(to: folder.appending(path: RecordingNames.recordingLog))

        let standIn = StandIn(browserTakesIt: false)
        let notOpened = ProblemReportAction(recordingFolder: folder, version: "v").run(opener: standIn)
        #expect(notOpened == standIn.opened.first)
        #expect(standIn.revealed == [[folder.appending(path: "recording.log")]])
        #expect(try whatHappened(#require(notOpened))?.contains("recording.json cannot be read: ") == true)
    }

    @Test func aManifestWithoutAnEndSaysSo() throws {
        let folder = try recordingFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        try RecordingManifest(app: "a", started: Date(), timeZone: .gmt, settings: .defaults).jsonData()
            .write(to: folder.appending(path: RecordingNames.manifest))
        let text = try whatHappened(ProblemReportAction(recordingFolder: folder, version: "v").issueURL)
        #expect(text?.contains(RecordingSummary.manifestNotWrittenLine) == true)
    }
}
