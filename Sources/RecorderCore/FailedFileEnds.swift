import AVFoundation
import Foundation
import RecorderLogic

/// Reads the duration a file holds; `AssetDurationReader` in a recording,
/// a stand-in in tests.
public protocol FileDurationReader: Sendable {
    func duration(of url: URL) async throws -> Double
}

/// The duration AVFoundation loads from the file itself.
public struct AssetDurationReader: FileDurationReader {
    public init() {}

    public func duration(of url: URL) async throws -> Double {
        let seconds = try await AVURLAsset(url: url).load(.duration).seconds
        guard seconds.isFinite, seconds >= 0 else {
            throw NoUsableDuration(detail: ErrorDetail(message: "the file has no usable duration (\(seconds))"))
        }
        return seconds
    }
}

struct NoUsableDuration: ErrorWithDetail {
    let detail: ErrorDetail
}

extension FailedFileEnd {
    /// The end of the failed file `url`, which started at `start` and was
    /// last given up to `failedAt`, from the duration `reader` reads.
    static func read(_ url: URL, start: Double, failedAt: Double, with reader: any FileDurationReader) async -> FailedFileEnd {
        let duration: ReadDuration
        do {
            duration = .seconds(try await reader.duration(of: url))
        } catch {
            duration = .unreadable(ErrorDetail(error))
        }
        return FailedFileEnd(start: start, failedAt: failedAt, duration: duration)
    }
}

extension ScreenFileEnd {
    /// The time of the failure that ended the file: the end its writer was given.
    var failureSeconds: Double { failedAt ?? file.end ?? file.start }

    /// A file whose writer failed (not finalized) ends where it really
    /// ends (D66); any other file is returned as it is.
    func readingItsFile(in folder: URL, with reader: any FileDurationReader = AssetDurationReader()) async -> ScreenFileEnd {
        guard file.state == .notFinalized else { return self }
        let real = await FailedFileEnd.read(
            folder.appending(path: file.name), start: file.start, failedAt: file.end ?? file.start, with: reader)
        var end = self
        end.file.end = real.end
        end.failedAt = real.failedAt
        end.lost = real.lost
        return end
    }
}

extension AudioFileEnd {
    /// The time of the failure that ended the file: the end its writer was given.
    var failureSeconds: Double { failedAt ?? file.end ?? file.start }

    /// As `ScreenFileEnd.readingItsFile`.
    func readingItsFile(in folder: URL, with reader: any FileDurationReader = AssetDurationReader()) async -> AudioFileEnd {
        guard file.state == .notFinalized else { return self }
        let real = await FailedFileEnd.read(
            folder.appending(path: file.name), start: file.start, failedAt: file.end ?? file.start, with: reader)
        var end = self
        end.file.end = real.end
        end.failedAt = real.failedAt
        end.lost = real.lost
        return end
    }
}
