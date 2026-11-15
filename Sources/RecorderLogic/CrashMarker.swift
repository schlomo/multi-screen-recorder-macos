import Foundation

/// The crash marker: while recording, a process keeps
/// `active-recordings/<process id>.json` beside the settings file, naming its
/// recording folder (D20). One left behind by a process that is gone marks a
/// recording that was not finalized.
public struct CrashMarker: Codable, Equatable, Sendable {
    /// The recording folder's full path.
    public var recordingFolder: String

    public init(recordingFolder: String) {
        self.recordingFolder = recordingFolder
    }

    public static let folder = "Library/Application Support/Multi Screen Recorder/active-recordings"

    public static func fileName(processID: Int32) -> String { "\(processID).json" }

    /// The process ID a marker's file name gives, nil for any other file.
    public static func processID(fileName: String) -> Int32? {
        guard fileName.hasSuffix(".json") else { return nil }
        return Int32(fileName.dropLast(".json".count))
    }

    /// What the app and `msr check` report for a marker whose process is gone.
    public var report: String {
        "Recording \(recordingFolder) was not finalized; its files are readable up to the last"
            + " \(RecorderValues.fragmentSeconds) seconds"
    }

    public func jsonData() throws -> Data { try prettyJSON(self) }

    public init(json data: Data) throws {
        self = try JSONDecoder().decode(CrashMarker.self, from: data)
    }
}
