import Testing
@testable import RecorderLogic

@Suite struct ProductTextTests {
    @Test func thePurposeIsTheReadmesOpeningParagraph() throws {
        let readme = try repositoryFile("README.md")
        let opening = readme.components(separatedBy: "\n\n")[1].replacing("\n", with: " ")
        #expect(ProductText.purpose == opening)
    }

    @Test func resolutionLabels() {
        #expect(RecordingResolution.allCases.map(\.label) == ["Native", "4K", "1440p", "1200p", "1080p", "720p"])
    }
}
