import AVFoundation
import CoreMedia
import Foundation
import RecorderLogic
@preconcurrency import ScreenCaptureKit

/// How an audio file ended, for the recording manifest: its entry with its
/// end, state and clock drift, and the writer's error, if any.
public struct AudioFileEnd: Equatable, Sendable {
    public var file: RecordingManifest.AudioFile
    public var error: AudioFileWriterError?
}

/// What an audio capture tells the recorder; each is called on the capture's queue.
struct AudioCaptureReports: Sendable {
    var fileStarted: @Sendable (RecordingManifest.AudioFile) -> Void
    var fileEnded: @Sendable (AudioFileEnd) -> Void
    var event: @Sendable (RecordingEvent) -> Void
    /// The capture ended by itself, after its last file ended.
    var ended: @Sendable (AudioTracker.CaptureEnd) -> Void
}

/// Where an audio capture's buffers come from: an audio input's
/// `AVCaptureSession`, or a ScreenCaptureKit stream with the system audio.
protocol AudioBufferSource: AnyObject, Sendable {
    /// Starts delivering buffers to `deliver` on `queue`; `ended` when it ends by itself.
    func start(
        queue: DispatchQueue, deliver: @escaping @Sendable (CMSampleBuffer) -> Void,
        ended: @escaping @Sendable (AudioTracker.CaptureEnd) -> Void)
    func stop() async
}

/// One audio source's capture and its audio files: buffers are placed on
/// the tick grid by `AudioFileTimeline`, written by `AudioFileWriter`, and
/// handed to the source's guide track. A gap over the longest filled gap
/// or a change of the channel count ends the file and starts a new one, in
/// the same capture. Everything runs on its own queue.
final class AudioCapture: @unchecked Sendable {
    let id: AudioTracker.SourceID
    let name: String
    private let context: RecordingContext
    private let guides: GuideTrackFeed
    private let guide: GuideTrack
    private let source: any AudioBufferSource
    private let reports: AudioCaptureReports
    private let queue: DispatchQueue

    // Confined to `queue`.
    /// The current file's place on the tick grid, from its first buffer on.
    private var timeline: AudioFileTimeline?
    private var channelCount = 0
    /// The current file, from its first sample after its first tick on.
    private var open: OpenFile?
    private var finishing: [Task<Void, Never>] = []
    private var isEnding = false
    private var guideChannels: Int?

    private struct OpenFile {
        var writer: AudioFileWriter
        var entry: RecordingManifest.AudioFile
        /// Silence or samples waiting for the writer, in order.
        var waiting: [(channels: [[Float]], position: Int64)] = []
    }

    init(
        id: AudioTracker.SourceID, name: String, source: any AudioBufferSource, context: RecordingContext,
        guides: GuideTrackFeed, reports: AudioCaptureReports
    ) {
        self.id = id
        self.name = name
        self.source = source
        self.context = context
        self.guides = guides
        guide = id == .systemAudio ? .systemAudio : .microphones
        self.reports = reports
        queue = DispatchQueue(label: "msr.audio.\(name)", qos: .userInteractive)
    }

    func start() {
        source.start(
            queue: queue, deliver: { [weak self] buffer in self?.receive(buffer) },
            ended: { [weak self] end in self?.queue.async { self?.end(end) } })
    }

    /// Stops the capture at the recorder's request and finalizes its file.
    func stop() async {
        await source.stop()
        let tasks = queue.sync { () -> [Task<Void, Never>] in
            isEnding = true
            finishFile()
            leaveGuide()
            return finishing
        }
        for task in tasks { await task.value }
    }

    /// Ends the capture by itself: its file ends, then it says why.
    private func end(_ reason: AudioTracker.CaptureEnd) {
        guard !isEnding else { return }
        isEnding = true
        finishFile()
        leaveGuide()
        let tasks = finishing
        let reports = reports
        Task {
            await self.source.stop()
            for task in tasks { await task.value }
            reports.ended(reason)
        }
    }

    // MARK: Buffers

    private func receive(_ buffer: CMSampleBuffer) {
        guard !isEnding, buffer.isValid, CMSampleBufferGetNumSamples(buffer) > 0 else { return }
        let arrival = context.now()
        let channels: [[Float]]
        do {
            channels = try Self.channels(of: buffer)
        } catch {
            end(.captureFailed(error.description))
            return
        }
        guard let count = channels.first?.count, count > 0 else { return }
        let pts = CMTimeConvertScale(CMSampleBufferGetPresentationTimeStamp(buffer), timescale: 1_000_000_000, method: .roundHalfAwayFromZero)
        let time = context.clock.sinceStart(host: UInt64(max(0, pts.value)))

        joinGuide(channelCount: channels.count)
        guides.receive(channels, from: name, to: guide, at: time)

        if timeline != nil, channelCount != channels.count { finishFile() }
        if timeline == nil {
            timeline = AudioFileTimeline()
            channelCount = channels.count
        }
        var placement = timeline!.place(bufferAt: time, sampleCount: count, arrival: arrival)
        if let gap = placement.gap { reports.event(gapEvent(gap, at: time)) }
        if placement.action == .endFile {
            finishFile()
            timeline = AudioFileTimeline()
            channelCount = channels.count
            placement = timeline!.place(bufferAt: time, sampleCount: count, arrival: arrival)
        }
        guard case .write(let silence, let firstSample, let position) = placement.action else { return }
        if open == nil {
            guard openFile(firstTick: timeline!.firstTick!) else { return }
        }
        if silence > 0 {
            open!.waiting.append((Array(repeating: [Float](repeating: 0, count: Int(silence)), count: channels.count), position - silence))
        }
        open!.waiting.append((firstSample == 0 ? channels : channels.map { Array($0[firstSample...]) }, position))
        writeWaiting()
    }

    private func gapEvent(_ gap: AudioGap, at time: Int64) -> RecordingEvent {
        var event = RecordingEvent(at: time, event: .audioInputGap, display: name)
        event.length = (Double(gap.length) / 1_000_000).rounded() / 1000
        return event
    }

    private func writeWaiting() {
        guard var file = open else { return }
        do {
            while let first = file.waiting.first {
                guard try file.writer.append(first.channels, at: first.position) else { break }
                file.waiting.removeFirst()
            }
        } catch {
            open = file
            fail(error)
            return
        }
        let waitingSamples = file.waiting.reduce(0) { $0 + ($1.channels.first?.count ?? 0) }
        open = file
        if waitingSamples > RecorderValues.lateTickBoundSeconds * RecorderValues.audioSampleRate {
            fail(AudioFileWriterError(nil, while: "the writer took none of the last \(RecorderValues.lateTickBoundSeconds) s of \(name)"))
        }
    }

    private func fail(_ error: AudioFileWriterError) {
        open?.waiting = []
        end(error.isDiskFull ? .diskFull : .writerFailed(error.description))
    }

    // MARK: Files

    /// The file's writer, at its first tick; false when it cannot be made,
    /// which ends the capture.
    private func openFile(firstTick: Int64) -> Bool {
        let description: AudioFileDescription = switch id {
        case .input(let uid): AudioFileDescription(
            source: .audioInput(name: name, coreAudioUID: uid, channelCount: channelCount),
            recordingStarted: context.startedText, app: context.app)
        case .systemAudio: AudioFileDescription(source: .systemAudio, recordingStarted: context.startedText, app: context.app)
        }
        let fileName = context.claimAudioFileName(tick: firstTick, source: description.source)
        do {
            let writer = try AudioFileWriter(
                url: context.folder.appending(path: fileName), description: description, firstTick: firstTick,
                timecode: context.timecode)
            let entry = RecordingManifest.AudioFile(
                name: fileName, audioSource: description.sourceName, audioSourceUID: description.coreAudioUID,
                channels: description.channels, start: TickGrid.recording.seconds(ofTick: firstTick),
                timecode: context.timecode.text(ofTick: firstTick))
            open = OpenFile(writer: writer, entry: entry)
            reports.fileStarted(entry)
            return true
        } catch {
            fail(error)
            return false
        }
    }

    /// Ends the current file, if any; its end is reported once it is finalized.
    private func finishFile() {
        let written = timeline?.writtenSamples ?? 0
        let drift = timeline?.clockDriftPpm
        timeline = nil
        guard let file = open else { return }
        open = nil
        let reports = reports
        finishing.append(Task {
            var entry = file.entry
            var failure: AudioFileWriterError?
            do throws(AudioFileWriterError) {
                try await file.writer.finish(endPosition: written > 0 ? written : nil)
                entry.state = .finalized
            } catch {
                failure = error
                entry.state = .notFinalized
            }
            entry.end = entry.start + Double(written) / Double(RecorderValues.audioSampleRate)
            entry.clockDriftPpm = drift.map { ($0 * 10).rounded() / 10 }
            reports.fileEnded(AudioFileEnd(file: entry, error: failure))
        })
    }

    // MARK: Guide track

    private func joinGuide(channelCount: Int) {
        guard guideChannels != channelCount else { return }
        if guideChannels != nil { guides.remove(source: name, from: guide) }
        if guide == .systemAudio, channelCount != GuideTrack.systemAudio.channelCount { return }
        guides.add(source: name, channelCount: channelCount, to: guide)
        guideChannels = channelCount
    }

    private func leaveGuide() {
        guard guideChannels != nil else { return }
        guides.remove(source: name, from: guide)
        guideChannels = nil
    }

    // MARK: PCM

    /// A buffer's samples, one array per channel, as floats from -1 to 1.
    static func channels(of buffer: CMSampleBuffer) throws(PCMLayoutError) -> [[Float]] {
        guard let format = CMSampleBufferGetFormatDescription(buffer),
              let stream = CMAudioFormatDescriptionGetStreamBasicDescription(format)?.pointee,
              stream.mFormatID == kAudioFormatLinearPCM
        else { throw PCMLayoutError(description: "an audio buffer that is not linear PCM") }
        let isFloat = stream.mFormatFlags & kAudioFormatFlagIsFloat != 0
        let sampleFormat: PCMLayout.SampleFormat
        switch (isFloat, stream.mBitsPerChannel) {
        case (true, 32): sampleFormat = .float32
        case (false, 16): sampleFormat = .int16
        case (false, 32): sampleFormat = .int32
        default: throw PCMLayoutError(description: "audio of \(stream.mBitsPerChannel) bits\(isFloat ? " float" : "") is not read")
        }
        let layout = PCMLayout(
            channelCount: Int(stream.mChannelsPerFrame),
            isInterleaved: stream.mFormatFlags & kAudioFormatFlagIsNonInterleaved == 0, sampleFormat: sampleFormat)
        var sizeNeeded = 0
        CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            buffer, bufferListSizeNeededOut: &sizeNeeded, bufferListOut: nil, bufferListSize: 0, blockBufferAllocator: nil,
            blockBufferMemoryAllocator: nil, flags: 0, blockBufferOut: nil)
        let list = UnsafeMutableRawPointer.allocate(byteCount: sizeNeeded, alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { list.deallocate() }
        var block: CMBlockBuffer?
        let status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            buffer, bufferListSizeNeededOut: nil, bufferListOut: list.assumingMemoryBound(to: AudioBufferList.self),
            bufferListSize: sizeNeeded, blockBufferAllocator: nil, blockBufferMemoryAllocator: nil,
            flags: kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment, blockBufferOut: &block)
        guard status == noErr else { throw PCMLayoutError(description: "an audio buffer cannot be read (error \(status))") }
        let buffers = UnsafeMutableAudioBufferListPointer(list.assumingMemoryBound(to: AudioBufferList.self))
        let raw = buffers.map { UnsafeRawBufferPointer(start: $0.mData, count: Int($0.mDataByteSize)) }
        return try withExtendedLifetime(block) { () throws(PCMLayoutError) -> [[Float]] in
            try splitIntoChannels(raw, layout: layout)
        }
    }
}
