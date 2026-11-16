import AVFoundation
import CoreMedia
import Foundation
import RecorderLogic
import Testing
@testable import RecorderCore

/// Writes audio files from synthetic PCM and reads them back with
/// AVFoundation: no microphone, no permission.
@Suite(.serialized) struct AudioFileWriterTests {
    private let scratch: URL
    private let berlin = TimeZone(identifier: "Europe/Berlin")!
    private let start = Date(timeIntervalSince1970: 1_794_488_585.12) // 2026-11-12 14:03:05.120 in Berlin
    private let rate = RecorderValues.audioSampleRate
    private let prefix = ScreenFileMetadata.keyPrefix
    private let started = "2026-11-12T14:03:05.120+01:00"
    private let app = "Multi Screen Recorder 0.20261115.3 (a1b2c3d)"

    init() throws {
        scratch = FileManager.default.temporaryDirectory
            .appending(path: "AudioFileWriterTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
    }

    private func removeScratch() {
        try? FileManager.default.removeItem(at: scratch)
    }

    private func microphone(channels: Int) -> AudioFileDescription {
        AudioFileDescription(
            source: .audioInput(name: "Razer Seiren V3 Mini", coreAudioUID: "AppleUSBAudioEngine:Razer:1", channelCount: channels),
            recordingStarted: started, app: app)
    }

    /// A sine tone per channel, 440 Hz times the channel's number, under
    /// noise, so the encoder needs its whole bit rate.
    private func tone(channels: Int, from first: Int64, count: Int) -> [[Float]] {
        (0..<channels).map { channel in
            (0..<count).map { index in
                let position = first + Int64(index)
                let sine = 0.25 * sin(2 * Double.pi * Double(440 * (channel + 1)) * Double(position) / Double(rate))
                var noise = UInt64(position) &* 6_364_136_223_846_793_005 &+ UInt64(channel + 1) &* 1_442_695_040_888_963_407
                noise ^= noise >> 29
                return Float(sine + 0.2 * (Double(noise % 2001) / 1000 - 1))
            }
        }
    }

    /// Writes buffers of 512 samples from `position` on, waiting for the writer.
    private func writeTone(_ writer: AudioFileWriter, channels: Int, from position: Int64, samples: Int) async throws {
        var written = 0
        while written < samples {
            let count = min(512, samples - written)
            let at = position + Int64(written)
            while try !writer.append(tone(channels: channels, from: at, count: count), at: at) {
                try await Task.sleep(for: .milliseconds(1))
            }
            written += count
        }
    }

    @Test func anAudioInputsFileHasAMonoTrackPerChannelTheTimecodeReelNameAndMetadata() async throws {
        defer { removeScratch() }
        let url = scratch.appending(path: "microphone.mov")
        let timecode = Timecode(start: start, timeZone: berlin)
        let writer = try AudioFileWriter(url: url, description: microphone(channels: 2), firstTick: 45, timecode: timecode)
        try await writeTone(writer, channels: 2, from: 0, samples: 3 * rate)
        try await writer.finish(endPosition: Int64(3 * rate))

        let asset = AVURLAsset(url: url)
        let tracks = try await asset.loadTracks(withMediaType: .audio)
        #expect(tracks.count == 2)
        for (index, track) in tracks.enumerated() {
            let stream = try await streamDescription(of: track)
            #expect(stream.mFormatID == kAudioFormatMPEG4AAC)
            #expect(stream.mChannelsPerFrame == 1)
            #expect(stream.mSampleRate == Double(rate))
            #expect(try await trackName(of: track) == "Microphone: Razer Seiren V3 Mini, channel \(index + 1)")
            #expect(try await track.loadAssociatedTracks(ofType: .timecode).count == 1)
            let dataRate = try await track.load(.estimatedDataRate)
            #expect(abs(dataRate - 128_000) < 128_000 * 0.2, "\(dataRate)")
            #expect(try decodedSamples(of: track, asset: asset).count == 3 * rate)
        }
        #expect(abs(try await asset.load(.duration).seconds - 3) < 0.001)
        try await expectTimecode(asset, frame: timecode.frame(ofTick: 45), reelName: "Microphone - Razer Seiren V3 Mini")
        let metadata = try await metadataValues(asset)
        #expect(metadata == [
            prefix + "audioSource": "Razer Seiren V3 Mini",
            prefix + "audioSourceUID": "AppleUSBAudioEngine:Razer:1",
            prefix + "channels": "2",
            prefix + "recordingStarted": started,
            prefix + "app": app,
            "com.apple.quicktime.software": app,
            "com.apple.proapps.reel": "Microphone - Razer Seiren V3 Mini",
            "com.apple.proapps.cameraName": "Microphone - Razer Seiren V3 Mini",
        ])
    }

    @Test func theSystemAudiosFileHasOneStereoTrack() async throws {
        defer { removeScratch() }
        let url = scratch.appending(path: "system audio.mov")
        let description = AudioFileDescription(source: .systemAudio, recordingStarted: started, app: app)
        let writer = try AudioFileWriter(url: url, description: description, firstTick: 0, timecode: Timecode(start: start, timeZone: berlin))
        try await writeTone(writer, channels: 2, from: 0, samples: 2 * rate)
        try await writer.finish(endPosition: Int64(2 * rate))

        let asset = AVURLAsset(url: url)
        let tracks = try await asset.loadTracks(withMediaType: .audio)
        #expect(tracks.count == 1)
        let track = try #require(tracks.first)
        #expect(try await streamDescription(of: track).mChannelsPerFrame == 2)
        #expect(try await trackName(of: track) == "System audio")
        let dataRate = try await track.load(.estimatedDataRate)
        #expect(abs(dataRate - 192_000) < 192_000 * 0.2, "\(dataRate)")
        try await expectTimecode(asset, frame: Timecode(start: start, timeZone: berlin).frame(ofTick: 0), reelName: "System audio")
        #expect(try await metadataValues(asset)[prefix + "audioSourceUID"] == nil)
    }

    /// Samples with another channel count than the file's are an error, never a trap.
    @Test func aBufferWithAnotherChannelCountIsAnError() async throws {
        defer { removeScratch() }
        let url = scratch.appending(path: "channels.mov")
        let writer = try AudioFileWriter(url: url, description: microphone(channels: 1), firstTick: 0, timecode: Timecode(start: start, timeZone: berlin))
        let error = #expect(throws: AudioFileWriterError.self) {
            _ = try writer.append([[0.1], [0.1]], at: 0)
        }
        #expect(error?.description.contains("2 channels") == true)
        try? await writer.finish(endPosition: nil)
    }

    /// A filled gap is silence of exactly its length at its place.
    @Test func silenceFillsAGapAtItsPosition() async throws {
        defer { removeScratch() }
        let url = scratch.appending(path: "gap.mov")
        let writer = try AudioFileWriter(url: url, description: microphone(channels: 1), firstTick: 0, timecode: Timecode(start: start, timeZone: berlin))
        try await writeTone(writer, channels: 1, from: 0, samples: rate)
        while try !writer.appendSilence(Int64(rate / 2), at: Int64(rate)) { try await Task.sleep(for: .milliseconds(1)) }
        try await writeTone(writer, channels: 1, from: Int64(rate * 3 / 2), samples: rate)
        try await writer.finish(endPosition: Int64(rate * 5 / 2))

        let asset = AVURLAsset(url: url)
        let track = try #require(try await asset.loadTracks(withMediaType: .audio).first)
        let samples = try decodedSamples(of: track, asset: asset)
        #expect(samples.count == rate * 5 / 2)
        func loudness(_ range: Range<Int>) -> Float { samples[range].map { $0 * $0 }.reduce(0, +) / Float(range.count) }
        // Away from the edges, where the encoder smears: tone, silence, tone.
        #expect(loudness(rate / 4..<rate * 3 / 4) > 0.02)
        #expect(loudness(rate * 9 / 8..<rate * 11 / 8) < 1e-6)
        #expect(loudness(rate * 7 / 4..<rate * 9 / 4) > 0.02)
    }

    /// A file the process never finalized, as after a crash, is readable up
    /// to its last fragment of 2 s, with its timecode and metadata.
    @Test func anUnfinalizedAudioFileIsReadableUpToItsLastFragment() async throws {
        defer { removeScratch() }
        let url = scratch.appending(path: "crash.mov")
        let timecode = Timecode(start: start, timeZone: berlin)
        let writer = try AudioFileWriter(url: url, description: microphone(channels: 2), firstTick: 30, timecode: timecode)
        try await writeTone(writer, channels: 2, from: 0, samples: 9 * rate)
        try await Task.sleep(for: .milliseconds(500))
        let copy = scratch.appending(path: "after a crash.mov")
        try FileManager.default.copyItem(at: url, to: copy)

        let asset = AVURLAsset(url: copy)
        let tracks = try await asset.loadTracks(withMediaType: .audio)
        #expect(tracks.count == 2)
        for track in tracks {
            let seconds = Double(try decodedSamples(of: track, asset: asset).count) / Double(rate)
            #expect(seconds >= 9 - Double(RecorderValues.fragmentSeconds) - 0.1, "\(seconds) s of 9")
        }
        try await expectTimecode(asset, frame: timecode.frame(ofTick: 30), reelName: "Microphone - Razer Seiren V3 Mini")
        #expect(try await metadataValues(asset)[prefix + "audioSource"] == "Razer Seiren V3 Mini")
        withExtendedLifetime(writer) {}
    }

    private func streamDescription(of track: AVAssetTrack) async throws -> AudioStreamBasicDescription {
        let format = try #require(try await track.load(.formatDescriptions).first)
        return try #require(CMAudioFormatDescriptionGetStreamBasicDescription(format)?.pointee)
    }

    private func trackName(of track: AVAssetTrack) async throws -> String? {
        let names = try await track.load(.metadata).filter { $0.identifier == .quickTimeUserDataFullName }
        return try await names.first?.load(.stringValue)
    }

    private func metadataValues(_ asset: AVAsset) async throws -> [String: String] {
        var values: [String: String] = [:]
        for item in try await asset.loadMetadata(for: .quickTimeMetadata) {
            if let key = item.key as? String { values[key] = try await item.load(.stringValue) }
        }
        return values
    }

    private func expectTimecode(_ asset: AVAsset, frame: Int64, reelName: String) async throws {
        let track = try #require(try await asset.loadTracks(withMediaType: .timecode).first)
        let format = try #require(try await track.load(.formatDescriptions).first)
        let reel = CMFormatDescriptionGetExtension(format, extensionKey: kCMTimeCodeFormatDescriptionExtension_SourceReferenceName)
            as? [String: Any]
        #expect(reel?[kCMTimeCodeFormatDescriptionKey_Value as String] as? String == reelName)
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
        reader.add(output)
        #expect(reader.startReading())
        var block: CMBlockBuffer?
        while block == nil, let sample = output.copyNextSampleBuffer() { block = CMSampleBufferGetDataBuffer(sample) }
        var value: Int32 = 0
        CMBlockBufferCopyDataBytes(try #require(block), atOffset: 0, dataLength: 4, destination: &value)
        #expect(Int64(Int32(bigEndian: value)) == frame)
    }

    /// The first channel's samples, decoded to 32-bit floats.
    private func decodedSamples(of track: AVAssetTrack, asset: AVAsset) throws -> [Float] {
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM, AVLinearPCMBitDepthKey: 32, AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsNonInterleaved: false, AVLinearPCMIsBigEndianKey: false,
        ])
        reader.add(output)
        #expect(reader.startReading())
        var samples: [Float] = []
        while let sample = output.copyNextSampleBuffer() {
            guard let block = CMSampleBufferGetDataBuffer(sample) else { continue }
            let frames = CMSampleBufferGetNumSamples(sample)
            var buffer = [Float](repeating: 0, count: CMBlockBufferGetDataLength(block) / 4)
            CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: buffer.count * 4, destination: &buffer)
            let channels = buffer.count / max(1, frames)
            samples += stride(from: 0, to: buffer.count, by: channels).map { buffer[$0] }
        }
        #expect(reader.status == .completed)
        return samples
    }
}
