import AVFoundation
import CoreMedia
import RecorderLogic

/// Why a track or a sample of a movie could not be made.
struct MovieTrackError: Error {
    let description: String
}

/// The timecode track every screen file and audio file carries (D21, D31,
/// D46): one sample, at the file's first tick, with the source as its reel
/// name. The writer finishes the track right after that sample, so the
/// writer can write the fragments without waiting for it and a file that is
/// never finalized still carries the timecode.
struct TimecodeTrack {
    let input: AVAssetWriterInput
    private let format: CMTimeCodeFormatDescription
    private let grid: TickGrid

    init(reelName: String, grid: TickGrid) throws(MovieTrackError) {
        self.grid = grid
        var format: CMTimeCodeFormatDescription?
        let status = CMTimeCodeFormatDescriptionCreate(
            allocator: nil, timeCodeFormatType: kCMTimeCodeFormatType_TimeCode32,
            frameDuration: CMTime(value: 1, timescale: CMTimeScale(grid.framesPerSecond)),
            frameQuanta: UInt32(grid.framesPerSecond), flags: kCMTimeCodeFlag_24HourMax,
            extensions: [
                kCMTimeCodeFormatDescriptionExtension_SourceReferenceName: [
                    kCMTimeCodeFormatDescriptionKey_Value: reelName,
                    kCMTimeCodeFormatDescriptionKey_LangCode: 0,
                ] as CFDictionary,
            ] as CFDictionary,
            formatDescriptionOut: &format)
        guard status == noErr, let format else {
            throw MovieTrackError(description: "cannot describe the timecode track (error \(status))")
        }
        self.format = format
        input = AVAssetWriterInput(mediaType: .timecode, outputSettings: nil, sourceFormatHint: format)
        input.expectsMediaDataInRealTime = true
    }

    /// Writes the one sample, the timecode of `tick`, and finishes the track.
    func write(_ timecode: Timecode, tick: Int64) throws(MovieTrackError) -> Bool {
        let sample = try sample(frame: timecode.frame(ofTick: tick), tick: tick)
        guard input.append(sample) else { return false }
        input.markAsFinished()
        return true
    }

    private func sample(frame: Int64, tick: Int64) throws(MovieTrackError) -> CMSampleBuffer {
        var value = Int32(truncatingIfNeeded: frame).bigEndian
        var block: CMBlockBuffer?
        var status = CMBlockBufferCreateWithMemoryBlock(
            allocator: nil, memoryBlock: nil, blockLength: MemoryLayout<Int32>.size, blockAllocator: nil,
            customBlockSource: nil, offsetToData: 0, dataLength: MemoryLayout<Int32>.size, flags: 0, blockBufferOut: &block)
        guard status == noErr, let block else {
            throw MovieTrackError(description: "cannot make a timecode sample (error \(status))")
        }
        status = CMBlockBufferReplaceDataBytes(
            with: &value, blockBuffer: block, offsetIntoDestination: 0, dataLength: MemoryLayout<Int32>.size)
        var timing = CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: CMTimeScale(grid.framesPerSecond)),
            presentationTimeStamp: CMTime(value: tick, timescale: CMTimeScale(grid.framesPerSecond)), decodeTimeStamp: .invalid)
        var size = MemoryLayout<Int32>.size
        var sample: CMSampleBuffer?
        if status == noErr {
            status = CMSampleBufferCreate(
                allocator: nil, dataBuffer: block, dataReady: true, makeDataReadyCallback: nil, refcon: nil,
                formatDescription: format, sampleCount: 1, sampleTimingEntryCount: 1, sampleTimingArray: &timing,
                sampleSizeEntryCount: 1, sampleSizeArray: &size, sampleBufferOut: &sample)
        }
        guard status == noErr, let sample else {
            throw MovieTrackError(description: "cannot make a timecode sample (error \(status))")
        }
        return sample
    }
}

/// QuickTime metadata items of a file, all text.
func movieMetadataItems(_ items: [(key: String, value: String)]) -> [AVMetadataItem] {
    items.map { key, value in
        let item = AVMutableMetadataItem()
        item.keySpace = .quickTimeMetadata
        item.key = key as NSString
        item.value = value as NSString
        return item
    }
}

/// A track's name, as the user data full name (`©nam`): the one track-level
/// item `ffprobe` shows, as the stream's `title` (the check of 2026-11-16).
func trackNameItem(_ name: String) -> AVMetadataItem {
    let item = AVMutableMetadataItem()
    item.identifier = .quickTimeUserDataFullName
    item.value = name as NSString
    return item
}

/// An AAC-LC track at the audio sample rate, taking 32-bit float PCM.
func aacTrack(channels: Int, bitRate: Int, name: String) -> AVAssetWriterInput {
    let track = AVAssetWriterInput(mediaType: .audio, outputSettings: [
        AVFormatIDKey: kAudioFormatMPEG4AAC,
        AVSampleRateKey: RecorderValues.audioSampleRate,
        AVNumberOfChannelsKey: channels,
        AVEncoderBitRateKey: bitRate,
    ])
    track.expectsMediaDataInRealTime = true
    track.metadata = [trackNameItem(name)]
    return track
}

/// 32-bit float PCM at the audio sample rate, interleaved when stereo.
func pcmFormat(channels: Int) throws(MovieTrackError) -> CMAudioFormatDescription {
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
        throw MovieTrackError(description: "cannot describe the PCM of \(channels) channels (error \(status))")
    }
    return format
}

/// A buffer of PCM in `format` from one array of samples per channel, interleaved into it.
func pcmSample(_ channels: ArraySlice<[Float]>, format: CMAudioFormatDescription, at time: CMTime) throws(MovieTrackError) -> CMSampleBuffer {
    let frameCount = channels.first?.count ?? 0
    let interleaved = channels.count == 1
        ? channels.first!
        : (0..<frameCount).flatMap { frame in channels.map { $0[frame] } }
    let length = interleaved.count * MemoryLayout<Float>.size
    var block: CMBlockBuffer?
    var status = CMBlockBufferCreateWithMemoryBlock(
        allocator: nil, memoryBlock: nil, blockLength: length, blockAllocator: nil, customBlockSource: nil,
        offsetToData: 0, dataLength: length, flags: kCMBlockBufferAssureMemoryNowFlag, blockBufferOut: &block)
    guard status == noErr, let block else {
        throw MovieTrackError(description: "cannot make an audio sample (error \(status))")
    }
    status = interleaved.withUnsafeBytes { bytes in
        CMBlockBufferReplaceDataBytes(with: bytes.baseAddress!, blockBuffer: block, offsetIntoDestination: 0, dataLength: length)
    }
    var sample: CMSampleBuffer?
    if status == noErr {
        status = CMAudioSampleBufferCreateReadyWithPacketDescriptions(
            allocator: nil, dataBuffer: block, formatDescription: format, sampleCount: frameCount,
            presentationTimeStamp: time, packetDescriptions: nil, sampleBufferOut: &sample)
    }
    guard status == noErr, let sample else {
        throw MovieTrackError(description: "cannot make an audio sample (error \(status))")
    }
    return sample
}
