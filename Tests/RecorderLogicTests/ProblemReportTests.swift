import Foundation
import Testing
@testable import RecorderLogic

@Suite struct ProblemReportTests {
    private func query(_ url: URL) throws -> [String: String?] {
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        #expect(components.scheme == "https")
        #expect(components.host == "github.com")
        #expect(components.path == "/schlomo/multi-screen-recorder-macos/issues/new")
        return Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value) })
    }

    @Test func theLinkFillsTheProblemReportForm() throws {
        let url = ProblemReport.issueURL(
            whatWentWrong: [(5, "Error at 5s: screen stream failed, LG (-3811)"), (65, "Problem at 1m05s: The screens cannot be read: denied")],
            version: "0.20261119.1 (a1b2c3d)")
        #expect(try query(url) == [
            "template": "problem-report.yml",
            "title": "Problem: ",
            "version": "0.20261119.1 (a1b2c3d)",
            "what-happened": "The recording ended with problems. What went wrong, the last first:\n"
                + "Problem at 1m05s: The screens cannot be read: denied\nError at 5s: screen stream failed, LG (-3811)",
        ])
    }

    /// The form ids the link fills are the ones `.github/ISSUE_TEMPLATE/problem-report.yml` has.
    @Test func theFieldsExistInTheForm() throws {
        let form = try repositoryFile(".github/ISSUE_TEMPLATE/problem-report.yml")
        for id in [ProblemReport.versionField, ProblemReport.whatHappenedField, "recording-json", "recording-log"] {
            #expect(form.contains("id: \(id)\n"), "\(id)")
        }
        #expect(form.contains("title: \"\(ProblemReport.title)\""))
    }

    @Test func nothingListedPointsToTheFiles() throws {
        let url = ProblemReport.issueURL(whatWentWrong: [], version: "v")
        #expect(try query(url)["what-happened"] == "The recording ended with problems; recording.log and recording.json tell what happened.")
    }

    @Test func aLongListIsCutToFitTheLinkAndSaysHowManyMore() throws {
        let lines = (0..<500).map { (Double($0), "Problem at \($0)s: The audio source Mic is gone: the device was removed (\($0))") }
        let url = ProblemReport.issueURL(whatWentWrong: lines, version: "v")
        #expect(url.absoluteString.count <= ProblemReport.maximumLinkLength)
        let text = try #require(try query(url)["what-happened"] ?? nil)
        let shown = text.split(separator: "\n").dropFirst().dropLast()
        #expect(shown.first == "Problem at 499s: The audio source Mic is gone: the device was removed (499)")
        #expect(shown.count > 10)
        #expect(text.hasSuffix("… and \(500 - shown.count) more, in recording.log and recording.json."))
        // One more line would not fit.
        let longer = ProblemReport.whatHappened(lastFirst: lines.reversed().map(\.1), shown: shown.count + 1)
        #expect(IssueFormLink.url(template: ProblemReport.template, title: ProblemReport.title,
                                  fields: [(ProblemReport.versionField, "v"), (ProblemReport.whatHappenedField, longer)])
            .absoluteString.count > ProblemReport.maximumLinkLength)
    }

    /// The state file keeps the recorder's folder path, which ends in a slash; the notice and the summary show it without.
    @Test func theNoticeAndTheSummaryShowTheFolderAlike() {
        let path = "/out/2026-11-19 14.10.46/"
        #expect(ProblemReport.noticeText(recordingFolder: path).hasPrefix("Its recording folder is /out/2026-11-19 14.10.46.\n"))
        let manifest = RecordingManifest(app: "a", started: Date(), timeZone: .gmt, settings: .manual)
        let summary = RecordingSummary(manifest: manifest, recordingFolder: path, seconds: 1, manifestWritten: true)
        #expect(summary.reportText(version: "v").contains("\nAttach: /out/2026-11-19 14.10.46/recording.log and"))
        #expect(ProblemReport.shownPath(path) == ProblemReport.shownPath("/out/2026-11-19 14.10.46"))
    }

    @Test func theNoticeNamesTheFolderAndTheFiles() {
        let text = ProblemReport.noticeText(recordingFolder: "/Users/a/Movies/2026-11-19 10-00-00")
        #expect(text.contains("/Users/a/Movies/2026-11-19 10-00-00"))
        #expect(text.contains("recording.json") && text.contains("recording.log"))
    }

    @Test func theSummaryEndsWithTheLinkAndTheFilesToAttach() throws {
        var manifest = RecordingManifest(app: "a", started: Date(), timeZone: .gmt, settings: .manual)
        manifest.problems = [RecordingProblem(atSeconds: 3, problem: "The screens cannot be read", error: "denied")]
        let summary = RecordingSummary(manifest: manifest, recordingFolder: "/r", seconds: 9, manifestWritten: false)
        let lines = summary.reportText(version: "v").split(separator: "\n", omittingEmptySubsequences: false)
        #expect(lines.count == 3 && lines[2].isEmpty)
        #expect(lines[1] == "Attach: /r/recording.log and recording.json")
        let link = try #require(lines[0].wholeMatch(of: /Report it: (.+)/)?.1)
        #expect(try query(try #require(URL(string: String(link))))["what-happened"] == "The recording ended with problems. What went wrong, the last first:\n"
            + "The recording manifest could not be written at the end: recording.json has no end.\n"
            + "Problem at 3s: The screens cannot be read: denied")
    }

    /// The recorder's folder path ends in a slash.
    @Test func theFilesToAttachHaveOneSlash() {
        let manifest = RecordingManifest(app: "a", started: Date(), timeZone: .gmt, settings: .manual)
        let summary = RecordingSummary(manifest: manifest, recordingFolder: "/out/2026-11-19 14.10.46/", seconds: 1, manifestWritten: true)
        #expect(summary.reportText(version: "v").hasSuffix("\nAttach: /out/2026-11-19 14.10.46/recording.log and recording.json\n"))
    }
}
