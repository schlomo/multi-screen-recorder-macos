import Testing
@testable import RecorderLogic

@Suite struct AppVersionTests {
    @Test func aBundledBuildShowsItsVersionAndCommit() {
        let version = AppVersion(infoDictionary: [
            AppVersion.versionKey: "0.20261115.2-pr3+a1b2c3d",
            AppVersion.commitKey: "a1b2c3d",
        ])
        #expect(version.description == "0.20261115.2-pr3+a1b2c3d (a1b2c3d)")
    }

    @Test func aReleaseShowsItsCommitToo() {
        let version = AppVersion(infoDictionary: [
            AppVersion.versionKey: "0.20261115.4",
            AppVersion.commitKey: "a1b2c3d",
        ])
        #expect(version.description == "0.20261115.4 (a1b2c3d)")
    }

    @Test func aBinaryOutsideABundleSaysSo() {
        #expect(AppVersion(infoDictionary: nil).description == "development build (not bundled)")
        #expect(AppVersion(infoDictionary: ["CFBundleExecutable": "msr"]).description
            == "development build (not bundled)")
    }

    /// The banner `msr check` and `msr record` print first: the version as
    /// `msr version` shows it, the build date and the homepage.
    @Test func theBannerNamesTheVersionTheBuildDateAndTheHomepage() {
        let version = AppVersion(infoDictionary: [
            AppVersion.versionKey: "0.20261116.42", AppVersion.commitKey: "9dc9443", AppVersion.buildDateKey: "2026-11-16",
        ])
        #expect(version.banner == """
            Multi Screen Recorder 0.20261116.42 (9dc9443), built 2026-11-16
            https://multiscreenrecorder.schapiro.org


            """)
    }

    @Test func aBannerWithoutABuildDateLeavesItOut() {
        #expect(AppVersion(infoDictionary: nil).banner == """
            Multi Screen Recorder development build (not bundled)
            https://multiscreenrecorder.schapiro.org


            """)
    }

    @Test func aBundleWithoutItsCommitSaysSo() {
        let version = AppVersion(infoDictionary: [AppVersion.versionKey: "0.20261115.4"])
        #expect(version.description == "0.20261115.4 (commit missing from Info.plist)")
    }
}
