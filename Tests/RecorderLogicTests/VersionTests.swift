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

    @Test func aBundleWithoutItsCommitSaysSo() {
        let version = AppVersion(infoDictionary: [AppVersion.versionKey: "0.20261115.4"])
        #expect(version.description == "0.20261115.4 (commit missing from Info.plist)")
    }
}
