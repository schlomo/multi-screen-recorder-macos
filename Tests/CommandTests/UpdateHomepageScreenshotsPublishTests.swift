import Foundation
import Testing

/// Runs scripts/update-homepage-screenshots --release and --snapshot in a
/// clone of a local bare repository standing in for GitHub's: its `main` and
/// the PR's branch `feature` hold the homepage's pictures and a stand-in
/// scripts/end-to-end-test, which logs its arguments and writes a scratch
/// folder with the given run.log and three PNG captures. A stub `gh` first on
/// the PATH answers `gh pr view` with the given pull request and logs every
/// call, so no network, VM or GitHub is involved; git is the real one.
@Suite struct UpdateHomepageScreenshotsPublishTests {
    private static let pictures = ["app-window.png", "status-window.png", "recording-folder.png"]
    private static let captures = ["app-start-window-light", "app-status-window-light", "app-finder-window-light"]
    private static let pngSignature = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
    private static let releaseVersion = "0.20261122.79"

    private let scratch: ScratchFolder
    private let origin: URL
    private let checkout: URL
    private let bin: URL
    private var mainHead = ""
    private var featureHead = ""

    init() async throws {
        scratch = try ScratchFolder("UpdateHomepageScreenshotsPublishTests")
        origin = scratch.url.appending(path: "origin.git", directoryHint: .isDirectory)
        checkout = scratch.url.appending(path: "checkout", directoryHint: .isDirectory)
        bin = scratch.url.appending(path: "bin", directoryHint: .isDirectory)
        let seed = scratch.url.appending(path: "seed", directoryHint: .isDirectory)
        let images = seed.appending(path: "homepage/assets/images", directoryHint: .isDirectory)
        for folder in [origin, images, seed.appending(path: "scripts"), bin] {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        try await git(in: origin, "init", "--quiet", "--bare", "--initial-branch=main")
        try await git(in: seed, "init", "--quiet", "--initial-branch=main")
        for picture in Self.pictures { try png("old \(picture)").write(to: images.appending(path: picture)) }
        try executable(seed.appending(path: "scripts/end-to-end-test"), """
            #!/bin/sh
            set -eu
            echo "$*" >> "$STANDIN_FOLDER/end-to-end-test.log"
            while [ $# -gt 0 ]; do
                case $1 in --scratch-folder) scratch=$2; shift 2 ;; *) shift ;; esac
            done
            mkdir -p "$scratch/review/app"
            cp "$STANDIN_FOLDER/run.log" "$scratch/run.log"
            for name in \(Self.captures.joined(separator: " ")); do
                printf '\\211PNG\\r\\n\\032\\nnew %s' "$name" > "$scratch/review/app/$name.png"
            done
            exit "$(cat "$STANDIN_FOLDER/status")"

            """)
        try await git(in: seed, "add", ".")
        try await git(in: seed, "commit", "--quiet", "--message=main")
        try await git(in: seed, "remote", "add", "origin", path(origin))
        try await git(in: seed, "push", "--quiet", "origin", "main")
        try await git(in: seed, "switch", "--quiet", "--create", "feature")
        try await git(in: seed, "commit", "--quiet", "--allow-empty", "--message=feature")
        try await git(in: seed, "push", "--quiet", "origin", "feature")
        mainHead = try await git(in: origin, "rev-parse", "main")
        featureHead = try await git(in: origin, "rev-parse", "feature")
        try await git(in: scratch.url, "clone", "--quiet", path(origin), path(checkout))
        try FileManager.default.copyItem(
            at: repositoryRoot.appending(path: "scripts/update-homepage-screenshots"),
            to: checkout.appending(path: "scripts/update-homepage-screenshots"))
        try endToEndRun(version: Self.releaseVersion, commit: String(mainHead.prefix(7)))
        try stubGH(state: "OPEN")
    }

    private var environment: [String: String] {
        get throws {
            [
                "HOME": path(scratch.url),
                "GIT_CONFIG_NOSYSTEM": "1",
                "GIT_CONFIG_GLOBAL": "/dev/null",
                "GIT_AUTHOR_NAME": "Test", "GIT_AUTHOR_EMAIL": "test@example.invalid",
                "GIT_COMMITTER_NAME": "Test", "GIT_COMMITTER_EMAIL": "test@example.invalid",
                "PATH": "\(path(bin)):\(try #require(ProcessInfo.processInfo.environment["PATH"]))",
                "STANDIN_FOLDER": path(scratch.url),
            ]
        }
    }

    private func path(_ url: URL) -> String { url.path(percentEncoded: false) }

    private func png(_ text: String) -> Data { Self.pngSignature + Data(text.utf8) }

    private func executable(_ file: URL, _ script: String) throws {
        try Data(script.utf8).write(to: file)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: path(file))
    }

    @discardableResult
    private func git(in folder: URL, _ arguments: String...) async throws -> String {
        let outcome = try await run(URL(filePath: "/usr/bin/env"), ["git"] + arguments, environment: try environment, in: folder)
        try #require(outcome.status == 0, "git \(arguments) failed: \(outcome.errors)")
        return outcome.output.trimmingCharacters(in: .newlines)
    }

    /// What the stand-in end-to-end run writes into run.log and the exit status it ends with.
    private func endToEndRun(version: String, commit: String, status: Int32 = 0) throws {
        try Data("msr-end-to-end: \(version) (\(commit)), 7 scenarios; the Mac cannot be used until they end\n".utf8)
            .write(to: scratch.url.appending(path: "run.log"))
        try Data("\(status)".utf8).write(to: scratch.url.appending(path: "status"))
    }

    private func stubGH(state: String, isCrossRepository: Bool = false) throws {
        let pullRequest = scratch.url.appending(path: "pr.json")
        try Data(#"""
            {"state": "\#(state)", "headRefName": "feature", "headRefOid": "\#(featureHead)",
             "isCrossRepository": \#(isCrossRepository)}
            """#.utf8).write(to: pullRequest)
        try executable(bin.appending(path: "gh"), """
            #!/bin/sh
            printf '%s\\n' "$*" >> '\(path(scratch.url.appending(path: "gh.log")))'
            case "$1 $2" in
                "pr view") cat '\(path(pullRequest))' ;;
                "pr create") echo https://github.example/pull/27 ;;
            esac

            """)
    }

    private func update(_ arguments: [String]) async throws -> CommandOutcome {
        try await run(checkout.appending(path: "scripts/update-homepage-screenshots"), arguments,
                      environment: try environment, in: scratch.url)
    }

    private func log(_ name: String) throws -> [String] {
        let file = scratch.url.appending(path: name)
        guard FileManager.default.fileExists(atPath: path(file)) else { return [] }
        return try String(contentsOf: file, encoding: .utf8).split(separator: "\n").map(String.init)
    }

    private func picture(_ name: String, at commit: String) async throws -> String {
        try await git(in: origin, "show", "\(commit):homepage/assets/images/\(name)")
    }

    private func branches() async throws -> [String] {
        try await git(in: origin, "for-each-ref", "--format=%(refname:short)", "refs/heads").split(separator: "\n").map(String.init)
    }

    /// Nothing is left of the run's worktree, and the checkout stays where it was.
    private func expectCheckoutUntouched() async throws {
        #expect(try await git(in: checkout, "worktree", "list").split(separator: "\n").count == 1)
        #expect(try await git(in: checkout, "rev-parse", "HEAD") == mainHead)
        #expect(try await git(in: checkout, "status", "--porcelain", "--untracked-files=no").isEmpty)
    }

    @Test func aReleaseGetsABranchOffMainAndADraftPR() async throws {
        defer { scratch.remove() }
        let outcome = try await update(["--release"])
        #expect(outcome.status == 0, "\(outcome.errors)")
        let branch = "homepage-screenshots-v\(Self.releaseVersion)"
        #expect(try await branches().sorted() == ["feature", branch, "main"].sorted())
        #expect(try await git(in: origin, "rev-parse", "\(branch)^") == mainHead)
        for (picture, capture) in zip(Self.pictures, Self.captures) {
            #expect(try await self.picture(picture, at: branch).hasSuffix("new \(capture)"))
        }
        let message = try await git(in: origin, "log", "-1", "--format=%B", branch)
        #expect(message.hasPrefix("Homepage screenshots from \(Self.releaseVersion)"), "\(message)")
        #expect(!message.contains("skip ci"))
        #expect(try await git(in: origin, "diff", "--name-only", "main", branch).split(separator: "\n").sorted()
                == Self.pictures.map { "homepage/assets/images/\($0)" }.sorted())
        #expect(try log("end-to-end-test.log").count == 1)
        #expect(try log("end-to-end-test.log").first?.hasPrefix("--release --scratch-folder ") == true)
        let ghCalls = try log("gh.log")
        #expect(ghCalls.count == 1)
        #expect(ghCalls.first?.hasPrefix("pr create --draft --base main --head \(branch) --title Homepage screenshots from \(Self.releaseVersion) --body ") == true,
                "\(ghCalls)")
        #expect(outcome.output.contains("https://github.example/pull/27"))
        try await expectCheckoutUntouched()
    }

    @Test func aSnapshotIsPushedOntoThePRsBranch() async throws {
        defer { scratch.remove() }
        let version = "0.20261122.80-pr26+\(featureHead.prefix(7))"
        try endToEndRun(version: version, commit: String(featureHead.prefix(7)))
        let outcome = try await update(["--snapshot", "26"])
        #expect(outcome.status == 0, "\(outcome.errors)")
        #expect(try await branches().sorted() == ["feature", "main"])
        #expect(try await git(in: origin, "rev-parse", "feature^") == featureHead)
        #expect(try await picture("status-window.png", at: "feature").hasSuffix("new app-status-window-light"))
        #expect(try await git(in: origin, "log", "-1", "--format=%s", "feature") == "Homepage screenshots from \(version)")
        #expect(try log("end-to-end-test.log").first?.hasPrefix("--snapshot 26 --scratch-folder ") == true)
        #expect(try log("gh.log") == ["pr view 26 --json state,headRefName,headRefOid,isCrossRepository"])
        try await expectCheckoutUntouched()
    }

    @Test func aSnapshotOfAnotherCommitIsRefused() async throws {
        defer { scratch.remove() }
        try endToEndRun(version: "0.20261122.80-pr26+\(mainHead.prefix(7))", commit: String(mainHead.prefix(7)))
        let outcome = try await update(["--snapshot", "26"])
        #expect(outcome.status == 1)
        #expect(outcome.errors.contains("PR #26's snapshot release was built from \(mainHead.prefix(7)), its head is \(featureHead)"),
                "\(outcome.errors)")
        #expect(try await git(in: origin, "rev-parse", "feature") == featureHead)
        try await expectCheckoutUntouched()
    }

    @Test(arguments: [("CLOSED", false, "PR #26 is CLOSED, not open"), ("OPEN", true, "PR #26 comes from a fork")])
    func aPRThatHasNoSnapshotToFollowIsRefused(state: String, isCrossRepository: Bool, message: String) async throws {
        defer { scratch.remove() }
        try stubGH(state: state, isCrossRepository: isCrossRepository)
        let outcome = try await update(["--snapshot", "26"])
        #expect(outcome.status == 1)
        #expect(outcome.errors.contains(message), "\(outcome.errors)")
        #expect(try log("end-to-end-test.log").isEmpty)
        try await expectCheckoutUntouched()
    }

    @Test func aFailedEndToEndRunCommitsNothing() async throws {
        defer { scratch.remove() }
        try endToEndRun(version: Self.releaseVersion, commit: String(mainHead.prefix(7)), status: 1)
        let outcome = try await update(["--release"])
        #expect(outcome.status == 1)
        #expect(outcome.errors.contains("scripts/end-to-end-test ended with exit status 1; its scratch folder is "),
                "\(outcome.errors)")
        #expect(try await branches().sorted() == ["feature", "main"])
        #expect(try log("gh.log").isEmpty)
        try await expectCheckoutUntouched()
    }

    @Test func aReleaseRunOfAnAppThatIsNoReleaseIsRefused() async throws {
        defer { scratch.remove() }
        try endToEndRun(version: "0.20261122.80-dev+\(mainHead.prefix(7))", commit: String(mainHead.prefix(7)))
        let outcome = try await update(["--release"])
        #expect(outcome.status == 1)
        #expect(outcome.errors.contains("not a release version"), "\(outcome.errors)")
        #expect(try await branches().sorted() == ["feature", "main"])
        try await expectCheckoutUntouched()
    }

    @Test(arguments: [["--release", "--snapshot", "26"], ["--release", "end-to-end"], ["--snapshot", "0"],
                      ["--snapshot", "x"]])
    func oneSourceIsAUsageError(arguments: [String]) async throws {
        defer { scratch.remove() }
        let outcome = try await update(arguments)
        #expect(outcome.status == 1)
        #expect(outcome.errors.contains("usage:"), "\(outcome.errors)")
        #expect(try log("end-to-end-test.log").isEmpty)
        #expect(try log("gh.log").isEmpty)
    }
}
