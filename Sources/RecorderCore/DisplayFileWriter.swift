import AVFoundation
import CoreMedia
import RecorderLogic
import VideoToolbox

public struct DisplayFileWriterError: Error, Equatable, CustomStringConvertible {
    public let description: String
    /// The disk is full: the file ends, readable up to its last fragment.
    public let isDiskFull: Bool

    public init(description: String, isDiskFull: Bool) {
        self.description = description
        self.isDiskFull = isDiskFull
    }

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
/// fragment every 2 s, tagged BT.709, with the timecode track carrying the
/// reel name, its guide tracks, and metadata items (D21, D24, D31, D46,
/// D49). Every frame carries exactly its tick's time on the shared clock.
/// Not thread-safe: one queue uses it.
public final class DisplayFileWriter: DisplayFileWriting {
    public let url: URL
    public let firstTick: Int64
    private let grid: TickGrid
    private let timecode: Timecode
    private let writer: AVAssetWriter
    private let video: AVAssetWriterInput
    private let adaptor: AVAssetWriterInputPixelBufferAdaptor
    private let timecodeTrack: TimecodeTrack
    private var wroteTimecode = false
    private let guides: [GuideTrack: (track: AVAssetWriterInput, pcm: CMAudioFormatDescription)]

    public init(
        url: URL, frameSize: FrameSize, firstTick: Int64, timecode: Timecode, metadata: DisplayFileMetadata,
        guideTracks: [GuideTrack] = [], grid: TickGrid = .recording
    ) throws(DisplayFileWriterError) {
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
        writer.metadata = movieMetadataItems(metadata.items)

        video = AVAssetWriterInput(mediaType: .video, outputSettings: Self.videoSettings(frameSize, grid: grid))
        video.expectsMediaDataInRealTime = true
        video.metadata = [trackNameItem(metadata.reelName)]
        adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: video, sourcePixelBufferAttributes: nil)
        var guides: [GuideTrack: (AVAssetWriterInput, CMAudioFormatDescription)] = [:]
        do {
            timecodeTrack = try TimecodeTrack(reelName: metadata.reelName, grid: grid)
            for guide in guideTracks {
                guides[guide] = (aacTrack(channels: guide.channelCount, bitRate: guide.bitRate, name: guide.name),
                                 try pcmFormat(channels: guide.channelCount))
            }
        } catch {
            throw DisplayFileWriterError(nil, while: error.description)
        }
        self.guides = guides

        let guideInputs = guideTracks.compactMap { guides[$0]?.0 }
        guard writer.canAdd(video), writer.canAdd(timecodeTrack.input), guideInputs.allSatisfy(writer.canAdd) else {
            throw DisplayFileWriterError(nil, while: "cannot add the tracks to \(url.lastPathComponent)")
        }
        writer.add(video)
        guideInputs.forEach(writer.add)
        writer.add(timecodeTrack.input)
        video.addTrackAssociation(withTrackOf: timecodeTrack.input, type: AVAssetTrack.AssociationType.timecode.rawValue)
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
    public var isReady: Bool { video.isReadyForMoreMediaData && (wroteTimecode || timecodeTrack.input.isReadyForMoreMediaData) }

    /// Writes a tick's frame with exactly the tick's time and its timecode;
    /// false when the writer is not ready, so the tick waits.
    public func append(_ pixelBuffer: CVPixelBuffer, tick: Int64) throws(DisplayFileWriterError) -> Bool {
        try checkStatus()
        guard isReady else { return false }
        if !wroteTimecode {
            wroteTimecode = true
            let wrote: Bool
            do {
                wrote = try timecodeTrack.write(timecode, tick: firstTick)
            } catch {
                throw DisplayFileWriterError(nil, while: error.description)
            }
            guard wrote else { throw DisplayFileWriterError(writer.error, while: "cannot write \(url.lastPathComponent)") }
        }
        guard adaptor.append(pixelBuffer, withPresentationTime: time(ofTick: tick))
        else {
            throw DisplayFileWriterError(writer.error, while: "cannot write \(url.lastPathComponent)")
        }
        return true
    }

    /// Writes samples of a guide track, one array per channel, the first at
    /// `position` samples from the file's first tick; false when the track
    /// is not ready, so they wait. A guide track the file does not have
    /// takes nothing.
    public func appendGuide(_ guide: GuideTrack, _ channels: [[Float]], at position: Int64) throws(DisplayFileWriterError) -> Bool {
        try checkStatus()
        guard let (track, pcm) = guides[guide] else { return true }
        guard channels.first?.isEmpty == false else { return true }
        guard track.isReadyForMoreMediaData else { return false }
        let time = CMTimeAdd(time(ofTick: firstTick), CMTime(value: position, timescale: CMTimeScale(RecorderValues.audioSampleRate)))
        let sample: CMSampleBuffer
        do {
            sample = try pcmSample(channels[...], format: pcm, at: time)
        } catch {
            throw DisplayFileWriterError(nil, while: error.description)
        }
        guard track.append(sample) else {
            throw DisplayFileWriterError(writer.error, while: "cannot write \(url.lastPathComponent)")
        }
        return true
    }

    private func checkStatus() throws(DisplayFileWriterError) {
        if writer.status == .failed {
            throw DisplayFileWriterError(writer.error, while: "cannot write \(url.lastPathComponent)")
        }
    }

    /// Finalizes the file after its last tick.
    public func finish(lastTick: Int64?) async throws(DisplayFileWriterError) {
        try checkStatus()
        if let lastTick { writer.endSession(atSourceTime: time(ofTick: lastTick + 1)) }
        video.markAsFinished()
        for (track, _) in guides.values { track.markAsFinished() }
        if !wroteTimecode { timecodeTrack.input.markAsFinished() }
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
