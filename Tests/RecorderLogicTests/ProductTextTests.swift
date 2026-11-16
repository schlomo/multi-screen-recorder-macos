import Testing
@testable import RecorderLogic

@Suite struct ProductTextTests {
    @Test func thePurposeIsTheReadmesOpeningParagraph() throws {
        let readme = try repositoryFile("README.md")
        let opening = readme.components(separatedBy: "\n\n")[1].replacing("\n", with: " ")
        #expect(ProductText.purpose == opening)
    }

    /// The window links to the homepage that `homepage/` builds and the Worker serves.
    @Test func theHomepageIsWhereTheSiteIsServed() throws {
        #expect(Homepage.url.absoluteString == "https://multiscreenrecorder.schapiro.org")
        #expect(try repositoryFile("homepage/hugo.toml").contains("baseURL = \"\(Homepage.url.absoluteString)/\""))
        #expect(try repositoryFile("homepage/hugo.toml").contains("description = \"\(ProductText.purpose)\""))
        #expect(try repositoryFile("homepage/wrangler.jsonc").contains("\"pattern\": \"\(Homepage.url.host() ?? "")\""))
    }

    /// The README and the homepage link to the problem report form.
    @Test func theProblemReportLinksOpenTheForm() throws {
        _ = try repositoryFile(".github/ISSUE_TEMPLATE/problem-report.yml")
        let link = "\(GitHubRepository.issues.absoluteString)/new?template=problem-report.yml"
        #expect(try repositoryFile("README.md").contains(link))
        #expect(try repositoryFile("homepage/hugo.toml").contains(link))
    }

    @Test func resolutionLabels() {
        #expect(RecordingResolution.allCases.map(\.label) == ["Native", "4K", "1440p", "1200p", "1080p", "720p"])
    }
}
