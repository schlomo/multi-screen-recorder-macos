import AVFoundation
import CoreMedia
import Foundation
import RecorderLogic
@preconcurrency import ScreenCaptureKit
import Synchronization

/// How an audio file ended, for the recording manifest: its entry with its
/// end, state, clock drift and clock drift correction, the writer's error, if any, and the samples
/// the writer never took at the end. A file whose writer failed ends where
/// the file really ends; `failedAt` is the end its writer was given, the
/// time of the failure, and `lost` says what the file lacks (D66).
public struct AudioFileEnd: Equatable, Sendable {
    public var file: RecordingManifest.AudioFile
    public var error: AudioFileWriterError?
    public var lostSamples: Int64 = 0
    public var failedAt: Double?
    public var lost: String?
    /// The capture ended by a failure (`AudioTracker.CaptureEnd.isFailure`),
    /// which ended this file: the capture's failure event tells it.
    public var endedByFailedCapture = false

    /// Its failure is told by an event, its own or the capture's, so its
    /// problem is not printed again (D65).
    public var toldByAnEvent: Bool { !events.isEmpty || endedByFailedCapture }

    /// Samples lost at the end are `audio file writer fell behind`, a
    /// failure (D47), at the file's end.
    public var events: [RecordingEvent] {
        guard lostSamples > 0 else { return [] }
        var event = RecordingEvent(
            at: Int64((failureSeconds * 1_000_000_000).rounded()), event: .audioFileWriterFellBehind,
            audioSource: file.audioSource)
        event.errorDetail = error?.detail
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
    /// An audio input has no audio (true) or its sound returned (false), after its event (D69).
    var noAudio: @Sendable (Bool) -> Void
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
        case noAudio(AudioTracker.SourceID, number: Int, Bool)
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

/// One audio source's capture and its audio files: each incoming buffer's
/// sample peak goes to its level meter, buffers are resampled
/// to follow the shared clock by `ClockDriftCorrection`, and its corrected
/// audio placed on the tick grid by `AudioFileTimeline`, written by an
/// `AudioFileWriting` in appends of about 100 ms
/// (`audioFileAppendSamples`), and handed to the source's guide track. A gap over
/// the longest filled gap or a change of the channel count ends the file
/// and starts a new one, in the same capture; an audio input's new file,
/// after that or after no audio, starts only with its sound
/// (`NoAudioDetector`, D69). Everything
/// runs on its own queue but the level meter, which the status window reads.
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
    /// Where an audio input's sound goes for measuring its delay (D77); nil for the system audio.
    private let delays: AudioDelayFeed?
    private let guide: GuideTrack
    private let source: any AudioBufferSource
    private let reports: AudioCaptureReports
    private let makeWriter: MakeWriter
    private let drainTimeout: Duration
    /// The shared clock's time now: when a buffer arrived.
    private let now: @Sendable () -> Int64
    /// The input volume at a file's start, for its entry; nil for the system audio.
    private let inputVolume: (@Sendable () -> Double?)?
    private let queue: DispatchQueue
    private let level = Mutex(AudioLevelMeter())

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
    /// The correction applied up to the current file's start and up to the
    /// end of what was placed in it, in seconds.
    private var fileApplied: (start: Double, end: Double) = (0, 0)
    private var clockDriftSchedule = ClockDriftSchedule()
    /// An audio input's; nil for the system audio, which is excluded (D69).
    private var noAudio: NoAudioDetector?

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
        /// Samples gathered for the next append, after the waiting ones, from `gatheredPosition` on.
        private var gathered: [[Float]] = []
        private var gatheredPosition: Int64 = 0
        /// The end of what the writer took, in samples from the file's first tick.
        var written: Int64 = 0

        init(writer: any AudioFileWriting, entry: RecordingManifest.AudioFile) {
            self.writer = writer
            self.entry = entry
        }

        var gatheredSamples: Int64 { Int64(gathered.first?.count ?? 0) }

        /// Everything not taken by the writer yet, gathered samples included.
        var waitingSamples: Int64 { waiting.reduce(gatheredSamples) { $0 + $1.chunk.count } }

        /// Samples join the gathered ones, which they follow without a gap.
        mutating func gather(_ channels: [[Float]], at position: Int64) {
            if gathered.isEmpty {
                gathered = channels
                gatheredPosition = position
            } else {
                for index in gathered.indices { gathered[index].append(contentsOf: channels[index]) }
            }
        }

        /// Silence waits after the samples gathered before it.
        mutating func addSilence(_ count: Int64, at position: Int64) {
            closeGathered()
            waiting.append((.silence(count), position))
        }

        /// The gathered samples wait for the writer as one append.
        mutating func closeGathered() {
            guard !gathered.isEmpty else { return }
            waiting.append((.samples(gathered), gatheredPosition))
            gathered = []
        }

        /// Nothing is written any more: what waits and what was gathered is dropped.
        mutating func dropWaiting() {
            waiting = []
            gathered = []
        }

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
        now: (@Sendable () -> Int64)? = nil,
        inputVolume: (@Sendable () -> Double?)? = nil,
        delays: AudioDelayFeed? = nil,
        makeWriter: MakeWriter? = nil
    ) {
        self.delays = id == .systemAudio ? nil : delays
        self.id = id
        self.number = number
        self.name = name
        self.source = source
        self.context = context
        self.guides = guides
        guide = id == .systemAudio ? .systemAudio : .audioInputs
        self.reports = reports
        self.drainTimeout = drainTimeout
        self.now = now ?? { [context] in context.now() }
        self.inputVolume = id == .systemAudio ? nil : inputVolume ?? { nil }
        noAudio = id == .systemAudio ? nil : .recording()
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
            // A capture that ended by itself already kept or dropped its tail.
            if !isEnding {
                isEnding = true
                flushCorrection()
            }
            finishFile()
            leaveGuide()
            return finishing
        }
        for task in tasks { await task.value }
    }

    /// Ends the capture by itself: its file ends, then it says why. The
    /// correction's held-back samples go to the file, unless its writer
    /// failed or fell behind, which ends it while corrected audio is placed.
    private func end(_ reason: AudioTracker.CaptureEnd, keepTail: Bool = true) {
        guard !isEnding else { return }
        isEnding = true
        if keepTail { flushCorrection() }
        finishFile(endedByFailedCapture: reason.isFailure)
        leaveGuide()
        let tasks = finishing
        let reports = reports
        Task {
            await self.source.stop()
            for task in tasks { await task.value }
            reports.ended(reason)
        }
    }

    /// The level meter's reading: the sample peak since the last reading, and the peak hold.
    func readLevel(at now: Int64) -> AudioLevel {
        level.withLock { $0.read(at: now) }
    }

    // MARK: Buffers

    private func receive(_ buffer: CMSampleBuffer) {
        guard !isEnding, buffer.isValid, CMSampleBufferGetNumSamples(buffer) > 0 else { return }
        let arrival = now()
        let channels: [[Float]]
        do {
            channels = try Self.channels(of: buffer)
        } catch {
            end(.captureFailed(ErrorDetail(error)))
            return
        }
        guard channels.first?.isEmpty == false else { return }
        level.withLock { $0.measure(channels, at: arrival) }
        if id == .systemAudio, channels.count != GuideTrack.systemAudio.channelCount {
            end(.captureFailed(ErrorDetail(message: "the system audio came with \(channels.count) channels instead of \(GuideTrack.systemAudio.channelCount)")))
            return
        }
        let pts = CMTimeConvertScale(CMSampleBufferGetPresentationTimeStamp(buffer), timescale: 1_000_000_000, method: .roundHalfAwayFromZero)
        let time = context.clock.sinceStart(host: UInt64(max(0, pts.value)))
        let (audio, gap) = correction.correct(channels, at: time, arrival: arrival)
        if let gap { RecorderLog.detail(DetailLine.clockDriftGap(of: label, gap), category: "recorder") }
        for corrected in audio where !isEnding { take(corrected) }
        reportClockDrift(at: arrival)
    }

    /// The correction's samples left at the end of its input go to the file.
    private func flushCorrection() {
        for corrected in correction.flush() { take(corrected) }
    }

    /// Corrected audio: to the guide track, and placed in the audio file;
    /// an audio input's only from its sound on, and its no audio ends the file.
    private func take(_ corrected: ClockDriftCorrection.CorrectedAudio) {
        let channels = corrected.channels
        joinGuide(channelCount: channels.count)
        guides.receive(channels, from: label, to: guide, at: corrected.time)
        if case .input(let uid) = id { delays?.receive(channels, from: uid, at: corrected.time) }
        guard var detector = noAudio else {
            _ = place(channels, at: corrected.time, appliedBefore: corrected.appliedAtStart, applied: corrected.applied)
            return
        }
        let time = { (frame: Int) in corrected.time + Int64(frame) * 1_000_000_000 / Int64(RecorderValues.audioSampleRate) }
        // The correction's tail comes through here while the capture ends.
        let wasEnding = isEnding
        // A file that ended for another reason than no audio sends the rest of the chunk through the detector again.
        var offset = 0
        chunk: while offset < channels[0].count {
            let rest = offset == 0 ? channels : channels.map { Array($0[offset...]) }
            // A step that ended the file is the first of its pass: the detector starts the pass again from here.
            let beforePass = detector
            for step in detector.steps(for: rest, isPlacing: timeline != nil) {
                // A failure while placing ended the capture.
                guard isEnding == wasEnding else { break chunk }
                switch step {
                case .place(let frames, let leadingZeros):
                    let placed = frames == rest[0].indices && leadingZeros == 0 ? rest : rest.map {
                        [Float](repeating: 0, count: leadingZeros) + $0[frames]
                    }
                    let first = offset + frames.lowerBound
                    guard place(placed, at: time(first - leadingZeros), appliedBefore: corrected.appliedAtStart,
                                applied: corrected.applied)
                    else {
                        detector = beforePass
                        detector.fileEnded()
                        offset = first
                        continue chunk
                    }
                case .noAudioStarted(let frame):
                    finishFile()
                    reports.event(RecordingEvent(at: time(offset + frame), event: .noAudioStarted, audioSource: name))
                    reports.noAudio(true)
                case .noAudioStopped(let frame):
                    reports.event(RecordingEvent(at: time(offset + frame), event: .noAudioStopped, audioSource: name))
                    reports.noAudio(false)
                }
            }
            break
        }
        noAudio = detector
    }

    /// Audio placed in the audio file, its first sample at `time`. False when
    /// the audio ended the file by a gap or a change of the channel count and
    /// was not placed: an audio input starts its next file only with sound,
    /// which its detector decides (D69); the system audio starts it here.
    private func place(_ channels: [[Float]], at time: Int64, appliedBefore: Double, applied: Double) -> Bool {
        let count = channels[0].count
        let startsNextHere = noAudio == nil
        // A file starting here counts the correction from this audio's
        // start (`appliedBefore`): the drift added at a gap that ended a file is no file's.
        if timeline != nil, channelCount != channels.count {
            finishFile()
            if !startsNextHere { return false }
        }
        if timeline == nil { startTimeline(channelCount: channels.count, appliedBefore: appliedBefore) }
        var placement = timeline!.place(bufferAt: time, sampleCount: count)
        if let gap = placement.gap { reports.event(gapEvent(gap, at: time)) }
        if placement.action == .endFile {
            finishFile()
            if !startsNextHere { return false }
            startTimeline(channelCount: channels.count, appliedBefore: appliedBefore)
            placement = timeline!.place(bufferAt: time, sampleCount: count)
        }
        fileApplied.end = applied
        guard case .write(let silence, let firstSample, let position) = placement.action else { return true }
        if open == nil {
            guard openFile(firstTick: timeline!.firstTick!) else { return true }
        }
        if silence > 0 { open!.addSilence(silence, at: position - silence) }
        open!.gather(firstSample == 0 ? channels : channels.map { Array($0[firstSample...]) }, at: position)
        writeWaiting()
        return true
    }

    private func startTimeline(channelCount: Int, appliedBefore: Double) {
        timeline = AudioFileTimeline()
        self.channelCount = channelCount
        fileApplied = (appliedBefore, appliedBefore)
    }

    /// The correction's status to the recorder about once a second; the recorder
    /// writes the detail lines of all sources together.
    private func reportClockDrift(at now: Int64) {
        guard clockDriftSchedule.due(at: now) else { return }
        reports.clockDrift(correction.status)
    }

    private func gapEvent(_ gap: AudioGap, at time: Int64) -> RecordingEvent {
        var event = RecordingEvent(at: time, event: .audioInputGap, audioSource: name)
        event.length = (Double(gap.length) / 1_000_000).rounded() / 1000
        return event
    }

    /// Once about 100 ms are gathered, or silence waits, the writer gets what waits.
    private func writeWaiting() {
        if let gathered = open?.gatheredSamples, gathered >= Int64(RecorderValues.audioFileAppendSamples) {
            open?.closeGathered()
        }
        do {
            try open?.write()
        } catch {
            fail(error)
            return
        }
        if let waiting = open?.waitingSamples, waiting > Int64(RecorderValues.audioWaitBoundSeconds * RecorderValues.audioSampleRate) {
            end(.writerFellBehind, keepTail: false)
        }
    }

    private func fail(_ error: AudioFileWriterError) {
        open?.dropWaiting()
        end(error.isDiskFull ? .diskFull : .writerFailed(error.detail), keepTail: false)
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
            var entry = RecordingManifest.AudioFile(
                name: fileName, audioSource: description.sourceName, audioSourceUID: description.coreAudioUID,
                channels: description.channels, start: TickGrid.recording.seconds(ofTick: firstTick),
                timecode: context.timecode.text(ofTick: firstTick))
            entry.inputVolume = inputVolume?().map(InputVolumeChanges.rounded)
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
    private func finishFile(endedByFailedCapture: Bool = false) {
        let fileCorrection = fileApplied.end - fileApplied.start
        let clockDriftPpm = correction.status.clockDriftPpm
        timeline = nil
        guard let file = open else { return }
        open = nil
        let reports = reports
        let drainTimeout = drainTimeout
        let name = name
        let folder = context.folder
        finishing.append(Task {
            // No longer open: only this task uses the writer from here on.
            var file = file
            file.closeGathered()
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
            entry.clockDrift(correction: fileCorrection, ppm: clockDriftPpm)
            let end = await AudioFileEnd(file: entry, error: failure, lostSamples: lost, endedByFailedCapture: endedByFailedCapture)
                .readingItsFile(in: folder)
            reports.fileEnded(end)
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
                file.dropWaiting()
                return (error, 0)
            }
            let left = file.waitingSamples
            if left == 0 { return (nil, 0) }
            if clock.now >= deadline {
                file.dropWaiting()
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
        guard status == noErr else { throw PCMLayoutError(description: "an audio buffer cannot be read (error \(ErrorDetail.codeText(Int(status))))") }
        let buffers = UnsafeMutableAudioBufferListPointer(list.assumingMemoryBound(to: AudioBufferList.self))
        let raw = buffers.map { UnsafeRawBufferPointer(start: $0.mData, count: Int($0.mDataByteSize)) }
        return try withExtendedLifetime(block) { () throws(PCMLayoutError) -> [[Float]] in
            try splitIntoChannels(raw, layout: layout)
        }
    }
}
