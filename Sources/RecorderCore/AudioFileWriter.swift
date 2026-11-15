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
/// audio track for the system audio, with a timecode track of one sample
/// carrying the source as its reel name, and metadata items (D45, D46).
/// Samples are placed by count from the file's first tick.
/// Not thread-safe: one queue uses it.
public final class AudioFileWriter {
    public let url: URL
    public let firstTick: Int64
    public let description: AudioFileDescription
    private let grid: TickGrid
    private let timecode: Timecode
    private let writer: AVAssetWriter
    private let tracks: [AVAssetWriterInput]
    private let pcmFormat: CMAudioFormatDescription
    private let timecodeTrack: AVAssetWriterInput
    private let timecodeFormat: CMTimeCodeFormatDescription
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
        writer.metadata = description.metadata.map { item in
            let metadata = AVMutableMetadataItem()
            metadata.keySpace = .quickTimeMetadata
            metadata.key = item.key as NSString
            metadata.value = item.value as NSString
            return metadata
        }

        tracks = description.trackNames.map { name in
            let track = AVAssetWriterInput(mediaType: .audio, outputSettings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: RecorderValues.audioSampleRate,
                AVNumberOfChannelsKey: description.channelsPerTrack,
                AVEncoderBitRateKey: description.bitRatePerTrack,
            ])
            track.expectsMediaDataInRealTime = true
            let title = AVMutableMetadataItem()
            title.identifier = .quickTimeUserDataTrackName
            title.value = name as NSString
            track.metadata = [title]
            return track
        }
        pcmFormat = try Self.pcmFormat(channels: description.channelsPerTrack)

        var format: CMTimeCodeFormatDescription?
        let reelName = [
            kCMTimeCodeFormatDescriptionExtension_SourceReferenceName: [
                kCMTimeCodeFormatDescriptionKey_Value: description.reelName,
                kCMTimeCodeFormatDescriptionKey_LangCode: 0,
            ] as CFDictionary,
        ] as CFDictionary
        let status = CMTimeCodeFormatDescriptionCreate(
            allocator: nil, timeCodeFormatType: kCMTimeCodeFormatType_TimeCode32,
            frameDuration: CMTime(value: 1, timescale: CMTimeScale(grid.framesPerSecond)),
            frameQuanta: UInt32(grid.framesPerSecond), flags: kCMTimeCodeFlag_24HourMax, extensions: reelName,
            formatDescriptionOut: &format)
        guard status == noErr, let format else {
            throw AudioFileWriterError(nil, while: "cannot describe the timecode track (error \(status))")
        }
        timecodeFormat = format
        timecodeTrack = AVAssetWriterInput(mediaType: .timecode, outputSettings: nil, sourceFormatHint: format)
        timecodeTrack.expectsMediaDataInRealTime = true

        guard tracks.allSatisfy(writer.canAdd), writer.canAdd(timecodeTrack) else {
            throw AudioFileWriterError(nil, while: "cannot add the tracks to \(url.lastPathComponent)")
        }
        tracks.forEach(writer.add)
        writer.add(timecodeTrack)
        for track in tracks {
            track.addTrackAssociation(withTrackOf: timecodeTrack, type: AVAssetTrack.AssociationType.timecode.rawValue)
        }
        guard writer.startWriting() else {
            throw AudioFileWriterError(writer.error, while: "cannot start writing \(url.lastPathComponent)")
        }
        writer.startSession(atSourceTime: startTime)
    }

    /// The PCM the writer takes: 32-bit floats, interleaved for a stereo track.
    private static func pcmFormat(channels: Int) throws(AudioFileWriterError) -> CMAudioFormatDescription {
        var stream = AudioStreamBasicDescription(
            mSampleRate: Double(RecorderValues.audioSampleRate), mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked,
            mBytesPerPacket: UInt32(4 * channels), mFramesPerPacket: 1, mBytesPerFrame: UInt32(4 * channels),
            mChannelsPerFrame: UInt32(channels), mBitsPerChannel: 32, mReserved: 0)
        var format: CMAudioFormatDescription?
        let status = CMAudioFormatDescriptionCreate(
            allocator: nil, asbd: &stream, layoutSize: 0, layout: nil, magicCookieSize: 0, magicCookie: nil,
            extensions: nil, formatDescriptionOut: &format)
        guard status == noErr, let format else {
            throw AudioFileWriterError(nil, while: "cannot describe the PCM of \(channels) channels (error \(status))")
        }
        return format
    }

    private var startTime: CMTime { CMTime(value: firstTick, timescale: CMTimeScale(grid.framesPerSecond)) }

    /// The time of a sample `position` samples from the file's first tick.
    private func time(ofPosition position: Int64) -> CMTime {
        CMTimeAdd(startTime, CMTime(value: position, timescale: CMTimeScale(RecorderValues.audioSampleRate)))
    }

    /// Whether the writer takes another buffer now.
    public var isReady: Bool {
        tracks.allSatisfy(\.isReadyForMoreMediaData) && (wroteTimecode || timecodeTrack.isReadyForMoreMediaData)
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
        if !wroteTimecode {
            wroteTimecode = true
            guard timecodeTrack.append(try timecodeSample()) else {
                throw AudioFileWriterError(writer.error, while: "cannot write \(url.lastPathComponent)")
            }
            timecodeTrack.markAsFinished()
        }
        let perTrack = description.channelsPerTrack
        for (index, track) in tracks.enumerated() {
            let trackChannels = channels[index * perTrack..<(index + 1) * perTrack]
            let interleaved = (0..<frameCount).flatMap { frame in trackChannels.map { $0[frame] } }
            guard track.append(try pcmSample(interleaved, frameCount: frameCount, at: time(ofPosition: position))) else {
                throw AudioFileWriterError(writer.error, while: "cannot write \(url.lastPathComponent)")
            }
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

    private func pcmSample(_ samples: [Float], frameCount: Int, at time: CMTime) throws(AudioFileWriterError) -> CMSampleBuffer {
        let length = samples.count * MemoryLayout<Float>.size
        var block: CMBlockBuffer?
        var status = CMBlockBufferCreateWithMemoryBlock(
            allocator: nil, memoryBlock: nil, blockLength: length, blockAllocator: nil, customBlockSource: nil,
            offsetToData: 0, dataLength: length, flags: kCMBlockBufferAssureMemoryNowFlag, blockBufferOut: &block)
        guard status == noErr, let block else {
            throw AudioFileWriterError(nil, while: "cannot make an audio sample (error \(status))")
        }
        status = samples.withUnsafeBytes { bytes in
            CMBlockBufferReplaceDataBytes(with: bytes.baseAddress!, blockBuffer: block, offsetIntoDestination: 0, dataLength: length)
        }
        var sample: CMSampleBuffer?
        if status == noErr {
            status = CMAudioSampleBufferCreateReadyWithPacketDescriptions(
                allocator: nil, dataBuffer: block, formatDescription: pcmFormat, sampleCount: frameCount,
                presentationTimeStamp: time, packetDescriptions: nil, sampleBufferOut: &sample)
        }
        guard status == noErr, let sample else {
            throw AudioFileWriterError(nil, while: "cannot make an audio sample (error \(status))")
        }
        return sample
    }

    /// The file's one timecode sample, at its first tick, as in a display
    /// file; the timecode track is then finished, so the writer can write
    /// the fragments without waiting for it.
    private func timecodeSample() throws(AudioFileWriterError) -> CMSampleBuffer {
        var frame = Int32(truncatingIfNeeded: timecode.frame(ofTick: firstTick)).bigEndian
        var block: CMBlockBuffer?
        var status = CMBlockBufferCreateWithMemoryBlock(
            allocator: nil, memoryBlock: nil, blockLength: MemoryLayout<Int32>.size, blockAllocator: nil,
            customBlockSource: nil, offsetToData: 0, dataLength: MemoryLayout<Int32>.size, flags: 0, blockBufferOut: &block)
        guard status == noErr, let block else {
            throw AudioFileWriterError(nil, while: "cannot make a timecode sample (error \(status))")
        }
        status = CMBlockBufferReplaceDataBytes(
            with: &frame, blockBuffer: block, offsetIntoDestination: 0, dataLength: MemoryLayout<Int32>.size)
        var timing = CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: CMTimeScale(grid.framesPerSecond)),
            presentationTimeStamp: startTime, decodeTimeStamp: .invalid)
        var size = MemoryLayout<Int32>.size
        var sample: CMSampleBuffer?
        if status == noErr {
            status = CMSampleBufferCreate(
                allocator: nil, dataBuffer: block, dataReady: true, makeDataReadyCallback: nil, refcon: nil,
                formatDescription: timecodeFormat, sampleCount: 1, sampleTimingEntryCount: 1, sampleTimingArray: &timing,
                sampleSizeEntryCount: 1, sampleSizeArray: &size, sampleBufferOut: &sample)
        }
        guard status == noErr, let sample else {
            throw AudioFileWriterError(nil, while: "cannot make a timecode sample (error \(status))")
        }
        return sample
    }

    /// Finalizes the file, ending it after `endPosition` samples from its
    /// first tick, nil when nothing was written.
    public func finish(endPosition: Int64?) async throws(AudioFileWriterError) {
        try checkStatus()
        if let endPosition { writer.endSession(atSourceTime: time(ofPosition: endPosition)) }
        tracks.forEach { $0.markAsFinished() }
        if !wroteTimecode { timecodeTrack.markAsFinished() }
        await writer.finishWriting()
        if writer.status != .completed {
            throw AudioFileWriterError(writer.error, while: "cannot finalize \(url.lastPathComponent)")
        }
    }
}
