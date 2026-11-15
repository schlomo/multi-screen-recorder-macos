import AVFoundation
import CoreMedia
import Foundation
import RecorderLogic
import Testing

/// The proof behind the audio file: `AVAssetWriter` writes an audio-only
/// fragmented `.mov` with mono AAC tracks, a timecode track carrying a reel
/// name and QuickTime metadata items, and AVFoundation reads all of it back,
/// finalized or not. Plain AVFoundation, no recorder code.
@Suite(.serialized) struct AudioOnlyMovieProofTests {
    private let scratch: URL
    private let sampleRate = 48_000
    private let rate = RecorderValues.framesPerSecond
    private let reelName = "Microphone - Razer Seiren V3 Mini"
    private let metadataKey = "org.schapiro.multiscreenrecorder.sourceName"

    init() throws {
        scratch = FileManager.default.temporaryDirectory
            .appending(path: "AudioOnlyMovieProofTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
    }

    private func removeScratch() {
        try? FileManager.default.removeItem(at: scratch)
    }

    private struct Written {
        let url: URL
        let writer: AVAssetWriter
    }

    private func write(seconds: Int, firstTick: Int64, timecodeFrame: Int32, finish: Bool) async throws -> Written {
        let url = scratch.appending(path: "proof.mov")
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        writer.movieFragmentInterval = CMTime(value: CMTimeValue(RecorderValues.fragmentSeconds), timescale: 1)
        let item = AVMutableMetadataItem()
        item.keySpace = .quickTimeMetadata
        item.key = metadataKey as NSString
        item.value = "Razer Seiren V3 Mini" as NSString
        writer.metadata = [item]

        let tracks = (1...2).map { channel in
            let input = AVAssetWriterInput(mediaType: .audio, outputSettings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: sampleRate,
                AVNumberOfChannelsKey: 1,
                AVEncoderBitRateKey: 128_000,
            ])
            input.expectsMediaDataInRealTime = true
            let name = AVMutableMetadataItem()
            name.identifier = .quickTimeUserDataTrackName
            name.value = "Microphone: Razer Seiren V3 Mini, channel \(channel)" as NSString
            input.metadata = [name]
            return input
        }

        var format: CMTimeCodeFormatDescription?
        let extensions = [
            kCMTimeCodeFormatDescriptionExtension_SourceReferenceName: [
                kCMTimeCodeFormatDescriptionKey_Value: reelName,
                kCMTimeCodeFormatDescriptionKey_LangCode: 0,
            ] as CFDictionary,
        ] as CFDictionary
        #expect(CMTimeCodeFormatDescriptionCreate(
            allocator: nil, timeCodeFormatType: kCMTimeCodeFormatType_TimeCode32,
            frameDuration: CMTime(value: 1, timescale: CMTimeScale(rate)), frameQuanta: UInt32(rate),
            flags: kCMTimeCodeFlag_24HourMax, extensions: extensions, formatDescriptionOut: &format) == noErr)
        let timecodeFormat = try #require(format)
        let timecode = AVAssetWriterInput(mediaType: .timecode, outputSettings: nil, sourceFormatHint: timecodeFormat)
        timecode.expectsMediaDataInRealTime = true

        for track in tracks { #expect(writer.canAdd(track)); writer.add(track) }
        #expect(writer.canAdd(timecode))
        writer.add(timecode)
        for track in tracks {
            #expect(track.canAddTrackAssociation(withTrackOf: timecode, type: AVAssetTrack.AssociationType.timecode.rawValue))
            track.addTrackAssociation(withTrackOf: timecode, type: AVAssetTrack.AssociationType.timecode.rawValue)
        }
        #expect(writer.startWriting(), "\(String(describing: writer.error))")
        let start = CMTime(value: firstTick, timescale: CMTimeScale(rate))
        writer.startSession(atSourceTime: start)

        #expect(timecode.append(try timecodeSample(frame: timecodeFrame, at: start, format: timecodeFormat)))
        timecode.markAsFinished()

        let block = sampleRate / 100
        let blocks = seconds * 100
        for index in 0..<blocks {
            let at = CMTimeAdd(start, CMTime(value: CMTimeValue(index * block), timescale: CMTimeScale(sampleRate)))
            for (channel, track) in tracks.enumerated() {
                let samples = (0..<block).map { frame in
                    Float(0.25 * sin(2 * Double.pi * Double(440 * (channel + 1)) * Double(index * block + frame) / Double(sampleRate)))
                }
                while !track.isReadyForMoreMediaData { try await Task.sleep(for: .milliseconds(1)) }
                #expect(track.append(try monoPCM(samples, at: at)), "\(String(describing: writer.error))")
            }
        }
        if finish {
            writer.endSession(atSourceTime: CMTimeAdd(start, CMTime(value: CMTimeValue(seconds), timescale: 1)))
            for track in tracks { track.markAsFinished() }
            await writer.finishWriting()
            #expect(writer.status == .completed, "\(String(describing: writer.error))")
        }
        return Written(url: url, writer: writer)
    }

    private func monoPCM(_ samples: [Float], at time: CMTime) throws -> CMSampleBuffer {
        var description = AudioStreamBasicDescription(
            mSampleRate: Double(sampleRate), mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked, mBytesPerPacket: 4, mFramesPerPacket: 1,
            mBytesPerFrame: 4, mChannelsPerFrame: 1, mBitsPerChannel: 32, mReserved: 0)
        var format: CMAudioFormatDescription?
        #expect(CMAudioFormatDescriptionCreate(
            allocator: nil, asbd: &description, layoutSize: 0, layout: nil, magicCookieSize: 0, magicCookie: nil,
            extensions: nil, formatDescriptionOut: &format) == noErr)
        let length = samples.count * 4
        var block: CMBlockBuffer?
        #expect(CMBlockBufferCreateWithMemoryBlock(
            allocator: nil, memoryBlock: nil, blockLength: length, blockAllocator: nil, customBlockSource: nil,
            offsetToData: 0, dataLength: length, flags: kCMBlockBufferAssureMemoryNowFlag, blockBufferOut: &block) == noErr)
        _ = samples.withUnsafeBytes { bytes in
            CMBlockBufferReplaceDataBytes(with: bytes.baseAddress!, blockBuffer: block!, offsetIntoDestination: 0, dataLength: length)
        }
        var sample: CMSampleBuffer?
        #expect(CMAudioSampleBufferCreateReadyWithPacketDescriptions(
            allocator: nil, dataBuffer: try #require(block), formatDescription: try #require(format),
            sampleCount: samples.count, presentationTimeStamp: time, packetDescriptions: nil, sampleBufferOut: &sample) == noErr)
        return try #require(sample)
    }

    private func timecodeSample(frame: Int32, at time: CMTime, format: CMTimeCodeFormatDescription) throws -> CMSampleBuffer {
        var value = frame.bigEndian
        var block: CMBlockBuffer?
        #expect(CMBlockBufferCreateWithMemoryBlock(
            allocator: nil, memoryBlock: nil, blockLength: 4, blockAllocator: nil, customBlockSource: nil,
            offsetToData: 0, dataLength: 4, flags: 0, blockBufferOut: &block) == noErr)
        #expect(CMBlockBufferReplaceDataBytes(with: &value, blockBuffer: block!, offsetIntoDestination: 0, dataLength: 4) == noErr)
        var timing = CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: CMTimeScale(rate)), presentationTimeStamp: time, decodeTimeStamp: .invalid)
        var size = 4
        var sample: CMSampleBuffer?
        #expect(CMSampleBufferCreate(
            allocator: nil, dataBuffer: block, dataReady: true, makeDataReadyCallback: nil, refcon: nil,
            formatDescription: format, sampleCount: 1, sampleTimingEntryCount: 1, sampleTimingArray: &timing,
            sampleSizeEntryCount: 1, sampleSizeArray: &size, sampleBufferOut: &sample) == noErr)
        return try #require(sample)
    }

    private func check(_ url: URL, minimumSeconds: Double, maximumSeconds: Double, timecodeFrame: Int32) async throws {
        let asset = AVURLAsset(url: url)
        let audio = try await asset.loadTracks(withMediaType: .audio)
        #expect(audio.count == 2)
        for (index, track) in audio.enumerated() {
            let format = try #require(try await track.load(.formatDescriptions).first)
            let description = try #require(CMAudioFormatDescriptionGetStreamBasicDescription(format)?.pointee)
            #expect(description.mFormatID == kAudioFormatMPEG4AAC)
            #expect(description.mChannelsPerFrame == 1)
            #expect(description.mSampleRate == Double(sampleRate))
            let samples = try decodedSampleCount(of: track, asset: asset)
            let seconds = Double(samples) / Double(sampleRate)
            #expect(seconds >= minimumSeconds && seconds <= maximumSeconds, "track \(index + 1): \(seconds) s")
            let names = try await track.load(.metadata).filter { $0.identifier == .quickTimeUserDataTrackName }
            let name = try await names.first?.load(.stringValue)
            #expect(name == "Microphone: Razer Seiren V3 Mini, channel \(index + 1)")
            #expect(try await track.loadAssociatedTracks(ofType: .timecode).count == 1)
        }
        let timecodeTrack = try #require(try await asset.loadTracks(withMediaType: .timecode).first)
        let format = try #require(try await timecodeTrack.load(.formatDescriptions).first)
        let reel = CMFormatDescriptionGetExtension(format, extensionKey: kCMTimeCodeFormatDescriptionExtension_SourceReferenceName)
            as? [String: Any]
        #expect(reel?[kCMTimeCodeFormatDescriptionKey_Value as String] as? String == reelName)
        #expect(try firstTimecodeFrame(of: timecodeTrack, asset: asset) == timecodeFrame)

        let items = try await asset.loadMetadata(for: .quickTimeMetadata)
        let item = items.first { $0.key as? String == metadataKey }
        #expect(try await item?.load(.stringValue) == "Razer Seiren V3 Mini")
    }

    private func decodedSampleCount(of track: AVAssetTrack, asset: AVAsset) throws -> Int {
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [AVFormatIDKey: kAudioFormatLinearPCM])
        reader.add(output)
        #expect(reader.startReading())
        var count = 0
        while let sample = output.copyNextSampleBuffer() { count += CMSampleBufferGetNumSamples(sample) }
        #expect(reader.status == .completed)
        return count
    }

    private func firstTimecodeFrame(of track: AVAssetTrack, asset: AVAsset) throws -> Int32? {
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
        reader.add(output)
        #expect(reader.startReading())
        var block: CMBlockBuffer?
        while block == nil, let sample = output.copyNextSampleBuffer() { block = CMSampleBufferGetDataBuffer(sample) }
        guard let block else { return nil }
        var frame: Int32 = 0
        CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: 4, destination: &frame)
        return Int32(bigEndian: frame)
    }

    @Test func aFinalizedAudioOnlyMovieHasItsTracksTimecodeReelNameAndMetadata() async throws {
        defer { removeScratch() }
        let written = try await write(seconds: 5, firstTick: 45, timecodeFrame: 1_411_234, finish: true)
        try await check(written.url, minimumSeconds: 4.99, maximumSeconds: 5.01, timecodeFrame: 1_411_234)
        let duration = try await AVURLAsset(url: written.url).load(.duration).seconds
        #expect(abs(duration - 5) < 0.01, "\(duration)")
    }

    @Test func aNeverFinalizedAudioOnlyMovieIsReadableUpToItsLastFragment() async throws {
        defer { removeScratch() }
        let written = try await write(seconds: 9, firstTick: 0, timecodeFrame: 1_411_234, finish: false)
        try await Task.sleep(for: .milliseconds(500))
        let copy = scratch.appending(path: "after a crash.mov")
        try FileManager.default.copyItem(at: written.url, to: copy)
        try await check(copy, minimumSeconds: 9 - Double(RecorderValues.fragmentSeconds) - 0.1, maximumSeconds: 9.01,
                        timecodeFrame: 1_411_234)
        withExtendedLifetime(written.writer) {}
    }
}
