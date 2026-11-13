import Testing
@testable import RecorderLogic

@Suite struct AppVersionTests {
    @Test func aBundledBuildShowsItsVersionAndCommit() {
        let version = AppVersion(infoDictionary: [
            AppVersion.versionKey: "0.2.0-pr3+a1b2c3d",
            AppVersion.commitKey: "a1b2c3d",
        ])
        #expect(version.description == "0.2.0-pr3+a1b2c3d (a1b2c3d)")
    }

    @Test func aReleaseShowsItsCommitToo() {
        let version = AppVersion(infoDictionary: [
            AppVersion.versionKey: "0.4.0",
            AppVersion.commitKey: "a1b2c3d",
        ])
        #expect(version.description == "0.4.0 (a1b2c3d)")
    }

    @Test func aBinaryOutsideABundleSaysSo() {
        #expect(AppVersion(infoDictionary: nil).description == "development build (not bundled)")
        #expect(AppVersion(infoDictionary: ["CFBundleExecutable": "msr"]).description
            == "development build (not bundled)")
    }

    @Test func aBundleWithoutItsCommitSaysSo() {
        let version = AppVersion(infoDictionary: [AppVersion.versionKey: "0.4.0"])
        #expect(version.description == "0.4.0 (commit missing from Info.plist)")
    }
}
