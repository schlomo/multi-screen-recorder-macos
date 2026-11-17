import Foundation
import Testing

/// Runs scripts/version in scratch git repositories: an upstream with three
/// commits on main, committed on 2026-11-15 12:00 UTC, and a clone with the script copied in, since the script
/// works in the repository it lives in.
@Suite struct VersionScriptTests {
    private let scratch: ScratchFolder
    private let upstream: URL
    private let noon = "2026-11-15T12:00:00+00:00"

    init() async throws {
        scratch = try ScratchFolder("VersionScriptTests")
        upstream = scratch.url.appending(path: "upstream", directoryHint: .isDirectory)
        try await git("init", "--quiet", "--initial-branch=main", upstream.path(percentEncoded: false))
        for number in 1...3 {
            try await git("commit", "--quiet", "--allow-empty", "--message=\(number)", in: upstream, committedAt: noon)
        }
    }

    /// A git with no system or global configuration and a fixed identity.
    @discardableResult
    private func git(_ arguments: String..., in folder: URL? = nil, committedAt: String? = nil) async throws -> String {
        let outcome = try await run(URL(filePath: "/usr/bin/env"), ["git"] + arguments, environment: [
            "GIT_COMMITTER_DATE": committedAt ?? noon,
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
    private func clone(depth: Int? = nil) async throws -> URL {
        let work = scratch.url.appending(path: "work", directoryHint: .isDirectory)
        if let depth {
            try await git("clone", "--quiet", "--depth=\(depth)", "--no-single-branch",
                    upstream.absoluteString, work.path(percentEncoded: false))
        } else {
            try await git("clone", "--quiet", upstream.absoluteString, work.path(percentEncoded: false))
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

    private func version(in repository: URL, _ environment: [String: String] = [:]) async throws -> CommandOutcome {
        try await run(repository.appending(path: "scripts/version"), environment: environment, in: scratch.url)
    }

    private func shortHead(of repository: URL) async throws -> String {
        try await git("rev-parse", "--short=7", "HEAD", in: repository)
    }

    private func commitWork(in work: URL, committedAt: String? = nil) async throws {
        try await git("commit", "--quiet", "--allow-empty", "--message=work", in: work, committedAt: committedAt)
    }

    private func touch(_ file: String, in work: URL, contents: String = "changed") throws {
        try contents.write(to: work.appending(path: file), atomically: true, encoding: .utf8)
    }

    /// A tracked file with a committed change on top of origin/main, edited afterwards.
    private func makeDirty(_ work: URL) async throws {
        try touch("tracked.txt", in: work, contents: "one")
        try await git("add", "tracked.txt", in: work)
        try await commitWork(in: work)
        try touch("tracked.txt", in: work, contents: "two")
    }

    @Test func aLocalBuildCountsOneMoreThanMain() async throws {
        defer { scratch.remove() }
        let work = try await clone()
        try await commitWork(in: work)
        let outcome = try await version(in: work)
        #expect(outcome.status == 0)
        #expect(outcome.output == "0.20261115.4-dev+\(try await shortHead(of: work))\n")
    }

    @Test func aSnapshotCarriesThePRNumber() async throws {
        defer { scratch.remove() }
        let work = try await clone()
        let outcome = try await version(in: work, ["PR_NUMBER": "7"])
        #expect(outcome.status == 0)
        #expect(outcome.output == "0.20261115.4-pr7+\(try await shortHead(of: work))\n")
    }

    @Test func aReleaseIsTheDateAndTheCountOfMain() async throws {
        defer { scratch.remove() }
        let outcome = try await version(in: try clone(), ["RELEASE_BUILD": "true"])
        #expect(outcome.status == 0)
        #expect(outcome.output == "0.20261115.3\n")
    }

    @Test func theDateIsTheCommitDateOfHEAD() async throws {
        defer { scratch.remove() }
        let work = try await clone()
        try await commitWork(in: work, committedAt: "2030-01-02T10:00:00+00:00")
        let outcome = try await version(in: work)
        #expect(outcome.output == "0.20300102.4-dev+\(try await shortHead(of: work))\n")
    }

    /// The build date the banner shows: the version's date, from the same commit date in UTC.
    @Test func theBuildDateIsTheVersionsDate() async throws {
        defer { scratch.remove() }
        let work = try await clone()
        try await commitWork(in: work, committedAt: "2026-11-16T00:30:00+01:00")
        let outcome = try await run(work.appending(path: "scripts/version"), ["--build-date"], environment: [:], in: scratch.url)
        #expect(outcome.status == 0, "\(outcome.errors)")
        #expect(outcome.output == "2026-11-15\n")
        #expect(try await version(in: work).output.hasPrefix("0.20261115."))
    }

    @Test func anUnknownArgumentStops() async throws {
        defer { scratch.remove() }
        let outcome = try await run(try clone().appending(path: "scripts/version"), ["--bogus"], environment: [:], in: scratch.url)
        #expect(outcome.status == 1)
        #expect(outcome.output.isEmpty)
        #expect(outcome.errors.contains("unknown argument '--bogus'"))
    }

    @Test(arguments: ["--help", "-h"])
    func helpPrintsTheUsage(argument: String) async throws {
        defer { scratch.remove() }
        let outcome = try await run(repositoryRoot.appending(path: "scripts/version"), [argument])
        #expect(outcome.status == 0, "\(outcome.errors)")
        #expect(outcome.output.hasPrefix("Prints the version of the current checkout."), "\(outcome.output)")
        #expect(outcome.output.contains("--build-date"))
    }

    @Test func buildDateTakesNoFurtherArgument() async throws {
        defer { scratch.remove() }
        let outcome = try await run(try clone().appending(path: "scripts/version"), ["--build-date", "extra"],
                                    environment: [:], in: scratch.url)
        #expect(outcome.status == 1)
        #expect(outcome.output.isEmpty)
        #expect(outcome.errors.contains("--build-date takes no further argument, not 'extra'"), "\(outcome.errors)")
    }

    @Test func aCommitJustAfterMidnightUTCIsOfThatDay() async throws {
        defer { scratch.remove() }
        let work = try await clone()
        try await commitWork(in: work, committedAt: "2026-11-16T00:00:30+00:00")
        #expect(try await version(in: work).output == "0.20261116.4-dev+\(try await shortHead(of: work))\n")
    }

    @Test func theDateIsInUTCWhateverTheOffsetOfTheCommit() async throws {
        defer { scratch.remove() }
        let work = try await clone()
        try await commitWork(in: work, committedAt: "2026-11-16T00:30:00+01:00")
        #expect(try await version(in: work).output == "0.20261115.4-dev+\(try await shortHead(of: work))\n")
    }

    @Test func theDateIsNotTheTimeZoneOfTheCaller() async throws {
        defer { scratch.remove() }
        let work = try await clone()
        try await commitWork(in: work, committedAt: "2026-11-15T23:30:00+00:00")
        let outcome = try await version(in: work, ["TZ": "Pacific/Kiritimati"])
        #expect(outcome.output == "0.20261115.4-dev+\(try await shortHead(of: work))\n")
    }

    @Test func uncommittedChangesToTrackedFilesMakeALocalBuildDirty() async throws {
        defer { scratch.remove() }
        let work = try await clone()
        try await makeDirty(work)
        let outcome = try await version(in: work)
        #expect(outcome.status == 0)
        #expect(outcome.output == "0.20261115.4-dev+\(try await shortHead(of: work)).dirty\n")
    }

    @Test func aSnapshotWithUncommittedChangesStops() async throws {
        defer { scratch.remove() }
        let work = try await clone()
        try await makeDirty(work)
        let outcome = try await version(in: work, ["PR_NUMBER": "8"])
        #expect(outcome.status == 1)
        #expect(outcome.output.isEmpty)
        #expect(outcome.errors.contains("scripts/version: a snapshot needs a checkout with no uncommitted changes to tracked files"))
    }

    @Test func aConfiguredShowSignatureDoesNotBreakTheDate() async throws {
        defer { scratch.remove() }
        let work = try await clone()
        try await git("config", "gpg.program", try scratch.installFakeGPG().path(percentEncoded: false), in: work)
        try await git("config", "user.signingkey", "ABCDEF", in: work)
        try await git("commit", "--quiet", "--allow-empty", "--gpg-sign", "--message=signed", in: work)
        #expect(try await git("cat-file", "-p", "HEAD", in: work).contains("gpgsig"))
        let outcome = try await version(in: work, ["GIT_CONFIG_PARAMETERS": "'log.showSignature=true'"])
        #expect(outcome.status == 0, "\(outcome.errors)")
        #expect(outcome.output == "0.20261115.4-dev+\(try await shortHead(of: work))\n")
    }

    @Test func stagedChangesMakeABuildDirty() async throws {
        defer { scratch.remove() }
        let work = try await clone()
        try await makeDirty(work)
        try await git("add", "tracked.txt", in: work)
        #expect(try await version(in: work).output == "0.20261115.4-dev+\(try await shortHead(of: work)).dirty\n")
    }

    @Test func aCleanBuildHasNoDirtySuffix() async throws {
        defer { scratch.remove() }
        let work = try await clone()
        try touch("tracked.txt", in: work, contents: "one")
        try await git("add", "tracked.txt", in: work)
        try await commitWork(in: work)
        #expect(try await version(in: work).output == "0.20261115.4-dev+\(try await shortHead(of: work))\n")
    }

    @Test func untrackedFilesDoNotMakeABuildDirty() async throws {
        defer { scratch.remove() }
        let work = try await clone()
        try touch("untracked.txt", in: work)
        #expect(try await version(in: work).output == "0.20261115.4-dev+\(try await shortHead(of: work))\n")
    }

    @Test func aReleaseWithUncommittedChangesStops() async throws {
        defer { scratch.remove() }
        try touch("README", in: upstream, contents: "one")
        try await git("add", "README", in: upstream)
        try await git("commit", "--quiet", "--message=readme", in: upstream)
        let work = try await clone()
        try touch("README", in: work, contents: "two")
        let outcome = try await version(in: work, ["RELEASE_BUILD": "true"])
        #expect(outcome.status == 1)
        #expect(outcome.output.isEmpty)
        #expect(outcome.errors.contains("a release needs a checkout with no uncommitted changes to tracked files"))
    }

    @Test func aReleaseOfAnotherCommitStops() async throws {
        defer { scratch.remove() }
        let work = try await clone()
        try await commitWork(in: work)
        let outcome = try await version(in: work, ["RELEASE_BUILD": "true"])
        #expect(outcome.status == 1)
        #expect(outcome.output.isEmpty)
        #expect(outcome.errors.contains("a release builds origin/main, but HEAD is \(try await shortHead(of: work))"))
    }

    @Test(arguments: [
        (["RELEASE_BUILD": "yes"], "RELEASE_BUILD must be true or unset, not 'yes'"),
        (["RELEASE_BUILD": "true", "PR_NUMBER": "7"], "RELEASE_BUILD and PR_NUMBER exclude each other"),
        (["PR_NUMBER": "seven"], "PR_NUMBER must be a number, not 'seven'"),
        (["PR_NUMBER": "0"], "PR_NUMBER must be a number, not '0'"),
        (["PR_NUMBER": "07"], "PR_NUMBER must be a number, not '07'"),
    ])
    func invalidInputStops(environment: [String: String], message: String) async throws {
        defer { scratch.remove() }
        let outcome = try await version(in: try clone(), environment)
        #expect(outcome.status == 1)
        #expect(outcome.output.isEmpty)
        #expect(outcome.errors.contains(message))
    }

    @Test func aRepositoryWithoutOriginMainStops() async throws {
        defer { scratch.remove() }
        try addScript(to: upstream)
        let outcome = try await version(in: upstream)
        #expect(outcome.status == 1)
        #expect(outcome.output.isEmpty)
        #expect(outcome.errors.contains("cannot count the commits on origin/main"))
    }

    @Test func aShallowCloneStops() async throws {
        defer { scratch.remove() }
        let work = try await clone(depth: 1)
        let outcome = try await version(in: work)
        #expect(outcome.status == 1)
        #expect(outcome.output.isEmpty)
        #expect(outcome.errors.contains("is a shallow clone"))
    }
}
