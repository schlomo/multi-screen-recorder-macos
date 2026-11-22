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
