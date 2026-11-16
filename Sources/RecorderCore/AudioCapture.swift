import AVFoundation
import CoreMedia
import Foundation
import RecorderLogic
@preconcurrency import ScreenCaptureKit
import Synchronization

/// How an audio file ended, for the recording manifest: its entry with its
/// end, state, clock drift and clock drift correction, the writer's error, if any, and the samples
/// the writer never took at the end.
public struct AudioFileEnd: Equatable, Sendable {
    public var file: RecordingManifest.AudioFile
    public var error: AudioFileWriterError?
    public var lostSamples: Int64 = 0

    /// Samples lost at the end are `audio file writer fell behind`, a
    /// failure (D47), at the file's end.
    public var events: [RecordingEvent] {
        guard lostSamples > 0 else { return [] }
        var event = RecordingEvent(
            at: Int64(((file.end ?? file.start) * 1_000_000_000).rounded()), event: .audioFileWriterFellBehind,
            audioSource: file.audioSource)
        event.error = error?.description
        return [event]
    }
}

/// What an audio capture tells the recorder; each is called on the capture's queue.
struct AudioCaptureReports: Sendable {
    var fileStarted: @Sendable (RecordingManifest.AudioFile) -> Void
    /// A file ended, finalized or not; each file's end once.
    var fileEnded: @Sendable (AudioFileEnd) -> Void
    var event: @Sendable (RecordingEvent) -> Void
    /// The clock drift correction's latest status, about once a second.
    var clockDrift: @Sendable (ClockDriftCorrection.Status) -> Void
    /// The capture ended by itself, after its last file's end.
    var ended: @Sendable (AudioTracker.CaptureEnd) -> Void
}

/// What the audio captures reported, in the order they reported it, until
/// the recorder takes it on the main actor; at Stop the recorder takes the
/// rest before it finalizes, so nothing depends on when a hop to the main
/// actor runs.
final class AudioReportInbox: Sendable {
    enum Report: Sendable {
        case fileStarted(RecordingManifest.AudioFile, AudioTracker.SourceID, name: String)
        case fileEnded(AudioFileEnd)
        case event(RecordingEvent)
        case clockDrift(AudioTracker.SourceID, number: Int, ClockDriftCorrection.Status)
        case ended(AudioTracker.SourceID, number: Int, name: String, AudioTracker.CaptureEnd)
    }

    private let reports = Mutex<[Report]>([])

    func post(_ report: Report) {
        reports.withLock { $0.append(report) }
    }

    /// Every report not taken yet, oldest first.
    func take() -> [Report] {
        reports.withLock { reports in
            defer { reports = [] }
            return reports
        }
    }
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

/// What an audio capture needs of an audio file's writer; `AudioFileWriter` in a recording.
protocol AudioFileWriting: AnyObject {
    /// False when the writer is not ready, so the samples wait.
    func append(_ channels: [[Float]], at position: Int64) throws(AudioFileWriterError) -> Bool
    func appendSilence(_ count: Int64, at position: Int64) throws(AudioFileWriterError) -> Bool
    func finish(endPosition: Int64?) async throws(AudioFileWriterError)
}

extension AudioFileWriter: AudioFileWriting {}

/// One audio source's capture and its audio files: buffers are resampled
/// to follow the shared clock by `ClockDriftCorrection`, and its corrected
/// chunks placed on the tick grid by `AudioFileTimeline`, written by an
/// `AudioFileWriting`, and handed to the source's guide track. A gap over
/// the longest filled gap or a change of the channel count ends the file
/// and starts a new one, in the same capture. Everything runs on its own queue.
final class AudioCapture: @unchecked Sendable {
    typealias MakeWriter = @Sendable (_ url: URL, _ description: AudioFileDescription, _ firstTick: Int64)
        throws(AudioFileWriterError) -> any AudioFileWriting

    let id: AudioTracker.SourceID
    /// Its number in the recording (`SourceLabel`), 0 for the system audio.
    let number: Int
    /// The device name; "System audio" for the system audio.
    let name: String
    /// Unique in the recording: its source in the guide track feed.
    private var label: String {
        id == .systemAudio ? SourceLabel.systemAudio : SourceLabel.audioInput(number, name: name)
    }
    private let context: RecordingContext
    private let guides: GuideTrackFeed
    private let guide: GuideTrack
    private let source: any AudioBufferSource
    private let reports: AudioCaptureReports
    private let makeWriter: MakeWriter
    private let drainTimeout: Duration
    private let queue: DispatchQueue

    // Confined to `queue`.
    /// The current file's place on the tick grid, from its first buffer on.
    private var timeline: AudioFileTimeline?
    private var channelCount = 0
    /// The current file, from its first sample after its first tick on.
    private var open: OpenFile?
    /// Every file's finishing, in the order the files started.
    private var finishing: [Task<Void, Never>] = []
    private var isEnding = false
    private var guideChannels: Int?
    private var correction = ClockDriftCorrection()
    /// The correction applied up to the end of the latest chunk, and up to
    /// the current file's start, in seconds.
    private var applied = 0.0
    private var appliedAtFileStart = 0.0
    /// When the clock drift was last reported and written to `--debug`; nil before the first buffer.
    private var clockDriftReported: Int64?
    private var clockDriftDebugged: Int64?

    private enum Chunk {
        case samples([[Float]])
        case silence(Int64)

        var count: Int64 {
            switch self {
            case .samples(let channels): Int64(channels.first?.count ?? 0)
            case .silence(let count): count
            }
        }
    }

    private struct OpenFile {
        var writer: any AudioFileWriting
        var entry: RecordingManifest.AudioFile
        /// Silence or samples waiting for the writer, in order.
        var waiting: [(chunk: Chunk, position: Int64)] = []
        /// The end of what the writer took, in samples from the file's first tick.
        var written: Int64 = 0

        var waitingSamples: Int64 { waiting.reduce(0) { $0 + $1.chunk.count } }

        /// Hands the waiting chunks to the writer while it takes them.
        mutating func write() throws(AudioFileWriterError) {
            while let first = waiting.first {
                let taken = switch first.chunk {
                case .samples(let channels): try writer.append(channels, at: first.position)
                case .silence(let count): try writer.appendSilence(count, at: first.position)
                }
                guard taken else { return }
                waiting.removeFirst()
                written = first.position + first.chunk.count
            }
        }
    }

    init(
        id: AudioTracker.SourceID, number: Int, name: String, source: any AudioBufferSource, context: RecordingContext,
        guides: GuideTrackFeed, reports: AudioCaptureReports,
        drainTimeout: Duration = .seconds(RecorderValues.audioWaitBoundSeconds),
        makeWriter: MakeWriter? = nil
    ) {
        self.id = id
        self.number = number
        self.name = name
        self.source = source
        self.context = context
        self.guides = guides
        guide = id == .systemAudio ? .systemAudio : .audioInputs
        self.reports = reports
        self.drainTimeout = drainTimeout
        self.makeWriter = makeWriter ?? Self.audioFileWriter(timecode: context.timecode)
        queue = DispatchQueue(label: "msr.audio.\(number)", qos: .userInteractive)
    }

    /// The writer of a recording: an `AudioFileWriter`. A function, not a
    /// default closure in `init`: Swift 6.4's compiler crashes on a
    /// typed-throws closure there.
    private static func audioFileWriter(timecode: Timecode) -> MakeWriter {
        let make: MakeWriter = { url, description, firstTick throws(AudioFileWriterError) in
            try AudioFileWriter(url: url, description: description, firstTick: firstTick, timecode: timecode)
        }
        return make
    }

    func start() {
        source.start(
            queue: queue, deliver: { [weak self] buffer in self?.receive(buffer) },
            ended: { [weak self] end in
                guard let self else { return }
                queue.async { self.end(end) }
            })
    }

    /// Stops the capture at the recorder's request and finalizes its file;
    /// returns once every file's end was reported.
    func stop() async {
        await source.stop()
        let tasks = queue.sync { () -> [Task<Void, Never>] in
            isEnding = true
            flushCorrection()
            finishFile()
            leaveGuide()
            return finishing
        }
        for task in tasks { await task.value }
    }

    /// Ends the capture by itself: its file ends, then it says why. The
    /// correction's held-back samples go to the file, unless its writer failed.
    private func end(_ reason: AudioTracker.CaptureEnd, keepTail: Bool = true) {
        guard !isEnding else { return }
        isEnding = true
        if keepTail { flushCorrection() }
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
        guard channels.first?.isEmpty == false else { return }
        if id == .systemAudio, channels.count != GuideTrack.systemAudio.channelCount {
            end(.captureFailed("the system audio came with \(channels.count) channels instead of \(GuideTrack.systemAudio.channelCount)"))
            return
        }
        let pts = CMTimeConvertScale(CMSampleBufferGetPresentationTimeStamp(buffer), timescale: 1_000_000_000, method: .roundHalfAwayFromZero)
        let time = context.clock.sinceStart(host: UInt64(max(0, pts.value)))
        for chunk in correction.correct(channels, at: time, arrival: arrival) where !isEnding { take(chunk) }
        reportClockDrift(at: arrival)
    }

    /// The correction's samples left at the end of its input go to the file.
    private func flushCorrection() {
        for chunk in correction.flush() { take(chunk) }
    }

    /// A corrected chunk: to the guide track, and placed in the audio file.
    private func take(_ chunk: ClockDriftCorrection.Chunk) {
        let channels = chunk.channels
        let time = chunk.time
        let count = channels[0].count
        let appliedBefore = applied
        applied = chunk.applied
        joinGuide(channelCount: channels.count)
        guides.receive(channels, from: label, to: guide, at: time)

        if timeline != nil, channelCount != channels.count { finishFile() }
        if timeline == nil { startTimeline(channelCount: channels.count, appliedBefore: appliedBefore) }
        var placement = timeline!.place(bufferAt: time, sampleCount: count)
        if let gap = placement.gap { reports.event(gapEvent(gap, at: time)) }
        if placement.action == .endFile {
            finishFile()
            startTimeline(channelCount: channels.count, appliedBefore: appliedBefore)
            placement = timeline!.place(bufferAt: time, sampleCount: count)
        }
        guard case .write(let silence, let firstSample, let position) = placement.action else { return }
        if open == nil {
            guard openFile(firstTick: timeline!.firstTick!) else { return }
        }
        if silence > 0 { open!.waiting.append((.silence(silence), position - silence)) }
        open!.waiting.append((.samples(firstSample == 0 ? channels : channels.map { Array($0[firstSample...]) }), position))
        writeWaiting()
    }

    private func startTimeline(channelCount: Int, appliedBefore: Double) {
        timeline = AudioFileTimeline()
        self.channelCount = channelCount
        appliedAtFileStart = appliedBefore
    }

    /// The correction's status to the recorder about once a second, and with
    /// `--debug` every 10 s as a detail line.
    private func reportClockDrift(at now: Int64) {
        let reported = clockDriftReported ?? now - RecorderValues.clockDriftStatusInterval.nanoseconds
        let debugged = clockDriftDebugged ?? now
        clockDriftDebugged = debugged
        guard now - reported >= RecorderValues.clockDriftStatusInterval.nanoseconds else { return }
        clockDriftReported = now
        let status = correction.status
        reports.clockDrift(status)
        guard now - debugged >= RecorderValues.clockDriftDebugInterval.nanoseconds else { return }
        clockDriftDebugged = now
        RecorderLog.detail(DebugLine.clockDrift(of: label, status), category: "recorder")
    }

    private func gapEvent(_ gap: AudioGap, at time: Int64) -> RecordingEvent {
        var event = RecordingEvent(at: time, event: .audioInputGap, audioSource: name)
        event.length = (Double(gap.length) / 1_000_000).rounded() / 1000
        return event
    }

    private func writeWaiting() {
        do {
            try open?.write()
        } catch {
            fail(error)
            return
        }
        if let waiting = open?.waitingSamples, waiting > Int64(RecorderValues.audioWaitBoundSeconds * RecorderValues.audioSampleRate) {
            end(.writerFellBehind)
        }
    }

    private func fail(_ error: AudioFileWriterError) {
        open?.waiting = []
        end(error.isDiskFull ? .diskFull : .writerFailed(error.description), keepTail: false)
    }

    // MARK: Files

    /// The file's writer, at its first tick; false when it cannot be made,
    /// which ends the capture.
    private func openFile(firstTick: Int64) -> Bool {
        let description: AudioFileDescription = switch id {
        case .input(let uid): AudioFileDescription(
            source: .audioInput(number: number, name: name, coreAudioUID: uid, channelCount: channelCount),
            recordingStarted: context.startedText, app: context.app)
        case .systemAudio: AudioFileDescription(source: .systemAudio, recordingStarted: context.startedText, app: context.app)
        }
        let fileName = context.claimAudioFileName(tick: firstTick, source: description.source)
        do {
            let writer = try makeWriter(context.folder.appending(path: fileName), description, firstTick)
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

    /// Ends the current file, if any: the samples still waiting are written
    /// for at most the drain timeout, then it is finalized. Its end counts
    /// only what the writer took; the rest is lost (`lostSamples`).
    private func finishFile() {
        let correction = applied - appliedAtFileStart
        timeline = nil
        guard let file = open else { return }
        open = nil
        let reports = reports
        let drainTimeout = drainTimeout
        let name = name
        finishing.append(Task {
            // No longer open: only this task uses the writer from here on.
            var file = file
            var (failure, lost) = await Self.drain(&file, timeout: drainTimeout, name: name)
            var entry = file.entry
            do throws(AudioFileWriterError) {
                try await file.writer.finish(endPosition: file.written > 0 ? file.written : nil)
                entry.state = .finalized
            } catch {
                failure = failure ?? error
                entry.state = .notFinalized
            }
            let duration = Double(file.written) / Double(RecorderValues.audioSampleRate)
            entry.end = entry.start + duration
            entry.clockDrift(correction: correction, duration: duration)
            reports.fileEnded(AudioFileEnd(file: entry, error: failure, lostSamples: lost))
        })
    }

    /// Writes the waiting samples, waiting for the writer for at most
    /// `timeout` on a clock that does not count sleep; an error when the
    /// writer failed or samples are left, which are lost.
    private static func drain(
        _ file: inout OpenFile, timeout: Duration, name: String
    ) async -> (error: AudioFileWriterError?, lost: Int64) {
        let clock = SuspendingClock()
        let deadline = clock.now + timeout
        while true {
            do {
                try file.write()
            } catch {
                file.waiting = []
                return (error, 0)
            }
            let left = file.waitingSamples
            if left == 0 { return (nil, 0) }
            if clock.now >= deadline {
                file.waiting = []
                let seconds = Double(left) / Double(RecorderValues.audioSampleRate)
                let error = AudioFileWriterError(nil, while: "the writer took none of the last \(left) samples ("
                    + String(format: "%.3f", seconds) + " s) of \(name) within \(timeout); they are lost")
                return (error, left)
            }
            try? await clock.sleep(for: .milliseconds(5))
        }
    }

    // MARK: Guide track

    private func joinGuide(channelCount: Int) {
        guard guideChannels != channelCount else { return }
        if guideChannels != nil { guides.remove(source: label, from: guide) }
        guides.add(source: label, channelCount: channelCount, to: guide)
        guideChannels = channelCount
    }

    private func leaveGuide() {
        guard guideChannels != nil else { return }
        guides.remove(source: label, from: guide)
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
