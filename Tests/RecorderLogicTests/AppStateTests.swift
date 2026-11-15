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
        #expect(try AppState(json: state.json) == state)
        #expect(String(decoding: state.json, as: UTF8.self) == #"{\#n  "lastOfferedCrashReport": "msr-2026-11-14-212425.ips"\#n}\#n"#)
        #expect(String(decoding: AppState.empty.json, as: UTF8.self) == "{\n}\n")
    }

    @Test func aCrashReportIsOfferedOnceOnceItIsMarked() {
        let names = ["msr-2026-11-13-132800.ips", "msr-2026-11-14-212425.ips"]
        let name = CrashReport.toOffer(fileNames: names, lastOffered: AppState.empty.lastOfferedCrashReport)
        #expect(name == "msr-2026-11-14-212425.ips")
        let marked = AppState.empty.offering(name!)
        #expect(marked.lastOfferedCrashReport == name)
        #expect(CrashReport.toOffer(fileNames: names, lastOffered: marked.lastOfferedCrashReport) == nil)
    }

    @Test func brokenJSONIsAnError() {
        #expect(throws: (any Error).self) { try AppState(json: Data("{".utf8)) }
        #expect(throws: (any Error).self) { try AppState(json: Data(#"{"lastOfferedCrashReport": 3}"#.utf8)) }
    }
}
