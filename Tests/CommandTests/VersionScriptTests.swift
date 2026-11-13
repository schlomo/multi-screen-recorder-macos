import Foundation
import Testing

/// Runs scripts/version in scratch git repositories: an upstream with three
/// commits on main, and a clone with the script copied in, since the script
/// works in the repository it lives in.
@Suite struct VersionScriptTests {
    private let scratch: ScratchFolder
    private let upstream: URL

    init() throws {
        scratch = try ScratchFolder("VersionScriptTests")
        upstream = scratch.url.appending(path: "upstream", directoryHint: .isDirectory)
        try git("init", "--quiet", "--initial-branch=main", upstream.path(percentEncoded: false))
        for number in 1...3 {
            try git("commit", "--quiet", "--allow-empty", "--message=\(number)", in: upstream)
        }
    }

    /// A git with no system or global configuration and a fixed identity.
    @discardableResult
    private func git(_ arguments: String..., in folder: URL? = nil) throws -> String {
        let outcome = try run(URL(filePath: "/usr/bin/env"), ["git"] + arguments, environment: [
            "HOME": scratch.url.path(percentEncoded: false),
            "GIT_CONFIG_NOSYSTEM": "1",
            "GIT_CONFIG_GLOBAL": "/dev/null",
            "GIT_AUTHOR_NAME": "Test", "GIT_AUTHOR_EMAIL": "test@example.invalid",
            "GIT_COMMITTER_NAME": "Test", "GIT_COMMITTER_EMAIL": "test@example.invalid",
        ], in: folder ?? scratch.url)
        try #require(outcome.status == 0, "git \(arguments) failed: \(outcome.errors)")
        return outcome.output.trimmingCharacters(in: .newlines)
    }

    /// A clone of the upstream, through file:// so --depth applies, with
    /// scripts/version copied in.
    private func clone(depth: Int? = nil) throws -> URL {
        let work = scratch.url.appending(path: "work", directoryHint: .isDirectory)
        if let depth {
            try git("clone", "--quiet", "--depth=\(depth)", "--no-single-branch",
                    upstream.absoluteString, work.path(percentEncoded: false))
        } else {
            try git("clone", "--quiet", upstream.absoluteString, work.path(percentEncoded: false))
        }
        try addScript(to: work)
        return work
    }

    private func addScript(to repository: URL) throws {
        let scripts = repository.appending(path: "scripts", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: scripts, withIntermediateDirectories: true)
        try FileManager.default.copyItem(
            at: repositoryRoot.appending(path: "scripts/version"), to: scripts.appending(path: "version"))
    }

    private func version(in repository: URL, _ environment: [String: String] = [:]) throws -> CommandOutcome {
        try run(repository.appending(path: "scripts/version"), environment: environment, in: scratch.url)
    }

    private func shortHead(of repository: URL) throws -> String {
        try git("rev-parse", "--short=7", "HEAD", in: repository)
    }

    @Test func aLocalBuildCountsOneMoreThanMain() throws {
        defer { scratch.remove() }
        let work = try clone()
        try git("commit", "--quiet", "--allow-empty", "--message=work", in: work)
        let outcome = try version(in: work)
        #expect(outcome.status == 0)
        #expect(outcome.output == "0.4.0-dev+\(try shortHead(of: work))\n")
    }

    @Test func aSnapshotCarriesThePRNumber() throws {
        defer { scratch.remove() }
        let work = try clone()
        let outcome = try version(in: work, ["PR_NUMBER": "7"])
        #expect(outcome.status == 0)
        #expect(outcome.output == "0.4.0-pr7+\(try shortHead(of: work))\n")
    }

    @Test func aReleaseIsTheCountOfMain() throws {
        defer { scratch.remove() }
        let outcome = try version(in: try clone(), ["RELEASE_BUILD": "true"])
        #expect(outcome.status == 0)
        #expect(outcome.output == "0.3.0\n")
    }

    @Test func aReleaseOfAnotherCommitStops() throws {
        defer { scratch.remove() }
        let work = try clone()
        try git("commit", "--quiet", "--allow-empty", "--message=work", in: work)
        let outcome = try version(in: work, ["RELEASE_BUILD": "true"])
        #expect(outcome.status == 1)
        #expect(outcome.output.isEmpty)
        #expect(outcome.errors.contains("a release builds origin/main, but HEAD is \(try shortHead(of: work))"))
    }

    @Test(arguments: [
        (["RELEASE_BUILD": "yes"], "RELEASE_BUILD must be true or unset, not 'yes'"),
        (["RELEASE_BUILD": "true", "PR_NUMBER": "7"], "RELEASE_BUILD and PR_NUMBER exclude each other"),
        (["PR_NUMBER": "seven"], "PR_NUMBER must be a number, not 'seven'"),
        (["PR_NUMBER": "0"], "PR_NUMBER must be a number, not '0'"),
        (["PR_NUMBER": "07"], "PR_NUMBER must be a number, not '07'"),
    ])
    func invalidInputStops(environment: [String: String], message: String) throws {
        defer { scratch.remove() }
        let outcome = try version(in: try clone(), environment)
        #expect(outcome.status == 1)
        #expect(outcome.output.isEmpty)
        #expect(outcome.errors.contains(message))
    }

    @Test func aRepositoryWithoutOriginMainStops() throws {
        defer { scratch.remove() }
        try addScript(to: upstream)
        let outcome = try version(in: upstream)
        #expect(outcome.status == 1)
        #expect(outcome.output.isEmpty)
        #expect(outcome.errors.contains("cannot count the commits on origin/main"))
    }

    @Test func aShallowCloneStops() throws {
        defer { scratch.remove() }
        let work = try clone(depth: 1)
        let outcome = try version(in: work)
        #expect(outcome.status == 1)
        #expect(outcome.output.isEmpty)
        #expect(outcome.errors.contains("is a shallow clone"))
    }
}
