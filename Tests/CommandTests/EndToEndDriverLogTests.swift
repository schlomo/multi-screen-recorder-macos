import Foundation
import Testing

/// The driver's own lines land in `run.log` in the scratch folder as well
/// as on the terminal, so a failed pipeline run keeps them. Only `restore`
/// without a restore file runs here: it reads the screen list and changes
/// nothing.
@Suite struct EndToEndDriverLogTests {
    private func scratch() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appending(path: "driver-log-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    @Test func aLineOnStandardOutputIsInTheLog() async throws {
        let folder = try scratch()
        defer { try? FileManager.default.removeItem(at: folder) }
        let outcome = try await run(try buildProducts().appending(path: "msr-end-to-end"),
                                    ["restore", "--scratch-folder", folder.path])
        #expect(outcome.status == 0, "\(outcome.errors)")
        #expect(outcome.output.hasPrefix("restore: no restore file"))
        let log = try String(contentsOf: folder.appending(path: "run.log"), encoding: .utf8)
        #expect(log == outcome.output)
    }

    @Test func anErrorIsOnStandardErrorAndInTheLog() async throws {
        let folder = try scratch()
        defer { try? FileManager.default.removeItem(at: folder) }
        try Data("not json".utf8).write(to: folder.appending(path: "restore.json"))
        let outcome = try await run(try buildProducts().appending(path: "msr-end-to-end"),
                                    ["restore", "--scratch-folder", folder.path])
        #expect(outcome.status == 1)
        #expect(outcome.output == "")
        #expect(outcome.errors.hasPrefix("msr-end-to-end: cannot read the restore file"), "\(outcome.errors)")
        let log = try String(contentsOf: folder.appending(path: "run.log"), encoding: .utf8)
        #expect(log == outcome.errors)
    }
}
