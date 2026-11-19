import Testing
@testable import EndToEndLogic

@Suite struct ReviewNamesTests {
    @Test func reviewFilesAreNamedByScenarioAndWhatTheyShow() {
        #expect(ReviewNames.folder == "review")
        #expect(ReviewNames.screenshot(scenario: "plain-recording", window: "status-window") == "plain-recording-status-window-light.png")
        #expect(ReviewNames.screenshot(scenario: ReviewNames.appStep, window: "start-window") == "app-start-window-light.png")
        #expect(ReviewNames.mainScreen(scenario: "plain-recording") == "plain-recording-main-screen-light.jpg")
        #expect(ReviewNames.contactSheet == "contact-sheet.png")
        #expect(ReviewNames.excerpt(of: "2026-11-19 08.27.21 Screen 1 - DELL P3421W.mov")
            == "excerpt 2026-11-19 08.27.21 Screen 1 - DELL P3421W.mov")
    }

    @Test func oneRecordingScenarioOpensTheStatusWindowWhileItRecords() {
        let shooting = Scenario.named.filter { $0.statusWindowAt != nil }
        #expect(shooting.map(\.name) == ["plain-recording"])
        for scenario in shooting { #expect(scenario.statusWindowAt! < scenario.stopAt) }
    }
}
