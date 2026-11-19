import RecorderLogic
import Testing
@testable import msr

/// The status window names the two files a report needs (D64).
@Suite struct StatusTextTests {
    @Test func theLineUnderTheProblemsNamesTheRecordingsFiles() {
        #expect(StatusView.forAReport.contains("\(RecordingNames.manifest) and \(RecordingNames.recordingLog)"))
    }
}
