import Foundation
import RecorderLogic

/// Writes a recording folder's timeline file (D68) from its `recording.json`:
/// at Stop, and for `msr timeline`.
public enum TimelineFile {
    struct Failure: ErrorWithDetail {
        let detail: ErrorDetail

        init(_ message: String, cause: (any Error)? = nil) {
            detail = ErrorDetail(message: message, underlying: cause)
        }
    }

    /// The timeline file in `folder`, written whole (replacing any older one) and returned. A file
    /// without an end gets its length from the media file, read by `reader`.
    @discardableResult
    public static func write(in folder: URL, reader: any FileDurationReader = AssetDurationReader()) async throws -> URL {
        let manifestFile = folder.appending(path: RecordingNames.manifest)
        let manifest: RecordingManifest
        do {
            manifest = try RecordingManifest(json: Data(contentsOf: manifestFile))
        } catch {
            throw Failure("\(RecordingNames.manifest) in \(folder.path(percentEncoded: false)) cannot be read", cause: error)
        }
        var mediaSeconds: [String: Double] = [:]
        for name in ResolveTimeline.filesWithoutEnd(in: manifest) {
            do {
                mediaSeconds[name] = try await reader.duration(of: folder.appending(path: name))
            } catch {
                throw Failure("the length of \(name) cannot be read", cause: error)
            }
        }
        let name = folder.lastPathComponent
        let file = folder.appending(path: ResolveTimeline.fileName(forFolder: name))
        do {
            let data = try ResolveTimeline.data(manifest: manifest, folderName: name, mediaSeconds: mediaSeconds)
            try data.write(to: file, options: .atomic)
        } catch {
            throw Failure("the timeline file \(file.lastPathComponent) cannot be written", cause: error)
        }
        return file
    }
}
