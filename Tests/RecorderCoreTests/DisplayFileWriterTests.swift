import AVFoundation
import CoreMedia
import Foundation
import RecorderLogic
import Testing
@testable import RecorderCore

/// Writes display files from synthetic frames and reads them back with
/// AVFoundation: no screen, no permission.
@Suite(.serialized) struct DisplayFileWriterTests {
    private let scratch: URL
    private let frameSize = FrameSize(width: 320, height: 180)
    private let berlin = TimeZone(identifier: "Europe/Berlin")!

    init() throws {
        scratch = FileManager.default.temporaryDirectory
            .appending(path: "DisplayFileWriterTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
    }

    private func removeScratch() {
        try? FileManager.default.removeItem(at: scratch)
    }

    /// A 420v frame tagged BT.709, as ScreenCaptureKit delivers them (the experiment of 2026-11-15).
    private func frame(brightness: UInt8) throws -> CVPixelBuffer {
        var buffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            nil, frameSize.width, frameSize.height, kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
            [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary, &buffer)
        let pixelBuffer = try #require(buffer, "CVPixelBufferCreate failed: \(status)")
        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        for plane in 0..<CVPixelBufferGetPlaneCount(pixelBuffer) {
            let base = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, plane)!
            let bytes = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, plane) * CVPixelBufferGetHeightOfPlane(pixelBuffer, plane)
            memset(base, Int32(plane == 0 ? brightness : 128), bytes)
        }
        CVPixelBufferUnlockBaseAddress(pixelBuffer, [])
        CVBufferSetAttachment(pixelBuffer, kCVImageBufferColorPrimariesKey, kCVImageBufferColorPrimaries_ITU_R_709_2, .shouldPropagate)
        CVBufferSetAttachment(pixelBuffer, kCVImageBufferTransferFunctionKey, kCVImageBufferTransferFunction_ITU_R_709_2, .shouldPropagate)
        CVBufferSetAttachment(pixelBuffer, kCVImageBufferYCbCrMatrixKey, kCVImageBufferYCbCrMatrix_ITU_R_709_2, .shouldPropagate)
        return pixelBuffer
    }

    /// Writes `seconds` of ticks from `firstTick` on, waiting for the writer as a late tick would.
    private func write(rate: Int, firstTick: Int64, seconds: Int, timecode: Timecode, finish: Bool = true) async throws -> (URL, DisplayFileWriter) {
        let url = scratch.appending(path: "Display 1 - Test \(rate).mov")
        let writer = try DisplayFileWriter(
            url: url, frameSize: frameSize, firstTick: firstTick, timecode: timecode, grid: TickGrid(framesPerSecond: rate))
        let frames = try (0..<4).map { try frame(brightness: UInt8(40 + 50 * $0)) }
        let lastTick = firstTick + Int64(seconds * rate) - 1
        for tick in firstTick...lastTick {
            while try !writer.append(frames[Int(tick / Int64(rate)) % frames.count], tick: tick) {
                try await Task.sleep(for: .milliseconds(1))
            }
        }
        if finish { try await writer.finish(lastTick: lastTick) }
        return (url, writer)
    }

    private func startDate() throws -> Date {
        try Date("2026-11-12T13:03:05.120Z", strategy: .iso8601.year().month().day().time(includingFractionalSeconds: true).timeZone(separator: .omitted))
    }

    @Test(arguments: [RecorderValues.framesPerSecond, 60])
    func aDisplayFileHasAConstantFrameRateTheTimecodeAndBT709(rate: Int) async throws {
        defer { removeScratch() }
        let timecode = Timecode(start: try startDate(), timeZone: berlin, framesPerSecond: rate)
        let firstTick = Int64(rate) * 3 / 2
        let (url, _) = try await write(rate: rate, firstTick: firstTick, seconds: 5, timecode: timecode)
        let asset = AVURLAsset(url: url)

        let video = try #require(try await asset.loadTracks(withMediaType: .video).first)
        let format = try #require(try await video.load(.formatDescriptions).first)
        #expect(CMFormatDescriptionGetMediaSubType(format) == kCMVideoCodecType_HEVC)
        let dimensions = CMVideoFormatDescriptionGetDimensions(format)
        #expect(dimensions.width == 320 && dimensions.height == 180)
        func ext(_ key: CFString) -> String? {
            CMFormatDescriptionGetExtension(format, extensionKey: key) as? String
        }
        #expect(ext(kCMFormatDescriptionExtension_ColorPrimaries) == kCMFormatDescriptionColorPrimaries_ITU_R_709_2 as String)
        #expect(ext(kCMFormatDescriptionExtension_TransferFunction) == kCMFormatDescriptionTransferFunction_ITU_R_709_2 as String)
        #expect(ext(kCMFormatDescriptionExtension_YCbCrMatrix) == kCMFormatDescriptionYCbCrMatrix_ITU_R_709_2 as String)

        let times = try readTimes(of: video, asset: asset)
        #expect(times.count == 5 * rate)
        let step = CMTime(value: 1, timescale: CMTimeScale(rate))
        for (earlier, later) in zip(times, times.dropFirst()) {
            #expect(CMTimeCompare(CMTimeSubtract(later, earlier), step) == 0, "\(earlier.seconds) → \(later.seconds)")
        }
        #expect(abs(try await asset.load(.duration).seconds - 5) < 0.001)
        #expect(abs(try await video.load(.nominalFrameRate) - Float(rate)) < 0.01)

        let timecodeTrack = try #require(try await asset.loadTracks(withMediaType: .timecode).first)
        let firstTimecode = try readFirstTimecodeFrame(of: timecodeTrack, asset: asset)
        #expect(firstTimecode == Int32(timecode.frame(ofTick: firstTick)), "\(String(describing: firstTimecode))")
        let associated = try await video.loadAssociatedTracks(ofType: .timecode)
        #expect(associated.count == 1)
    }

    /// A file the process never finalized, as after a crash, is readable up
    /// to its last fragment of 2 s.
    @Test func anUnfinalizedDisplayFileIsReadableUpToItsLastFragment() async throws {
        defer { removeScratch() }
        let rate = RecorderValues.framesPerSecond
        // The writer is kept, never finished: the process "crashed".
        let timecode = Timecode(start: try startDate(), timeZone: berlin)
        let (url, writer) = try await write(rate: rate, firstTick: 0, seconds: 9, timecode: timecode, finish: false)
        try await Task.sleep(for: .milliseconds(500))
        let copy = scratch.appending(path: "after a crash.mov")
        try FileManager.default.copyItem(at: url, to: copy)
        let boxes = try topLevelBoxes(of: copy)
        #expect(boxes.contains("moov"))
        // 9 s in fragments of 2 s: after the movie box, a movie fragment every 2 s.
        #expect(boxes.filter { $0 == "moof" }.count >= 3, "\(boxes)")
        let asset = AVURLAsset(url: copy)
        let video = try #require(try await asset.loadTracks(withMediaType: .video).first)
        let times = try readTimes(of: video, asset: asset)
        let lost = 9 - Double(times.count) / Double(rate)
        #expect(lost <= Double(RecorderValues.fragmentSeconds), "\(times.count) frames of \(9 * rate)")
        // The one timecode sample of the file is in it before the file is finalized.
        let timecodeTrack = try #require(try await asset.loadTracks(withMediaType: .timecode).first)
        #expect(try readFirstTimecodeFrame(of: timecodeTrack, asset: asset) == Int32(timecode.frame(ofTick: 0)))
        withExtendedLifetime(writer) {}
    }

    private func readTimes(of track: AVAssetTrack, asset: AVAsset) throws -> [CMTime] {
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
        reader.add(output)
        #expect(reader.startReading())
        var times: [CMTime] = []
        while let sample = output.copyNextSampleBuffer() {
            if CMSampleBufferGetNumSamples(sample) > 0 { times.append(CMSampleBufferGetPresentationTimeStamp(sample)) }
        }
        #expect(reader.status == .completed)
        return times.sorted { CMTimeCompare($0, $1) < 0 }
    }

    private func readFirstTimecodeFrame(of track: AVAssetTrack, asset: AVAsset) throws -> Int32? {
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
        reader.add(output)
        #expect(reader.startReading())
        // Marker buffers without data may come first.
        var block: CMBlockBuffer?
        while block == nil, let sample = output.copyNextSampleBuffer() { block = CMSampleBufferGetDataBuffer(sample) }
        guard let block else { return nil }
        var frame: Int32 = 0
        CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: 4, destination: &frame)
        return Int32(bigEndian: frame)
    }

    private func topLevelBoxes(of url: URL) throws -> [String] {
        let data = try Data(contentsOf: url)
        var boxes: [String] = []
        var offset = 0
        while offset + 8 <= data.count {
            var size = data[offset..<offset + 4].reduce(0) { $0 << 8 | Int($1) }
            let type = String(decoding: data[offset + 4..<offset + 8], as: UTF8.self)
            if size == 1 { size = data[offset + 8..<offset + 16].reduce(0) { $0 << 8 | Int($1) } }
            guard size >= 8 else { break }
            boxes.append(type)
            offset += size
        }
        return boxes
    }
}

@Suite struct ClockTests {
    /// ScreenCaptureKit stamps a frame's display time in mach absolute time;
    /// the shared clock reads the host clock as the same.
    @Test func theHostClockIsMachAbsoluteTime() {
        let before = readClocks().host
        let machNow = nanoseconds(machTicks: mach_absolute_time())
        let after = readClocks().host
        #expect(before <= machNow && machNow <= after)
    }

    /// The continuous clock counts everything the host clock counts and the
    /// sleeps; read later, it is never behind. (`readClocks` reads the host
    /// clock second, so its two values can differ the other way by the gap
    /// between the reads.)
    @Test func theContinuousClockIsNeverBehindTheHostClock() {
        let host = nanoseconds(machTicks: mach_absolute_time())
        let continuous = continuousNow()
        #expect(continuous >= host)
    }
}

@Suite struct DiskFullTests {
    @Test func aFullDiskIsRecognisedAlsoUnderAnotherError() {
        #expect(isDiskFullError(NSError(domain: AVFoundationErrorDomain, code: AVError.Code.diskFull.rawValue)))
        #expect(isDiskFullError(NSError(domain: NSPOSIXErrorDomain, code: Int(ENOSPC))))
        let wrapped = NSError(domain: AVFoundationErrorDomain, code: AVError.Code.unknown.rawValue,
                              userInfo: [NSUnderlyingErrorKey: NSError(domain: NSPOSIXErrorDomain, code: Int(ENOSPC))])
        #expect(isDiskFullError(wrapped))
        #expect(!isDiskFullError(NSError(domain: NSPOSIXErrorDomain, code: Int(EACCES))))
    }
}
