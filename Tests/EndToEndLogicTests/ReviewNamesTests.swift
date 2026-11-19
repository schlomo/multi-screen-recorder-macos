import Testing
@testable import EndToEndLogic

@Suite struct ReviewNamesTests {
    @Test func reviewFilesAreNamedByScenarioAndWhatTheyShow() {
        #expect(ReviewNames.folder == "review")
        #expect(ReviewNames.screenshot(scenario: ReviewNames.appStep, window: "start-window") == "app-start-window-light.png")
        #expect(ReviewNames.contactSheet == "contact-sheet.png")
        #expect(ReviewNames.excerpt(of: "2026-11-19 08.27.21 Screen 1 - DELL P3421W.mov")
            == "excerpt 2026-11-19 08.27.21 Screen 1 - DELL P3421W.mov")
    }
}
