import Foundation
import Testing

/// Runs scripts/publish-snapshot-release in a scratch checkout with one commit,
/// a bundle and its zip, against a stub `gh` first on the PATH: it answers
/// `gh pr view` with the given pull request, `gh release list` with no
/// releases, and logs every call, so no network is involved.
@Suite struct PublishSnapshotReleaseScriptTests {
    private let scratch: ScratchFolder
    private let checkout: URL
    private let bin: URL
    private let ghLog: URL
    private var head = ""

    init() throws {
        scratch = try ScratchFolder("PublishSnapshotReleaseScriptTests")
        checkout = scratch.url.appending(path: "checkout", directoryHint: .isDirectory)
        bin = scratch.url.appending(path: "bin", directoryHint: .isDirectory)
        ghLog = scratch.url.appending(path: "gh.log")
        let contents = checkout.appending(path: "build/Multi Screen Recorder.app/Contents", directoryHint: .isDirectory)
        for folder in [checkout.appending(path: "scripts"), contents, bin] {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        try FileManager.default.copyItem(
            at: repositoryRoot.appending(path: "scripts/publish-snapshot-release"),
            to: checkout.appending(path: "scripts/publish-snapshot-release"))
        try git("init", "--quiet", "--initial-branch=main")
        try git("commit", "--quiet", "--allow-empty", "--message=one")
        head = try git("rev-parse", "HEAD")
        let version = "0.2.0-pr7+\(head.prefix(7))"
        try PropertyListSerialization.data(fromPropertyList: ["MSRVersion": version], format: .xml, options: 0)
            .write(to: contents.appending(path: "Info.plist"))
        try Data("zip".utf8).write(to: checkout.appending(path: "build/Multi Screen Recorder \(version).zip"))
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

    /// Installs the stub `gh`, answering `gh pr view` with this pull request.
    private func stubGH(state: String, headRefOid: String) throws {
        let pullRequest = scratch.url.appending(path: "pr.json")
        try Data(#"{"state": "\#(state)", "headRefOid": "\#(headRefOid)"}"#.utf8).write(to: pullRequest)
        let gh = bin.appending(path: "gh")
        try Data("""
            #!/bin/sh
            echo "$*" >> '\(ghLog.path(percentEncoded: false))'
            case "$1 $2" in
                "pr view") cat '\(pullRequest.path(percentEncoded: false))' ;;
                "release list") echo '[]' ;;
            esac

            """.utf8).write(to: gh)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: gh.path(percentEncoded: false))
    }

    private func publish(_ environment: [String: String] = ["PR_NUMBER": "7"]) throws -> CommandOutcome {
        let path = try #require(ProcessInfo.processInfo.environment["PATH"])
        return try run(checkout.appending(path: "scripts/publish-snapshot-release"),
                       environment: environment.merging(["PATH": "\(bin.path(percentEncoded: false)):\(path)"]) { given, _ in given },
                       in: scratch.url)
    }

    private func ghCalls() throws -> [String] {
        guard FileManager.default.fileExists(atPath: ghLog.path(percentEncoded: false)) else { return [] }
        return try String(contentsOf: ghLog, encoding: .utf8).split(separator: "\n").map(String.init)
    }

    @Test func aClosedPRPublishesNothing() throws {
        defer { scratch.remove() }
        try stubGH(state: "MERGED", headRefOid: head)
        let outcome = try publish()
        #expect(outcome.status == 0, "\(outcome.errors)")
        #expect(outcome.errors.contains("PR #7 is MERGED, not open; publishing nothing"))
        #expect(try ghCalls() == ["pr view 7 --json state,headRefOid"])
    }

    @Test func aPRNowAtAnotherCommitPublishesNothing() throws {
        defer { scratch.remove() }
        let other = String(repeating: "1", count: 40)
        try stubGH(state: "OPEN", headRefOid: other)
        let outcome = try publish()
        #expect(outcome.status == 0, "\(outcome.errors)")
        #expect(outcome.errors.contains("PR #7 is now at \(other), not \(head); publishing nothing"))
        #expect(try ghCalls() == ["pr view 7 --json state,headRefOid"])
    }

    @Test func anOpenPRAtThisCommitIsPublished() throws {
        defer { scratch.remove() }
        try stubGH(state: "OPEN", headRefOid: head)
        let outcome = try publish()
        #expect(outcome.status == 0, "\(outcome.errors)")
        let calls = try ghCalls()
        #expect(calls.count == 3)
        #expect(calls.last?.hasPrefix("release create pr-7 build/Multi Screen Recorder 0.2.0-pr7+") == true, "\(calls)")
    }

    @Test func aMissingPRNumberStops() throws {
        defer { scratch.remove() }
        try stubGH(state: "OPEN", headRefOid: head)
        let outcome = try publish([:])
        #expect(outcome.status == 1)
        #expect(outcome.errors.contains("PR_NUMBER is not set"))
        #expect(try ghCalls().isEmpty)
    }

    @Test(arguments: InfoPlistDamage.allCases)
    func aDamagedInfoPlistStops(damage: InfoPlistDamage) throws {
        defer { scratch.remove() }
        try stubGH(state: "OPEN", headRefOid: head)
        try damage.write(to: checkout.appending(path: "build/Multi Screen Recorder.app/Contents/Info.plist"))
        let outcome = try publish()
        #expect(outcome.status == 1)
        #expect(outcome.errors.contains(damage.message), "\(outcome.errors)")
        #expect(!outcome.errors.contains("Traceback"))
        #expect(try ghCalls().isEmpty)
    }

    /// scripts/publish-release reads the same Info.plist, with plutil.
    @Test(arguments: InfoPlistDamage.allCases)
    func publishReleaseStopsOnADamagedInfoPlist(damage: InfoPlistDamage) throws {
        defer { scratch.remove() }
        try stubGH(state: "OPEN", headRefOid: head)
        try FileManager.default.copyItem(
            at: repositoryRoot.appending(path: "scripts/publish-release"),
            to: checkout.appending(path: "scripts/publish-release"))
        try damage.write(to: checkout.appending(path: "build/Multi Screen Recorder.app/Contents/Info.plist"))
        let path = try #require(ProcessInfo.processInfo.environment["PATH"])
        let outcome = try run(checkout.appending(path: "scripts/publish-release"),
                              environment: ["RELEASE_BUILD": "true", "PATH": "\(bin.path(percentEncoded: false)):\(path)"],
                              in: scratch.url)
        #expect(outcome.status == 1)
        #expect(outcome.errors.contains("cannot read MSRVersion from the bundle's Info.plist"), "\(outcome.errors)")
        #expect(try ghCalls().isEmpty)
    }
}
