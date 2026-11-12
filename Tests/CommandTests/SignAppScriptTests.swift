import Foundation
import Testing

/// Runs scripts/sign-app, signing ad hoc, in a scratch checkout with one
/// commit and a bundle around the built `msr`: the version and commit come
/// from the bundle and must have the form for this build.
@Suite struct SignAppScriptTests {
    private let scratch: ScratchFolder
    private let checkout: URL
    private var head = ""

    init() throws {
        scratch = try ScratchFolder("SignAppScriptTests")
        checkout = scratch.url.appending(path: "checkout", directoryHint: .isDirectory)
        for folder in ["scripts", "Resources", "build/Multi Screen Recorder.app/Contents/MacOS"] {
            try FileManager.default.createDirectory(
                at: checkout.appending(path: folder, directoryHint: .isDirectory), withIntermediateDirectories: true)
        }
        for file in ["scripts/sign-app", "Resources/msr.entitlements"] {
            try FileManager.default.copyItem(at: repositoryRoot.appending(path: file), to: checkout.appending(path: file))
        }
        try FileManager.default.copyItem(
            at: try buildProducts().appending(path: "msr"),
            to: checkout.appending(path: "build/Multi Screen Recorder.app/Contents/MacOS/msr"))
        try git("init", "--quiet", "--initial-branch=main")
        try git("commit", "--quiet", "--allow-empty", "--message=one")
        head = try git("rev-parse", "--short=7", "HEAD")
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

    private func writeInfo(version: String, commit: String? = nil,
                           identifier: String = "org.schapiro.multiscreenrecorder") throws {
        let plist: [String: String] = [
            "CFBundleExecutable": "msr",
            "CFBundleIdentifier": identifier,
            "CFBundlePackageType": "APPL",
            "MSRVersion": version,
            "MSRCommit": commit ?? head,
        ]
        try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            .write(to: checkout.appending(path: "build/Multi Screen Recorder.app/Contents/Info.plist"))
    }

    private func signApp(_ environment: [String: String] = [:]) throws -> CommandOutcome {
        try run(checkout.appending(path: "scripts/sign-app"),
                environment: environment.merging(["SIGNING_IDENTITY": "-"]) { given, _ in given }, in: scratch.url)
    }

    private func zipExists(_ version: String) -> Bool {
        FileManager.default.fileExists(
            atPath: checkout.appending(path: "build/Multi Screen Recorder \(version).zip").path(percentEncoded: false))
    }

    /// The bundle still carries build-app's signature or none: the key was not used.
    private func isUnsignedByThisRun() throws -> Bool {
        let signature = checkout.appending(path: "build/Multi Screen Recorder.app/Contents/_CodeSignature")
        return !FileManager.default.fileExists(atPath: signature.path(percentEncoded: false))
    }

    @Test(arguments: [
        ([String: String](), "0.13.0-dev+"),
        (["PR_NUMBER": "7"], "0.13.0-pr7+"),
    ])
    func aMatchingVersionIsSignedAndZipped(environment: [String: String], prefix: String) throws {
        defer { scratch.remove() }
        let version = prefix + head
        try writeInfo(version: version)
        let outcome = try signApp(environment)
        #expect(outcome.status == 0, "\(outcome.errors)")
        #expect(zipExists(version))
    }

    @Test func aReleaseHasNoSuffix() throws {
        defer { scratch.remove() }
        try writeInfo(version: "0.12.0")
        let outcome = try signApp(["RELEASE_BUILD": "true"])
        #expect(outcome.status == 0, "\(outcome.errors)")
        #expect(zipExists("0.12.0"))
    }

    @Test(arguments: [
        ([String: String](), "0.13.0-pr7+HEAD", "does not have the form"),
        (["PR_NUMBER": "8"], "0.13.0-pr7+HEAD", "does not have the form"),
        (["PR_NUMBER": "7"], "0.13.0-dev+HEAD", "does not have the form"),
        (["RELEASE_BUILD": "true"], "0.13.0-dev+HEAD", "does not have the form"),
        ([String: String](), "0.13.0-dev+abcdef0", "does not have the form"),
        (["RELEASE_BUILD": "yes"], "0.12.0", "RELEASE_BUILD must be true or unset"),
        (["RELEASE_BUILD": "true", "PR_NUMBER": "7"], "0.12.0", "exclude each other"),
        (["PR_NUMBER": "07"], "0.13.0-pr07+HEAD", "PR_NUMBER must be a number"),
    ])
    func aWrongVersionStopsBeforeSigning(environment: [String: String], version: String, message: String) throws {
        defer { scratch.remove() }
        try writeInfo(version: version.replacing("HEAD", with: head))
        let outcome = try signApp(environment)
        #expect(outcome.status == 1)
        #expect(outcome.errors.contains(message), "\(outcome.errors)")
        #expect(try isUnsignedByThisRun())
    }

    @Test func anotherCommitStopsBeforeSigning() throws {
        defer { scratch.remove() }
        try writeInfo(version: "0.13.0-dev+abcdef0", commit: "abcdef0")
        let outcome = try signApp()
        #expect(outcome.status == 1)
        #expect(outcome.errors.contains("the bundle was built from abcdef0, but HEAD is \(head)"))
        #expect(try isUnsignedByThisRun())
    }

    @Test func anotherIdentifierStopsBeforeSigning() throws {
        defer { scratch.remove() }
        try writeInfo(version: "0.13.0-dev+\(head)", identifier: "org.example.other")
        let outcome = try signApp()
        #expect(outcome.status == 1)
        #expect(outcome.errors.contains("identifier is org.example.other"))
        #expect(try isUnsignedByThisRun())
    }

    @Test func aMissingBundleStops() throws {
        defer { scratch.remove() }
        try FileManager.default.removeItem(at: checkout.appending(path: "build/Multi Screen Recorder.app"))
        let outcome = try signApp()
        #expect(outcome.status == 1)
        #expect(outcome.errors.contains("does not exist"))
    }
}
