import Foundation
import Testing

/// Runs scripts/smoke-test in a scratch checkout with one commit and a bundle
/// around the built `msr`, whose Info.plist names the version and commit.
@Suite struct SmokeTestScriptTests {
    private let scratch: ScratchFolder
    private let checkout: URL
    private var head = ""

    init() throws {
        scratch = try ScratchFolder("SmokeTestScriptTests")
        checkout = scratch.url.appending(path: "checkout", directoryHint: .isDirectory)
        for folder in ["scripts", "build/Multi Screen Recorder.app/Contents/MacOS", "build/Multi Screen Recorder.app/Contents/Resources"] {
            try FileManager.default.createDirectory(
                at: checkout.appending(path: folder, directoryHint: .isDirectory), withIntermediateDirectories: true)
        }
        try FileManager.default.copyItem(
            at: repositoryRoot.appending(path: "scripts/smoke-test"), to: checkout.appending(path: "scripts/smoke-test"))
        try FileManager.default.copyItem(
            at: try buildProducts().appending(path: "msr"),
            to: checkout.appending(path: "build/Multi Screen Recorder.app/Contents/MacOS/msr"))
        try makeIcon(at: checkout.appending(path: "build/Multi Screen Recorder.app/Contents/Resources/AppIcon.icns"))
        try git("init", "--quiet", "--initial-branch=main")
        try git("commit", "--quiet", "--allow-empty", "--message=one")
        head = try git("rev-parse", "--short=7", "HEAD")
    }

    /// A real `.icns` holding the committed icon at 1024 px, as iconutil makes it.
    private func makeIcon(at icns: URL) throws {
        let iconset = scratch.url.appending(path: "AppIcon.iconset", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
        try FileManager.default.copyItem(
            at: repositoryRoot.appending(path: "assets/icon/app-icon.png"),
            to: iconset.appending(path: "icon_512x512@2x.png"))
        let outcome = try run(URL(filePath: "/usr/bin/env"),
                              ["iconutil", "-c", "icns", iconset.path(percentEncoded: false), "-o", icns.path(percentEncoded: false)],
                              environment: [:], in: scratch.url)
        try #require(outcome.status == 0, "iconutil failed: \(outcome.errors)")
    }

    @discardableResult
    private func git(_ arguments: String...) throws -> String {
        let outcome = try run(URL(filePath: "/usr/bin/env"), ["git"] + arguments, environment: [
            "HOME": scratch.url.path(percentEncoded: false),
            "GIT_CONFIG_NOSYSTEM": "1",
            "GIT_CONFIG_GLOBAL": "/dev/null",
            "GIT_AUTHOR_NAME": "Test", "GIT_AUTHOR_EMAIL": "test@example.invalid",
            "GIT_COMMITTER_NAME": "Test", "GIT_COMMITTER_EMAIL": "test@example.invalid",
        ], in: checkout)
        try #require(outcome.status == 0, "git \(arguments) failed: \(outcome.errors)")
        return outcome.output.trimmingCharacters(in: .newlines)
    }

    private func writeInfo(commit: String, iconFile: String? = "AppIcon") throws {
        var plist: [String: String] = [
            "CFBundleExecutable": "msr",
            "CFBundleIdentifier": "org.schapiro.multiscreenrecorder.test",
            "CFBundlePackageType": "APPL",
            "MSRVersion": "0.9.0-dev+\(commit)",
            "MSRCommit": commit,
        ]
        plist["CFBundleIconFile"] = iconFile
        try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            .write(to: checkout.appending(path: "build/Multi Screen Recorder.app/Contents/Info.plist"))
    }

    private func smokeTest() throws -> CommandOutcome {
        try run(checkout.appending(path: "scripts/smoke-test"), in: scratch.url)
    }

    @Test func aBundleOfThisCommitPasses() throws {
        defer { scratch.remove() }
        try writeInfo(commit: head)
        let outcome = try smokeTest()
        #expect(outcome.status == 0, "\(outcome.errors)")
        #expect(outcome.output.contains("ok    msr version through a symbolic link prints the same"))
        #expect(outcome.output.contains("ok    the bundle names its icon file and holds it"))
        #expect(outcome.output.contains("all checks passed"))
    }

    @Test func aBundleWithoutCFBundleIconFileFails() throws {
        defer { scratch.remove() }
        try writeInfo(commit: head, iconFile: nil)
        let outcome = try smokeTest()
        #expect(outcome.status == 1)
        #expect(outcome.errors.contains("FAIL  the bundle names its icon file and holds it: CFBundleIconFile is not set"),
                "\(outcome.errors)")
    }

    @Test func anEmptyIconFileFails() throws {
        defer { scratch.remove() }
        try writeInfo(commit: head)
        try Data().write(to: checkout.appending(path: "build/Multi Screen Recorder.app/Contents/Resources/AppIcon.icns"))
        let outcome = try smokeTest()
        #expect(outcome.status == 1)
        #expect(outcome.errors.contains("FAIL  the bundle names its icon file and holds it: Contents/Resources/AppIcon.icns is not a 1024 px icon"),
                "\(outcome.errors)")
    }

    @Test func aBundleWithoutTheIconFileFails() throws {
        defer { scratch.remove() }
        try writeInfo(commit: head)
        try FileManager.default.removeItem(
            at: checkout.appending(path: "build/Multi Screen Recorder.app/Contents/Resources/AppIcon.icns"))
        let outcome = try smokeTest()
        #expect(outcome.status == 1)
        #expect(outcome.errors.contains("FAIL  the bundle names its icon file and holds it: Contents/Resources/AppIcon.icns is missing"),
                "\(outcome.errors)")
    }

    @Test func aBundleOfAnotherCommitFails() throws {
        defer { scratch.remove() }
        try writeInfo(commit: "abcdef0")
        let outcome = try smokeTest()
        #expect(outcome.status == 1)
        #expect(outcome.errors.contains("FAIL  msr version prints this commit's version"), "\(outcome.errors)")
        #expect(outcome.errors.contains("check(s) failed"))
    }

    @Test func aMissingBundleStops() throws {
        defer { scratch.remove() }
        try FileManager.default.removeItem(at: checkout.appending(path: "build/Multi Screen Recorder.app"))
        let outcome = try smokeTest()
        #expect(outcome.status == 1)
        #expect(outcome.errors.contains("run scripts/build-app first"))
    }

    @Test(arguments: InfoPlistDamage.allCases)
    func aDamagedInfoPlistStops(damage: InfoPlistDamage) throws {
        defer { scratch.remove() }
        try damage.write(to: checkout.appending(path: "build/Multi Screen Recorder.app/Contents/Info.plist"))
        let outcome = try smokeTest()
        #expect(outcome.status == 1)
        #expect(outcome.errors.contains(damage.message), "\(outcome.errors)")
        #expect(!outcome.errors.contains("Traceback"))
    }
}
