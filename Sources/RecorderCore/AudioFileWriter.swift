import AVFoundation
import CoreMedia
import RecorderLogic

public struct AudioFileWriterError: Error, Equatable, CustomStringConvertible {
    public let description: String
    /// The disk is full: the file ends, readable up to its last fragment.
    public let isDiskFull: Bool

    init(_ error: (any Error)?, while doing: String) {
        if let error {
            description = "\(doing): \(error.localizedDescription)"
            isDiskFull = isDiskFullError(error)
        } else {
            description = doing
            isDiskFull = false
        }
    }
}

/// An audio file: AAC-LC at 48 kHz in a fragmented `.mov`, a fragment every
/// 2 s, one mono audio track per channel of an audio input or one stereo
/// audio track for the system audio, with the timecode track carrying the
/// source as its reel name, and metadata items (D45, D46, D49). Samples are
/// placed by count from the file's first tick.
/// Not thread-safe: one queue uses it.
public final class AudioFileWriter {
    public let url: URL
    public let firstTick: Int64
    public let description: AudioFileDescription
    private let grid: TickGrid
    private let timecode: Timecode
    private let writer: AVAssetWriter
    private let tracks: [AVAssetWriterInput]
    private let pcm: CMAudioFormatDescription
    private let timecodeTrack: TimecodeTrack
    private var wroteTimecode = false

    public init(
        url: URL, description: AudioFileDescription, firstTick: Int64, timecode: Timecode, grid: TickGrid = .recording
    ) throws(AudioFileWriterError) {
        precondition(timecode.framesPerSecond == grid.framesPerSecond, "the timecode counts the tick grid's frames")
        self.url = url
        self.firstTick = firstTick
        self.description = description
        self.grid = grid
        self.timecode = timecode
        do {
            writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        } catch {
            throw AudioFileWriterError(error, while: "cannot create \(url.lastPathComponent)")
        }
        writer.movieFragmentInterval = CMTime(value: CMTimeValue(RecorderValues.fragmentSeconds), timescale: 1)
        writer.shouldOptimizeForNetworkUse = false
        writer.metadata = movieMetadataItems(description.items)
        tracks = description.trackNames.map {
            aacTrack(channels: description.channelsPerTrack, bitRate: description.bitRatePerTrack, name: $0)
        }
        do {
            pcm = try pcmFormat(channels: description.channelsPerTrack)
            timecodeTrack = try TimecodeTrack(reelName: description.reelName, grid: grid)
        } catch {
            throw AudioFileWriterError(nil, while: error.description)
        }
        guard tracks.allSatisfy(writer.canAdd), writer.canAdd(timecodeTrack.input) else {
            throw AudioFileWriterError(nil, while: "cannot add the tracks to \(url.lastPathComponent)")
        }
        tracks.forEach(writer.add)
        writer.add(timecodeTrack.input)
        for track in tracks {
            track.addTrackAssociation(withTrackOf: timecodeTrack.input, type: AVAssetTrack.AssociationType.timecode.rawValue)
        }
        guard writer.startWriting() else {
            throw AudioFileWriterError(writer.error, while: "cannot start writing \(url.lastPathComponent)")
        }
        writer.startSession(atSourceTime: startTime)
    }

    private var startTime: CMTime { CMTime(value: firstTick, timescale: CMTimeScale(grid.framesPerSecond)) }

    /// The time of a sample `position` samples from the file's first tick.
    private func time(ofPosition position: Int64) -> CMTime {
        CMTimeAdd(startTime, CMTime(value: position, timescale: CMTimeScale(RecorderValues.audioSampleRate)))
    }

    /// Whether the writer takes another buffer now.
    public var isReady: Bool {
        tracks.allSatisfy(\.isReadyForMoreMediaData) && (wroteTimecode || timecodeTrack.input.isReadyForMoreMediaData)
    }

    /// Writes one array of samples per channel of the source, the first
    /// sample at `position` samples from the file's first tick; false when
    /// the writer is not ready, so the buffer waits.
    public func append(_ channels: [[Float]], at position: Int64) throws(AudioFileWriterError) -> Bool {
        precondition(channels.count == description.channelCount,
                     "\(description.sourceName) has \(description.channelCount) channels, not \(channels.count)")
        let frameCount = channels[0].count
        precondition(channels.allSatisfy { $0.count == frameCount }, "every channel of a buffer has as many samples")
        try checkStatus()
        guard isReady else { return false }
        guard frameCount > 0 else { return true }
        do {
            if !wroteTimecode {
                wroteTimecode = true
                guard try timecodeTrack.write(timecode, tick: firstTick) else {
                    throw AudioFileWriterError(writer.error, while: "cannot write \(url.lastPathComponent)")
                }
            }
            let perTrack = description.channelsPerTrack
            for (index, track) in tracks.enumerated() {
                let sample = try pcmSample(channels[index * perTrack..<(index + 1) * perTrack], format: pcm, at: time(ofPosition: position))
                guard track.append(sample) else {
                    throw AudioFileWriterError(writer.error, while: "cannot write \(url.lastPathComponent)")
                }
            }
        } catch let error as MovieTrackError {
            throw AudioFileWriterError(nil, while: error.description)
        } catch let error as AudioFileWriterError {
            throw error
        } catch {
            throw AudioFileWriterError(error, while: "cannot write \(url.lastPathComponent)")
        }
        return true
    }

    /// Writes `count` samples of silence at `position`, as for a filled gap.
    public func appendSilence(_ count: Int64, at position: Int64) throws(AudioFileWriterError) -> Bool {
        let silence = [Float](repeating: 0, count: Int(count))
        return try append(Array(repeating: silence, count: description.channelCount), at: position)
    }

    private func checkStatus() throws(AudioFileWriterError) {
        if writer.status == .failed {
            throw AudioFileWriterError(writer.error, while: "cannot write \(url.lastPathComponent)")
        }
    }

    /// Finalizes the file, ending it after `endPosition` samples from its
    /// first tick, nil when nothing was written.
    public func finish(endPosition: Int64?) async throws(AudioFileWriterError) {
        try checkStatus()
        if let endPosition { writer.endSession(atSourceTime: time(ofPosition: endPosition)) }
        tracks.forEach { $0.markAsFinished() }
        if !wroteTimecode { timecodeTrack.input.markAsFinished() }
        await writer.finishWriting()
        if writer.status != .completed {
            throw AudioFileWriterError(writer.error, while: "cannot finalize \(url.lastPathComponent)")
        }
    }
}
