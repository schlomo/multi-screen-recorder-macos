import Foundation
import Testing
@testable import RecorderLogic

@Suite struct CrashReportTests {
    private let older = "msr-2026-11-13-132800.ips"
    private let newer = "msr-2026-11-14-212425.ips"

    @Test func theNewestReportIsOfferedWhenNothingWasOfferedBefore() {
        #expect(CrashReport.toOffer(fileNames: [newer, older], lastOffered: nil) == newer)
    }

    @Test func aReportIsOfferedOnlyIfNewerThanTheLastOfferedOne() {
        #expect(CrashReport.toOffer(fileNames: [newer, older], lastOffered: older) == newer)
        #expect(CrashReport.toOffer(fileNames: [newer, older], lastOffered: newer) == nil)
        #expect(CrashReport.toOffer(fileNames: [older], lastOffered: newer) == nil)
    }

    @Test func onlyMSRReportsCount() {
        let others = ["swiftpm-testing-helper-2026-11-14-230000.ips", "msr-2026-11-15-100000.txt",
                      "xmsr-2026-11-15-100000.ips", "Retired"]
        #expect(CrashReport.toOffer(fileNames: others, lastOffered: nil) == nil)
        #expect(CrashReport.toOffer(fileNames: others + [older], lastOffered: nil) == older)
    }

    @Test func onlyTheExactNameShapeCounts() {
        let odd = ["msr-2026-11-14-212425.hang.ips", "msr-2026-11-14-212425.ips.bak", "msr-2026-11-14-2124.ips",
                   "msr-2026-11-14-212425-1.ips", "msr-.ips", "msr-2026-11-14-212425.IPS"]
        #expect(CrashReport.toOffer(fileNames: odd, lastOffered: nil) == nil)
    }

    @Test func aCrashDatedBeforeTheLastOfferedOneIsNotOffered() {
        #expect(CrashReport.toOffer(fileNames: [older], lastOffered: newer) == nil)
    }

    @Test func noReportsOfferNothing() {
        #expect(CrashReport.toOffer(fileNames: [], lastOffered: nil) == nil)
    }

    @Test func theIssueURLCarriesTheFormFields() throws {
        let url = CrashReport.issueURL(crashReportName: newer, version: "0.20261115.4 (a1b2c3d)", macOSVersion: "Version 26.1 (Build 25B78)")
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        #expect(components.scheme == "https")
        #expect(components.host == "github.com")
        #expect(components.path == "/schlomo/multi-screen-recorder-macos/issues/new")
        let query = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value) })
        #expect(query == [
            "template": "crash-report.yml",
            "title": "Crash: \(newer)",
            "version": "0.20261115.4 (a1b2c3d)",
            "macos": "Version 26.1 (Build 25B78)",
        ])
    }

    @Test func specialCharactersArePercentEncoded() {
        let url = CrashReport.issueURL(crashReportName: newer, version: "a&b=c d", macOSVersion: "x#y")
        #expect(url.absoluteString.contains("version=a%26b%3Dc%20d"))
        #expect(url.absoluteString.contains("macos=x%23y"))
    }

    @Test func theIssueFormHasTheFieldsTheURLFills() throws {
        let form = try repositoryFile(".github/ISSUE_TEMPLATE/crash-report.yml")
        #expect(form.contains("\n    id: \(CrashReport.versionField)\n"))
        #expect(form.contains("\n    id: \(CrashReport.macOSField)\n"))
        _ = try repositoryFile(".github/ISSUE_TEMPLATE/\(CrashReport.template)")
    }

    /// The form and the README name the same command for the log (D46); the crash report dialog
    /// names the recording's files instead (D64).
    @Test func theLogCommandIsInTheFormAndTheReadme() throws {
        #expect(CrashReport.logCommand == #"log show --last 2h --predicate 'subsystem == "org.schapiro.multiscreenrecorder" and process == "msr"'"#)
        let form = try repositoryFile(".github/ISSUE_TEMPLATE/crash-report.yml")
        #expect(form.contains("\n    id: log\n"))
        #expect(form.contains(CrashReport.logCommand))
        // in a comment, so the submitted issue does not show it
        let comment = try #require(form.firstMatch(of: /<!--(?s:(.*?))-->/)).1
        #expect(comment.contains(CrashReport.logCommand))
        #expect(try repositoryFile("README.md").contains(CrashReport.logCommand))
        #expect(!CrashReport.dialogText.contains(CrashReport.logCommand))
        #expect(CrashReport.dialogText.contains("recording.json and recording.log"))
        #expect(try repositoryFile("README.md").contains("`recording.json` and `recording.log`"))
    }

    @Test func aPlusInAValueIsPercentEncoded() {
        let url = CrashReport.issueURL(crashReportName: newer, version: "1+2", macOSVersion: "x")
        #expect(url.absoluteString.contains("version=1%2B2"))
    }

    @Test func theTextCopyKeepsTheBaseName() {
        #expect(CrashReport.textCopyName(crashReportName: newer) == "msr-2026-11-14-212425.txt")
    }

    @Test func theIssuesURLIsOneConstant() {
        #expect(GitHubRepository.issues.absoluteString == "https://github.com/schlomo/multi-screen-recorder-macos/issues")
    }
}
