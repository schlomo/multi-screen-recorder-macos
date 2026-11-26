import Testing
@testable import RecorderLogic

@Suite struct ProductTextTests {
    /// The window links to the homepage that `homepage/` builds and the Worker serves.
    @Test func theHomepageIsWhereTheSiteIsServed() throws {
        #expect(Homepage.url.absoluteString == "https://multiscreenrecorder.schapiro.org")
        #expect(try repositoryFile("homepage/hugo.toml").contains("baseURL = \"\(Homepage.url.absoluteString)/\""))
        #expect(try repositoryFile("homepage/hugo.toml").contains("description = \"\(ProductText.purpose)\""))
        #expect(try repositoryFile("homepage/wrangler.jsonc").contains("\"pattern\": \"\(Homepage.url.host() ?? "")\""))
    }

    /// D55: the app's header and the homepage say the same tagline, in the same two lines.
    @Test func theAppAndTheHomepageShowTheSameTagline() throws {
        let lines = Tagline.lines.map { "\"\($0)\"" }.joined(separator: ", ")
        #expect(Tagline.lines == ["Every screen, every camera, all audio.", "Keeps going when things change."])
        #expect(Tagline.text == "Every screen, every camera, all audio. Keeps going when things change.")
        #expect(try repositoryFile("homepage/hugo.toml").contains("tagline = [\(lines)]"))
        #expect(try repositoryFile("homepage/layouts/home.html")
            .contains("<p class=\"tagline\">{{ delimit site.Params.tagline \"<br />\" | safeHTML }}</p>"))
    }

    /// The homepage links to the problem report form.
    @Test func theProblemReportLinksOpenTheForm() throws {
        _ = try repositoryFile(".github/ISSUE_TEMPLATE/problem-report.yml")
        let link = "\(GitHubRepository.issues.absoluteString)/new?template=problem-report.yml"
        #expect(try repositoryFile("homepage/hugo.toml").contains(link))
    }

    @Test func resolutionShownNames() {
        #expect(RecordingResolution.allCases.map(\.shownName) == ["Native", "4K", "1440p", "1200p", "1080p", "720p", "None"])
    }
}
