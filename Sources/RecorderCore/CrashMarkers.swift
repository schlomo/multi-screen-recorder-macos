import Darwin
import Foundation
import RecorderLogic

/// The crash markers in `active-recordings` beside the settings file
/// (`HOME` decides where): one per recording process while it records.
public struct CrashMarkers: Sendable {
    public let folder: URL

    public init(homeFolder: URL) {
        folder = homeFolder.appending(path: CrashMarker.folder, directoryHint: .isDirectory)
    }

    func url(processID: Int32) -> URL {
        folder.appending(path: CrashMarker.fileName(processID: processID))
    }

    /// Writes this process's marker naming its recording folder.
    func write(recordingFolder: URL, processID: Int32 = getpid()) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try CrashMarker(recordingFolder: recordingFolder.path(percentEncoded: false)).jsonData()
            .write(to: url(processID: processID), options: .atomic)
    }

    func remove(processID: Int32 = getpid()) throws {
        try FileManager.default.removeItem(at: url(processID: processID))
    }

    /// Handles every marker whose process is gone: its recording manifest's
    /// state becomes `not finalized` and the marker is removed. Returns one
    /// line per marker for the person: the report, or why it could not be
    /// handled (that marker is then left in place).
    /// Each line also goes to the unified log at `.notice`.
    public func finishLeftBehind(isRunning: (Int32) -> Bool = processIsRunning) -> [String] {
        let lines = handleLeftBehind(isRunning: isRunning)
        for line in lines { RecorderLog.notice(line, category: "crash markers") }
        return lines
    }

    private func handleLeftBehind(isRunning: (Int32) -> Bool) -> [String] {
        let names: [String]
        do {
            names = try FileManager.default.contentsOfDirectory(atPath: folder.path(percentEncoded: false)).sorted()
        } catch CocoaError.fileReadNoSuchFile {
            return []
        } catch {
            return ["Crash markers in \(folder.path(percentEncoded: false)) cannot be read: \(error.localizedDescription)"]
        }
        var lines: [String] = []
        for name in names {
            guard let processID = CrashMarker.processID(fileName: name), !isRunning(processID) else { continue }
            let markerURL = folder.appending(path: name)
            do {
                let marker = try CrashMarker(json: Data(contentsOf: markerURL))
                let manifestURL = URL(filePath: marker.recordingFolder, directoryHint: .isDirectory)
                    .appending(path: RecordingNames.manifest)
                if FileManager.default.fileExists(atPath: manifestURL.path(percentEncoded: false)) {
                    let manifest = try RecordingManifest(json: Data(contentsOf: manifestURL))
                    if manifest.state == .finalized {
                        // Gone after it finalized, before it removed its marker: nothing to report.
                        try FileManager.default.removeItem(at: markerURL)
                        continue
                    }
                    try manifest.markedNotFinalized().jsonData().write(to: manifestURL, options: .atomic)
                }
                try FileManager.default.removeItem(at: markerURL)
                lines.append(marker.report)
            } catch {
                lines.append("Crash marker \(markerURL.path(percentEncoded: false)) cannot be handled: \(error.localizedDescription)")
            }
        }
        return lines
    }
}

/// Whether a process with this ID exists.
public func processIsRunning(_ processID: Int32) -> Bool {
    kill(processID, 0) == 0 || errno == EPERM
}
