import AVFoundation
import CoreMedia
import RecorderLogic
import VideoToolbox

public struct DisplayFileWriterError: Error, CustomStringConvertible {
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

/// A display file: HEVC 8-bit in a fragmented `.mov`, a keyframe and a
/// fragment every 2 s, tagged BT.709, with a timecode track (D21, D24,
/// D31). Every frame carries exactly its tick's time on the shared clock.
/// Not thread-safe: one queue uses it.
public final class DisplayFileWriter {
    public let url: URL
    public let firstTick: Int64
    private let grid: TickGrid
    private let timecode: Timecode
    private let writer: AVAssetWriter
    private let video: AVAssetWriterInput
    private let adaptor: AVAssetWriterInputPixelBufferAdaptor
    private let timecodeTrack: AVAssetWriterInput
    private let timecodeFormat: CMTimeCodeFormatDescription

    public init(url: URL, frameSize: FrameSize, firstTick: Int64, timecode: Timecode, grid: TickGrid = .recording) throws(DisplayFileWriterError) {
        precondition(timecode.framesPerSecond == grid.framesPerSecond, "the timecode counts the tick grid's frames")
        self.url = url
        self.firstTick = firstTick
        self.grid = grid
        self.timecode = timecode
        do {
            writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        } catch {
            throw DisplayFileWriterError(error, while: "cannot create \(url.lastPathComponent)")
        }
        writer.movieFragmentInterval = CMTime(value: CMTimeValue(RecorderValues.fragmentSeconds), timescale: 1)
        writer.shouldOptimizeForNetworkUse = false

        video = AVAssetWriterInput(mediaType: .video, outputSettings: Self.videoSettings(frameSize, grid: grid))
        video.expectsMediaDataInRealTime = true
        adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: video, sourcePixelBufferAttributes: nil)

        var format: CMTimeCodeFormatDescription?
        let status = CMTimeCodeFormatDescriptionCreate(
            allocator: nil, timeCodeFormatType: kCMTimeCodeFormatType_TimeCode32,
            frameDuration: CMTime(value: 1, timescale: CMTimeScale(grid.framesPerSecond)),
            frameQuanta: UInt32(grid.framesPerSecond), flags: kCMTimeCodeFlag_24HourMax, extensions: nil,
            formatDescriptionOut: &format)
        guard status == noErr, let format else {
            throw DisplayFileWriterError(nil, while: "cannot describe the timecode track (error \(status))")
        }
        timecodeFormat = format
        timecodeTrack = AVAssetWriterInput(mediaType: .timecode, outputSettings: nil, sourceFormatHint: format)
        timecodeTrack.expectsMediaDataInRealTime = true

        guard writer.canAdd(video), writer.canAdd(timecodeTrack) else {
            throw DisplayFileWriterError(nil, while: "cannot add the tracks to \(url.lastPathComponent)")
        }
        writer.add(video)
        writer.add(timecodeTrack)
        video.addTrackAssociation(withTrackOf: timecodeTrack, type: AVAssetTrack.AssociationType.timecode.rawValue)
        guard writer.startWriting() else {
            throw DisplayFileWriterError(writer.error, while: "cannot start writing \(url.lastPathComponent)")
        }
        writer.startSession(atSourceTime: time(ofTick: firstTick))
    }

    static func videoSettings(_ frameSize: FrameSize, grid: TickGrid) -> [String: Any] {
        [
            AVVideoCodecKey: AVVideoCodecType.hevc,
            AVVideoWidthKey: frameSize.width,
            AVVideoHeightKey: frameSize.height,
            AVVideoEncoderSpecificationKey: [
                kVTVideoEncoderSpecification_EnableHardwareAcceleratedVideoEncoder as String: true,
            ],
            AVVideoCompressionPropertiesKey: [
                AVVideoQualityKey: Encoding.videoQuality,
                kVTCompressionPropertyKey_DataRateLimits as String: [Encoding.videoCeilingBytesPerSecond(frameSize: frameSize), 1],
                AVVideoMaxKeyFrameIntervalKey: Encoding.keyframeIntervalSeconds * grid.framesPerSecond,
                AVVideoMaxKeyFrameIntervalDurationKey: Encoding.keyframeIntervalSeconds,
                AVVideoExpectedSourceFrameRateKey: grid.framesPerSecond,
                AVVideoAllowFrameReorderingKey: false,
            ],
            AVVideoColorPropertiesKey: [
                AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
                AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
                AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2,
            ],
        ]
    }

    private func time(ofTick tick: Int64) -> CMTime {
        CMTime(value: tick, timescale: CMTimeScale(grid.framesPerSecond))
    }

    /// Whether the writer takes another frame now.
    public var isReady: Bool { video.isReadyForMoreMediaData && timecodeTrack.isReadyForMoreMediaData }

    /// Writes a tick's frame with exactly the tick's time and its timecode;
    /// false when the writer is not ready, so the tick waits.
    public func append(_ pixelBuffer: CVPixelBuffer, tick: Int64) throws(DisplayFileWriterError) -> Bool {
        try checkStatus()
        guard isReady else { return false }
        let timecodeSample = try timecodeSample(tick: tick)
        guard adaptor.append(pixelBuffer, withPresentationTime: time(ofTick: tick)),
              timecodeTrack.append(timecodeSample)
        else {
            throw DisplayFileWriterError(writer.error, while: "cannot write \(url.lastPathComponent)")
        }
        return true
    }

    private func checkStatus() throws(DisplayFileWriterError) {
        if writer.status == .failed {
            throw DisplayFileWriterError(writer.error, while: "cannot write \(url.lastPathComponent)")
        }
    }

    /// One timecode sample per tick, so the track covers the file up to its
    /// last fragment also when the file is not finalized.
    private func timecodeSample(tick: Int64) throws(DisplayFileWriterError) -> CMSampleBuffer {
        var frame = Int32(truncatingIfNeeded: timecode.frame(ofTick: tick)).bigEndian
        var block: CMBlockBuffer?
        var status = CMBlockBufferCreateWithMemoryBlock(
            allocator: nil, memoryBlock: nil, blockLength: MemoryLayout<Int32>.size, blockAllocator: nil,
            customBlockSource: nil, offsetToData: 0, dataLength: MemoryLayout<Int32>.size, flags: 0, blockBufferOut: &block)
        guard status == noErr, let block else {
            throw DisplayFileWriterError(nil, while: "cannot make a timecode sample (error \(status))")
        }
        status = CMBlockBufferReplaceDataBytes(
            with: &frame, blockBuffer: block, offsetIntoDestination: 0, dataLength: MemoryLayout<Int32>.size)
        var timing = CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: CMTimeScale(grid.framesPerSecond)),
            presentationTimeStamp: time(ofTick: tick), decodeTimeStamp: .invalid)
        var size = MemoryLayout<Int32>.size
        var sample: CMSampleBuffer?
        status = CMSampleBufferCreate(
            allocator: nil, dataBuffer: block, dataReady: true, makeDataReadyCallback: nil, refcon: nil,
            formatDescription: timecodeFormat, sampleCount: 1, sampleTimingEntryCount: 1, sampleTimingArray: &timing,
            sampleSizeEntryCount: 1, sampleSizeArray: &size, sampleBufferOut: &sample)
        guard status == noErr, let sample else {
            throw DisplayFileWriterError(nil, while: "cannot make a timecode sample (error \(status))")
        }
        return sample
    }

    /// Finalizes the file after its last tick.
    public func finish(lastTick: Int64?) async throws(DisplayFileWriterError) {
        try checkStatus()
        if let lastTick { writer.endSession(atSourceTime: time(ofTick: lastTick + 1)) }
        video.markAsFinished()
        timecodeTrack.markAsFinished()
        await writer.finishWriting()
        if writer.status != .completed {
            throw DisplayFileWriterError(writer.error, while: "cannot finalize \(url.lastPathComponent)")
        }
    }
}

/// Whether an error, or one under it, says the disk is full.
func isDiskFullError(_ error: any Error) -> Bool {
    let nsError = error as NSError
    if nsError.domain == AVFoundationErrorDomain, nsError.code == AVError.Code.diskFull.rawValue { return true }
    if nsError.domain == NSPOSIXErrorDomain, nsError.code == Int(ENOSPC) { return true }
    if nsError.domain == NSCocoaErrorDomain, nsError.code == NSFileWriteOutOfSpaceError { return true }
    return nsError.underlyingErrors.contains(where: isDiskFullError)
}
