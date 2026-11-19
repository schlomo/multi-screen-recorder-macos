import Testing
@testable import EndToEndLogic

@Suite struct GitHubReportTests {
    @Test func anAnnotationEscapesItsMessageAndItsTitle() {
        #expect(GitHubReport.annotation(title: "tone", message: "a click is 5 ms off") == "::error title=tone::a click is 5 ms off")
        #expect(GitHubReport.annotation(title: "a:b,c", message: "100% off\r\nnext line")
            == "::error title=a%3Ab%2Cc::100%25 off%0D%0Anext line")
    }

    @Test func theSummaryIsATableWithOneRowPerScenario() {
        let summary = GitHubReport.summary(rows: [
            .init(scenario: "app", result: "evidence", seconds: nil, margin: nil, firstFailure: nil,
                  notes: "the screenshot of the start window was not taken: no window"),
            .init(scenario: "plain-recording", result: "ok", seconds: 14, margin: "+0.19 s / +0.13 s", firstFailure: nil),
            .init(scenario: "tone", result: "FAIL", seconds: 15, margin: nil, firstFailure: "a | b\nc"),
            .init(scenario: "system-audio", result: "STOP", seconds: nil, margin: nil, firstFailure: "interrupted"),
        ], verdict: "msr-end-to-end: 1 of 3 scenarios failed")
        #expect(summary == """
            ## End-to-end tests

            msr-end-to-end: 1 of 3 scenarios failed

            | Scenario | Result | Time | Margin | First failure | Evidence notes |
            |---|---|---|---|---|---|
            | app | evidence |  |  |  | the screenshot of the start window was not taken: no window |
            | plain-recording | ok | 14 s | +0.19 s / +0.13 s |  |  |
            | tone | FAIL | 15 s |  | a \\| b c |  |
            | system-audio | STOP |  |  | interrupted |  |

            """)
    }
}
