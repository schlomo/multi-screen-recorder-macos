import Foundation
import RecorderLogic

public struct StateFileError: Error, CustomStringConvertible {
    public let fileURL: URL
    public let problem: String

    public var description: String { "State file \(fileURL.path(percentEncoded: false)): \(problem)" }
}

/// The state file, next to the settings file; `HOME` decides where.
public struct StateFile: Sendable {
    public let url: URL

    public init(homeFolder: URL) {
        url = homeFolder.appending(path: "Library/Application Support/Multi Screen Recorder/state.json")
    }

    /// A missing file means nothing is remembered yet; one that cannot be read or decoded is an error.
    public func load() throws(StateFileError) -> AppState {
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else { return .empty }
        do { return try AppState(json: try Data(contentsOf: url)) } catch {
            throw StateFileError(fileURL: url, problem: error.localizedDescription)
        }
    }

    public func save(_ state: AppState) throws(StateFileError) {
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try state.json.write(to: url, options: .atomic)
        } catch {
            throw StateFileError(fileURL: url, problem: error.localizedDescription)
        }
    }
}
