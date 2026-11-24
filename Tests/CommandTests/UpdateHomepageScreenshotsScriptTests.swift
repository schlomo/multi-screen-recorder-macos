import Foundation
import Testing

/// Runs scripts/update-homepage-screenshots in a scratch checkout, since the
/// script writes into the homepage of the repository it lives in.
@Suite struct UpdateHomepageScreenshotsScriptTests {
    /// The end-to-end run's light captures and the homepage pictures they become.
    private static let copies = [
        ("app-start-window-light.png", "app-window.png"),
        ("app-status-window-light.png", "status-window.png"),
        ("app-finder-window-light.png", "recording-folder.png"),
    ]
    private static let pngSignature = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])

    private let scratch: ScratchFolder
    private let checkout: URL
    private let endToEndScratch: URL

    init() throws {
        scratch = try ScratchFolder("UpdateHomepageScreenshotsScriptTests")
        checkout = scratch.url.appending(path: "checkout", directoryHint: .isDirectory)
        let scripts = checkout.appending(path: "scripts", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: scripts, withIntermediateDirectories: true)
        try FileManager.default.copyItem(
            at: repositoryRoot.appending(path: "scripts/update-homepage-screenshots"),
            to: scripts.appending(path: "update-homepage-screenshots"))
        endToEndScratch = scratch.url.appending(path: "end-to-end", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: images, withIntermediateDirectories: true)
        for (_, picture) in Self.copies { try png("old \(picture)").write(to: images.appending(path: picture)) }
        try FileManager.default.createDirectory(at: review, withIntermediateDirectories: true)
        for (capture, _) in Self.copies { try png("new \(capture)").write(to: review.appending(path: capture)) }
    }

    private var images: URL { checkout.appending(path: "homepage/assets/images", directoryHint: .isDirectory) }
    private var review: URL { endToEndScratch.appending(path: "review/app", directoryHint: .isDirectory) }

    private func png(_ text: String) -> Data { Self.pngSignature + Data(text.utf8) }

    private func contents(of name: String) throws -> Data { try Data(contentsOf: images.appending(path: name)) }

    private func update(_ arguments: [String]) async throws -> CommandOutcome {
        try await run(checkout.appending(path: "scripts/update-homepage-screenshots"), arguments, in: scratch.url)
    }

    @Test func theThreeLightCapturesReplaceTheHomepagePictures() async throws {
        defer { scratch.remove() }
        let outcome = try await update([endToEndScratch.path(percentEncoded: false)])
        #expect(outcome.status == 0, "\(outcome.errors)")
        for (capture, picture) in Self.copies {
            #expect(try contents(of: picture) == png("new \(capture)"))
            #expect(outcome.output.contains("homepage/assets/images/\(picture)"))
        }
    }

    @Test func aRelativeScratchFolderIsReadFromTheCurrentFolder() async throws {
        defer { scratch.remove() }
        let outcome = try await update(["end-to-end"])
        #expect(outcome.status == 0, "\(outcome.errors)")
        #expect(try contents(of: "status-window.png") == png("new app-status-window-light.png"))
    }

    @Test(arguments: copies.map(\.0))
    func aMissingCaptureStopsBeforeAnyPictureChanges(missing: String) async throws {
        defer { scratch.remove() }
        try FileManager.default.removeItem(at: review.appending(path: missing))
        let outcome = try await update([endToEndScratch.path(percentEncoded: false)])
        #expect(outcome.status == 1)
        #expect(outcome.errors.contains(missing), "\(outcome.errors)")
        for (_, picture) in Self.copies { #expect(try contents(of: picture) == png("old \(picture)")) }
    }

    @Test func aMissingHomepagePictureStops() async throws {
        defer { scratch.remove() }
        try FileManager.default.removeItem(at: images.appending(path: "app-window.png"))
        let outcome = try await update([endToEndScratch.path(percentEncoded: false)])
        #expect(outcome.status == 1)
        #expect(outcome.errors.contains("app-window.png"), "\(outcome.errors)")
        #expect(try contents(of: "status-window.png") == png("old status-window.png"))
    }

    @Test func noScratchFolderIsAUsageError() async throws {
        defer { scratch.remove() }
        let outcome = try await update([])
        #expect(outcome.status == 1)
        #expect(outcome.errors.contains("usage:"), "\(outcome.errors)")
    }

    @Test(arguments: ["--help", "-h"])
    func helpPrintsTheUsage(argument: String) async throws {
        defer { scratch.remove() }
        let outcome = try await update([argument])
        #expect(outcome.status == 0, "\(outcome.errors)")
        #expect(outcome.output.contains("scratch_folder"), "\(outcome.output)")
    }
}

/// The argument handling of --this-mac, which never reaches a recording: the app is checked and its
/// version printed before anything is built, and the scratch checkout has nothing to build.
@Suite struct UpdateHomepageScreenshotsThisMacTests {
    private let scratch: ScratchFolder
    private let checkout: URL

    init() throws {
        scratch = try ScratchFolder("UpdateHomepageScreenshotsThisMacTests")
        checkout = scratch.url.appending(path: "checkout", directoryHint: .isDirectory)
        let scripts = checkout.appending(path: "scripts", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: scripts, withIntermediateDirectories: true)
        try FileManager.default.copyItem(
            at: repositoryRoot.appending(path: "scripts/update-homepage-screenshots"),
            to: scripts.appending(path: "update-homepage-screenshots"))
    }

    private func update(_ arguments: [String]) async throws -> CommandOutcome {
        try await run(checkout.appending(path: "scripts/update-homepage-screenshots"), arguments, in: scratch.url)
    }

    private func fakeApp(version: String?) throws -> URL {
        let app = scratch.url.appending(path: "Fake.app", directoryHint: .isDirectory)
        let contents = app.appending(path: "Contents", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: contents.appending(path: "MacOS"), withIntermediateDirectories: true)
        try Data().write(to: contents.appending(path: "MacOS/msr"))
        if let version {
            try PropertyListSerialization.data(fromPropertyList: ["CFBundleShortVersionString": version], format: .xml, options: 0)
                .write(to: contents.appending(path: "Info.plist"))
        }
        return app
    }

    @Test(arguments: [["--release"], ["--snapshot", "3"], ["somewhere"]])
    func thisMacExcludesTheOtherSources(other: [String]) async throws {
        defer { scratch.remove() }
        let outcome = try await update(["--this-mac"] + other)
        #expect(outcome.status == 1)
        #expect(outcome.errors.contains("not allowed with"), "\(outcome.errors)")
    }

    @Test func appWithoutThisMacIsRefused() async throws {
        defer { scratch.remove() }
        let outcome = try await update(["--release", "--app", "/nonexistent.app"])
        #expect(outcome.status == 1)
        #expect(outcome.errors.contains("--app only goes with --this-mac"), "\(outcome.errors)")
    }

    @Test func aMissingAppIsRefused() async throws {
        defer { scratch.remove() }
        let outcome = try await update(["--this-mac", "--app", "/nonexistent.app"])
        #expect(outcome.status == 1)
        #expect(outcome.errors.contains("/nonexistent.app is not the app"), "\(outcome.errors)")
    }

    @Test func anAppWithoutAVersionIsRefused() async throws {
        defer { scratch.remove() }
        let outcome = try await update(["--this-mac", "--app", try fakeApp(version: nil).path(percentEncoded: false)])
        #expect(outcome.status == 1)
        #expect(outcome.errors.contains("cannot read its version"), "\(outcome.errors)")
    }

    @Test func theAppsVersionIsPrintedBeforeAnythingIsBuilt() async throws {
        defer { scratch.remove() }
        let outcome = try await update(["--this-mac", "--app", try fakeApp(version: "0.20261124.7").path(percentEncoded: false)])
        #expect(outcome.output.contains("version 0.20261124.7"), "\(outcome.output)")
        #expect(outcome.status == 1, "the scratch checkout has no package to build")
        #expect(outcome.errors.contains("swift build"), "\(outcome.errors)")
    }
}
