import AVFoundation
import CoreMedia
import IOSurface
import RecorderLogic
import VideoToolbox

public struct ScreenFileWriterError: ErrorWithDetail, Equatable, CustomStringConvertible {
    /// What failed, with the error macOS gave, if any, and its full chain.
    public let detail: ErrorDetail
    /// The disk is full: the file ends, readable up to its last fragment.
    public let isDiskFull: Bool

    public init(detail: ErrorDetail, isDiskFull: Bool) {
        self.detail = detail
        self.isDiskFull = isDiskFull
    }

    public init(description: String, isDiskFull: Bool) {
        self.init(detail: ErrorDetail(message: description), isDiskFull: isDiskFull)
    }

    init(_ error: (any Error)?, while doing: String) {
        self.init(detail: ErrorDetail(message: doing, underlying: error), isDiskFull: error.map(isDiskFullError) ?? false)
    }

    public var description: String { detail.text }
}

/// A screen file: HEVC 8-bit in a fragmented `.mov`, a keyframe and a
/// fragment every 2 s, tagged BT.709, with the timecode track carrying the
/// reel name, its guide tracks, and metadata items (D21, D24, D31, D46,
/// D49). Every frame carries exactly its tick's time on the shared clock.
/// Not thread-safe: one queue uses it.
public final class ScreenFileWriter: ScreenFileWriting {
    public let url: URL
    public let firstTick: Int64
    private let grid: TickGrid
    private let timecode: Timecode
    private let writer: AVAssetWriter
    private let video: AVAssetWriterInput
    private let adaptor: AVAssetWriterInputPixelBufferAdaptor
    private let timecodeTrack: TimecodeTrack
    private var wroteTimecode = false
    private var appends: InputAppends
    private var failureTold = false
    /// The last buffer handed to the adaptor, and whether it was the one before again.
    private var lastBuffer: CVPixelBuffer?
    private var lastBufferWasRepeat = false
    private var wasReady: Bool?
    private let guides: [GuideTrack: (track: AVAssetWriterInput, pcm: CMAudioFormatDescription)]

    public init(
        url: URL, frameSize: FrameSize, firstTick: Int64, timecode: Timecode, metadata: ScreenFileMetadata,
        guideTracks: [GuideTrack] = [], grid: TickGrid = .recording
    ) throws(ScreenFileWriterError) {
        precondition(timecode.framesPerSecond == grid.framesPerSecond, "the timecode counts the tick grid's frames")
        self.url = url
        self.firstTick = firstTick
        self.grid = grid
        self.timecode = timecode
        do {
            writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        } catch {
            throw ScreenFileWriterError(error, while: "cannot create \(url.lastPathComponent)")
        }
        writer.movieFragmentInterval = CMTime(value: CMTimeValue(RecorderValues.fragmentSeconds), timescale: 1)
        writer.shouldOptimizeForNetworkUse = false
        writer.metadata = movieMetadataItems(metadata.items)

        let settings = Self.videoSettings(frameSize, grid: grid)
        video = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
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
            throw ScreenFileWriterError(nil, while: error.description)
        }
        self.guides = guides
        appends = InputAppends(inputs: [Self.videoName] + guideTracks.map(Self.name(of:)) + [Self.timecodeName])

        let guideInputs = guideTracks.compactMap { guides[$0]?.0 }
        guard writer.canAdd(video), writer.canAdd(timecodeTrack.input), guideInputs.allSatisfy(writer.canAdd) else {
            throw ScreenFileWriterError(nil, while: "cannot add the tracks to \(url.lastPathComponent)")
        }
        writer.add(video)
        guideInputs.forEach(writer.add)
        writer.add(timecodeTrack.input)
        video.addTrackAssociation(withTrackOf: timecodeTrack.input, type: AVAssetTrack.AssociationType.timecode.rawValue)
        guard writer.startWriting() else {
            throw ScreenFileWriterError(writer.error, while: "cannot start writing \(url.lastPathComponent)")
        }
        writer.startSession(atSourceTime: time(ofTick: firstTick))
        RecorderLog.detail("video settings of \(url.lastPathComponent): \(SettingsText.text(settings))", category: Self.detailCategory)
        RecorderLog.detail(Self.encoderList(), category: Self.detailCategory)
    }

    /// The encoders VideoToolbox lists for HEVC.
    private static func encoderList() -> String {
        var list: CFArray?
        let status = VTCopyVideoEncoderList(nil, &list)
        guard status == noErr, let entries = list as? [[String: Any]] else {
            return "video encoders cannot be listed (error \(ErrorDetail.codeText(Int(status))))"
        }
        let encoders = entries
            .filter { ($0[kVTVideoEncoderList_CodecType as String] as? NSNumber)?.uint32Value == kCMVideoCodecType_HEVC }
            .map {
                EncoderListText.Encoder(
                    name: $0[kVTVideoEncoderList_EncoderName as String] as? String ?? "unnamed",
                    id: $0[kVTVideoEncoderList_EncoderID as String] as? String ?? "no ID",
                    isHardwareAccelerated: ($0[kVTVideoEncoderList_IsHardwareAccelerated as String] as? Bool) ?? false)
            }
        return EncoderListText.text(codec: FrameFacts.fourCharacterCode(kCMVideoCodecType_HEVC), encoders)
    }

    /// The category of the detail lines about the capture's frames and this writer's inputs (D66).
    static let detailCategory = "capture"
    private static let videoName = "video"
    private static let timecodeName = "timecode"
    private static func name(of guide: GuideTrack) -> String { "guide track \(guide.name)" }

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
    public var isReady: Bool {
        let videoReady = video.isReadyForMoreMediaData
        if videoReady != wasReady {
            if wasReady != nil || !videoReady {
                RecorderLog.detail("video input of \(url.lastPathComponent) ready for more media data: \(videoReady)",
                                   category: Self.detailCategory)
            }
            wasReady = videoReady
        }
        return videoReady && (wroteTimecode || timecodeTrack.input.isReadyForMoreMediaData)
    }

    /// Writes a tick's frame with exactly the tick's time and its timecode;
    /// false when the writer is not ready, so the tick waits.
    public func append(_ pixelBuffer: CVPixelBuffer, tick: Int64) throws(ScreenFileWriterError) -> Bool {
        try checkStatus()
        guard isReady else { return false }
        if !wroteTimecode {
            wroteTimecode = true
            let wrote: Bool
            do {
                wrote = try timecodeTrack.write(timecode, tick: firstTick)
            } catch {
                throw ScreenFileWriterError(nil, while: error.description)
            }
            guard wrote else {
                appends.refused(Self.timecodeName)
                throw failed("cannot write \(url.lastPathComponent)")
            }
            appends.appended(Self.timecodeName, at: time(ofTick: firstTick).seconds)
        }
        lastBufferWasRepeat = lastBuffer === pixelBuffer
        lastBuffer = pixelBuffer
        guard adaptor.append(pixelBuffer, withPresentationTime: time(ofTick: tick)) else {
            appends.refused(Self.videoName)
            throw failed("cannot write \(url.lastPathComponent)")
        }
        appends.appended(Self.videoName, at: time(ofTick: tick).seconds)
        return true
    }

    /// Writes samples of a guide track, one array per channel, the first at
    /// `position` samples from the file's first tick; false when the track
    /// is not ready, so they wait. A guide track the file does not have
    /// takes nothing.
    public func appendGuide(_ guide: GuideTrack, _ channels: [[Float]], at position: Int64) throws(ScreenFileWriterError) -> Bool {
        try checkStatus()
        guard let (track, pcm) = guides[guide] else { return true }
        guard channels.first?.isEmpty == false else { return true }
        guard track.isReadyForMoreMediaData else { return false }
        let time = CMTimeAdd(time(ofTick: firstTick), CMTime(value: position, timescale: CMTimeScale(RecorderValues.audioSampleRate)))
        let sample: CMSampleBuffer
        do {
            sample = try pcmSample(channels[...], format: pcm, at: time)
        } catch {
            throw ScreenFileWriterError(nil, while: error.description)
        }
        guard track.append(sample) else {
            appends.refused(Self.name(of: guide))
            throw failed("cannot write \(url.lastPathComponent)")
        }
        appends.appended(Self.name(of: guide), at: time.seconds)
        return true
    }

    private func checkStatus() throws(ScreenFileWriterError) {
        if writer.status == .failed { throw failed("cannot write \(url.lastPathComponent)") }
    }

    /// The writer's error as the recorder's, with one detail line, the first time, on what
    /// each input took (D66).
    private func failed(_ doing: String) -> ScreenFileWriterError {
        if !failureTold {
            failureTold = true
            let error = writer.error.map { ErrorDetail($0).text } ?? "none"
            RecorderLog.detail(
                "writer of \(url.lastPathComponent) failed: status \(Self.statusName(writer.status)), error \(error); \(appends.text); \(lastBufferText)",
                category: Self.detailCategory)
        }
        return ScreenFileWriterError(writer.error, while: doing)
    }

    /// "last buffer 1600×900, IOSurface ID 4711, a repeat of the one before: no"
    private var lastBufferText: String {
        guard let lastBuffer else { return "no buffer was handed over" }
        let surface = CVPixelBufferGetIOSurface(lastBuffer).map { "\(IOSurfaceGetID($0.takeUnretainedValue()))" } ?? "none"
        return "last buffer \(CVPixelBufferGetWidth(lastBuffer))×\(CVPixelBufferGetHeight(lastBuffer)), IOSurface ID \(surface), "
            + "a repeat of the one before: \(lastBufferWasRepeat ? "yes" : "no")"
    }

    private static func statusName(_ status: AVAssetWriter.Status) -> String {
        switch status {
        case .unknown: "unknown"
        case .writing: "writing"
        case .completed: "completed"
        case .failed: "failed"
        case .cancelled: "cancelled"
        @unknown default: "\(status.rawValue)"
        }
    }

    /// Finalizes the file after its last tick.
    public func finish(lastTick: Int64?) async throws(ScreenFileWriterError) {
        try checkStatus()
        if let lastTick { writer.endSession(atSourceTime: time(ofTick: lastTick + 1)) }
        video.markAsFinished()
        for (track, _) in guides.values { track.markAsFinished() }
        if !wroteTimecode { timecodeTrack.input.markAsFinished() }
        await writer.finishWriting()
        if writer.status != .completed {
            throw failed("cannot finalize \(url.lastPathComponent)")
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
