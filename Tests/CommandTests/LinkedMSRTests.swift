import Foundation
import Testing

/// `msr` started through a symbolic link finds its app bundle: it re-executes
/// itself at its real path. The bundle here is a minimal one, an Info.plist
/// with the version beside the built `msr`; scripts/build-app makes the real one.
@Suite struct LinkedMSRTests {
    private let scratch: ScratchFolder
    private let bundledMSR: URL

    init() throws {
        scratch = try ScratchFolder("LinkedMSRTests")
        let contents = scratch.url.appending(path: "Multi Screen Recorder.app/Contents", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: contents.appending(path: "MacOS"), withIntermediateDirectories: true)
        bundledMSR = contents.appending(path: "MacOS/msr")
        try FileManager.default.copyItem(at: try buildProducts().appending(path: "msr"), to: bundledMSR)
        let plist: [String: String] = [
            "CFBundleExecutable": "msr",
            "CFBundleIdentifier": "org.schapiro.multiscreenrecorder.test",
            "CFBundlePackageType": "APPL",
            "MSRVersion": "0.9.0-dev+abcdef0",
            "MSRCommit": "abcdef0",
        ]
        try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            .write(to: contents.appending(path: "Info.plist"))
    }

    private func version(of program: URL) throws -> CommandOutcome {
        try run(program, ["version"], environment: ["HOME": scratch.url.path(percentEncoded: false)])
    }

    @Test func theBundledMSRShowsItsVersion() throws {
        defer { scratch.remove() }
        let outcome = try version(of: bundledMSR)
        #expect(outcome.status == 0)
        #expect(outcome.output == "0.9.0-dev+abcdef0 (abcdef0)\n")
    }

    @Test func aLinkToTheBundledMSRShowsTheSameVersion() throws {
        defer { scratch.remove() }
        let bin = scratch.url.appending(path: "bin", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: false)
        let link = bin.appending(path: "msr")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: bundledMSR)
        let outcome = try version(of: link)
        #expect(outcome.status == 0)
        #expect(outcome.output == "0.9.0-dev+abcdef0 (abcdef0)\n")
    }
}
