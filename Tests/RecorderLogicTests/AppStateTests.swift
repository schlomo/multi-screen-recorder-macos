import Foundation
import Testing
@testable import RecorderLogic

@Suite struct AppStateTests {
    @Test func theLastOfferedCrashReportIsReadFromJSON() throws {
        let state = try AppState(json: Data(#"{"lastOfferedCrashReport": "msr-2026-11-14-212425.ips"}"#.utf8))
        #expect(state.lastOfferedCrashReport == "msr-2026-11-14-212425.ips")
    }

    @Test func anEmptyObjectMeansNothingOfferedYet() throws {
        #expect(try AppState(json: Data("{}".utf8)) == .empty)
    }

    @Test func itRoundTrips() throws {
        let state = AppState(lastOfferedCrashReport: "msr-2026-11-14-212425.ips")
        #expect(try AppState(json: state.jsonData()) == state)
        #expect(String(decoding: try state.jsonData(), as: UTF8.self)
            == #"{\#n  "lastOfferedCrashReport" : "msr-2026-11-14-212425.ips"\#n}\#n"#)
        #expect(try AppState(json: AppState.empty.jsonData()) == .empty)
    }

    @Test func theStateFileIsWrittenLikeTheSettingsFile() throws {
        #expect(String(decoding: try AppState.empty.jsonData(), as: UTF8.self) == "{\n\n}\n")
    }

    @Test func aCrashReportIsOfferedOnceOnceItIsMarked() {
        let names = ["msr-2026-11-13-132800.ips", "msr-2026-11-14-212425.ips"]
        let installed = "/Applications/\(CrashReport.appBundleName)/Contents/MacOS/msr"
        let name = CrashReport.toOffer(fileNames: names, lastOffered: AppState.empty.lastOfferedCrashReport, procPath: { _ in installed })
        #expect(name == "msr-2026-11-14-212425.ips")
        let marked = AppState.empty.offering(name!)
        #expect(marked.lastOfferedCrashReport == name)
        #expect(CrashReport.toOffer(fileNames: names, lastOffered: marked.lastOfferedCrashReport, procPath: { _ in installed }) == nil)
    }

    @Test func brokenJSONIsAnError() {
        #expect(throws: (any Error).self) { try AppState(json: Data("{".utf8)) }
        #expect(throws: (any Error).self) { try AppState(json: Data(#"{"lastOfferedCrashReport": 3}"#.utf8)) }
    }

    @Test func theLastRecordingIsKeptInTheFile() throws {
        let state = AppState.empty.recorded(folder: "/Users/a/Movies/r", noticeWanted: true)
        #expect(state.lastRecording == AppState.LastRecording(folder: "/Users/a/Movies/r", noticeWanted: true, noticeShown: false))
        #expect(try AppState(json: state.jsonData()) == state)
        #expect(String(decoding: try state.jsonData(), as: UTF8.self).contains(#""noticeWanted" : true"#))
        let shown = state.showingProblemsNotice()
        #expect(try AppState(json: shown.jsonData()) == shown)
    }

    /// A state file the release before D84 wrote, with the recording's `result`, decodes: it wants no notice.
    @Test func aStateFileWithTheResultWantsNoNotice() throws {
        let state = try AppState(json: Data(#"{"lastRecording": {"folder": "/r", "result": "problems", "noticeShown": false}}"#.utf8))
        #expect(state.lastRecording == AppState.LastRecording(folder: "/r", noticeWanted: false))
        #expect(state.problemsNoticeFolder { _ in true } == nil)
    }

    @Test func theNoticeShowsOnceForARecordingThatWantsItWhoseFolderIsThere() {
        let wanted = AppState.empty.recorded(folder: "/r", noticeWanted: true)
        #expect(wanted.problemsNoticeFolder { _ in true } == "/r")
        #expect(wanted.problemsNoticeFolder { _ in false } == nil)
        #expect(wanted.showingProblemsNotice().problemsNoticeFolder { _ in true } == nil)
        #expect(AppState.empty.recorded(folder: "/r", noticeWanted: false).problemsNoticeFolder { _ in true } == nil)
        #expect(AppState.empty.problemsNoticeFolder { _ in true } == nil)
    }

    @Test func aNewRecordingReplacesTheLastOneAndItsNotice() {
        let shown = AppState.empty.recorded(folder: "/r1", noticeWanted: true).showingProblemsNotice()
        #expect(shown.recorded(folder: "/r2", noticeWanted: true).problemsNoticeFolder { _ in true } == "/r2")
        #expect(shown.recorded(folder: "/r2", noticeWanted: false).offering("c").lastRecording?.folder == "/r2")
    }
}
