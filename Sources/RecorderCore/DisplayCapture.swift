import AVFoundation
import CoreMedia
import Foundation
import RecorderLogic
@preconcurrency import ScreenCaptureKit
import Synchronization

/// What every display capture of a recording shares: the recording folder,
/// the clock, the timecode, and the displays' bounds as last read, which
/// the recorder updates whenever the displays change.
public final class RecordingContext: Sendable {
    public let folder: URL
    public let started: Date
    public let timeZone: TimeZone
    public let timecode: Timecode
    private let state: Mutex<State>

    private struct State {
        var clock: SharedClock
        var bounds: [String: ScreenRect] = [:]
        var lastDisplayChange: Int64?
        var takenNames: Set<String> = []
    }

    init(folder: URL, started: Date, timeZone: TimeZone, clock: SharedClock) {
        self.folder = folder
        self.started = started
        self.timeZone = timeZone
        timecode = Timecode(start: started, timeZone: timeZone)
        state = Mutex(State(clock: clock))
    }

    public var clock: SharedClock { state.withLock { $0.clock } }

    func rereadClocks() {
        state.withLock { $0.clock.reread(readClocks()) }
    }

    /// Nanoseconds from t0 now.
    func now() -> Int64 {
        clock.sinceStart(continuous: continuousNow())
    }

    func update(_ displays: [ConnectedDisplay], lastDisplayChange: Int64?) {
        state.withLock {
            for display in displays { $0.bounds[display.uuid] = display.bounds }
            $0.lastDisplayChange = lastDisplayChange
        }
    }

    func bounds(of uuid: String) -> (ScreenRect?, Int64?) {
        state.withLock { ($0.bounds[uuid], $0.lastDisplayChange) }
    }

    /// The display file's name for a file starting at `tick`, never one already used.
    func claimFileName(tick: Int64, number: Int, display: String) -> String {
        let start = started.addingTimeInterval(TickGrid.recording.seconds(ofTick: tick))
        return state.withLock { state in
            let existing = Set((try? FileManager.default.contentsOfDirectory(atPath: folder.path(percentEncoded: false))) ?? [])
            let name = RecordingNames.displayFile(
                start: start, timeZone: timeZone, number: number, display: display, taken: state.takenNames.union(existing))
            state.takenNames.insert(name)
            return name
        }
    }
}

/// How a display file ended, for the recording manifest.
public struct DisplayFileEnd: Sendable {
    public var name: String
    public var end: Double
    public var finalized: Bool
    public var framesRepeatedForLateness: Int
}

/// One display's stream and its display file: frames pass the display
/// check, ticks choose the newest frame, the writer writes them. A capture
/// has at most one display file; a new file needs a new capture. Everything
/// runs on its own queue.
public final class DisplayCapture: NSObject, @unchecked Sendable, SCStreamOutput, SCStreamDelegate {
    public let uuid: String
    public let number: Int
    public let name: String
    public let frameSize: FrameSize
    private let displayID: CGDirectDisplayID
    private let context: RecordingContext
    private let queue: DispatchQueue
    private let grid = TickGrid.recording

    /// The file started; reports its manifest entry.
    private let onFileStarted: @Sendable (RecordingManifest.DisplayFile) -> Void
    /// The capture ended by itself, after its file was ended.
    private let onEnded: @Sendable (DisplayTracker.StreamEnd, DisplayFileEnd?) -> Void

    // Confined to `queue`.
    private var stream: SCStream?
    private var check = DisplayCheck()
    private var ticks = TickLoop<CVPixelBuffer>()
    private var writer: DisplayFileWriter?
    private var fileName: String?
    private var timer: DispatchSourceTimer?
    /// No frame and no tick is taken any more.
    private var isEnding = false
    /// Finishing the file, by the capture itself or at the recorder's request; set once.
    private var finishTask: Task<DisplayFileEnd?, Never>?
    private static let queueKey = DispatchSpecificKey<Int>()

    init(
        uuid: String, displayID: UInt32, number: Int, name: String, frameSize: FrameSize, context: RecordingContext,
        onFileStarted: @escaping @Sendable (RecordingManifest.DisplayFile) -> Void,
        onEnded: @escaping @Sendable (DisplayTracker.StreamEnd, DisplayFileEnd?) -> Void
    ) {
        self.uuid = uuid
        self.displayID = displayID
        self.number = number
        self.name = name
        self.frameSize = frameSize
        self.context = context
        self.onFileStarted = onFileStarted
        self.onEnded = onEnded
        queue = DispatchQueue(label: "msr.display.\(number)", qos: .userInteractive)
        super.init()
        queue.setSpecific(key: Self.queueKey, value: ObjectIdentifier(self).hashValue)
    }

    /// Starts the stream; its failure ends the capture as a failing stream.
    func start() {
        Task {
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
                guard let display = content.displays.first(where: { $0.displayID == displayID }) else {
                    throw CaptureError("ScreenCaptureKit does not list the display")
                }
                let configuration = SCStreamConfiguration()
                configuration.width = frameSize.width
                configuration.height = frameSize.height
                configuration.pixelFormat = kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
                configuration.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(grid.framesPerSecond))
                configuration.queueDepth = 8
                configuration.showsCursor = true
                configuration.scalesToFit = true
                let stream = SCStream(filter: SCContentFilter(display: display, excludingWindows: []),
                                      configuration: configuration, delegate: self)
                try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)
                queue.sync { self.stream = stream }
                try await stream.startCapture()
            } catch {
                queue.async { self.end(.streamFailed(Self.describe(error))) }
            }
        }
    }

    private struct CaptureError: Error, LocalizedError {
        let errorDescription: String?
        init(_ text: String) { errorDescription = text }
    }

    private static func describe(_ error: any Error) -> String {
        let nsError = error as NSError
        return "\(nsError.localizedDescription) (\(nsError.domain) \(nsError.code))"
    }

    // MARK: Frames

    public func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, !isEnding, sampleBuffer.isValid,
              let attachments = (CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false)
                as? [[SCStreamFrameInfo: Any]])?.first,
              let statusValue = attachments[.status] as? Int, SCFrameStatus(rawValue: statusValue) == .complete,
              let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer),
              let rectDictionary = attachments[.screenRect] as CFTypeRef?,
              CFGetTypeID(rectDictionary) == CFDictionaryGetTypeID(),
              let screenRect = CGRect(dictionaryRepresentation: rectDictionary as! CFDictionary),
              // When the frame was shown, in mach absolute time: the host clock.
              let displayTime = (attachments[.displayTime] as? NSNumber)?.uint64Value
        else { return }
        let capturedAt = context.clock.sinceStart(host: nanoseconds(machTicks: displayTime))
        let (bounds, lastChange) = context.bounds(of: uuid)
        guard let bounds else { return }
        switch check.judge(frameRect: ScreenRect(screenRect), displayBounds: bounds, capturedAt: capturedAt,
                           lastDisplayChange: lastChange) {
        case .passes:
            ticks.receive(pixelBuffer, capturedAt: capturedAt)
            if writer == nil { startFile() }
        case .fails:
            break
        case .showsAnotherDisplay:
            end(.showsAnotherDisplay)
        }
    }

    public func stream(_ stream: SCStream, didStopWithError error: any Error) {
        queue.async { self.end(.streamFailed(Self.describe(error))) }
    }

    // MARK: The display file

    private func startFile() {
        guard let firstTick = ticks.firstTick else { return }
        let name = context.claimFileName(tick: firstTick, number: number, display: self.name)
        do {
            writer = try DisplayFileWriter(
                url: context.folder.appending(path: name), frameSize: frameSize, firstTick: firstTick,
                timecode: context.timecode)
        } catch {
            end(error.isDiskFull ? .diskFull : .writerFailed(error.description))
            return
        }
        fileName = name
        onFileStarted(RecordingManifest.DisplayFile(
            name: name, display: self.name, displayUUID: uuid, frameSize: frameSize,
            start: grid.seconds(ofTick: firstTick), timecode: context.timecode.text(ofTick: firstTick)))
        let timer = DispatchSource.makeTimerSource(flags: .strict, queue: queue)
        let interval = DispatchTimeInterval.nanoseconds(Int(grid.time(ofTick: 1)))
        timer.schedule(deadline: .now(), repeating: interval, leeway: .milliseconds(1))
        timer.setEventHandler { [weak self] in self?.tick() }
        timer.resume()
        self.timer = timer
    }

    private func tick() {
        guard !isEnding, let writer else { return }
        do {
            let outcome = try ticks.advance(to: context.now()) { tick, frame in try writer.append(frame, tick: tick) }
            if outcome == .writerFellBehind { end(.writerFellBehind) }
        } catch let error as DisplayFileWriterError {
            end(error.isDiskFull ? .diskFull : .writerFailed(error.description))
        } catch {
            end(.writerFailed(Self.describe(error)))
        }
    }

    // MARK: Ending

    /// Ends the capture by itself, then reports why; unless the recorder stopped it first.
    private func end(_ reason: DisplayTracker.StreamEnd) {
        guard !isEnding else { return }
        guard let finishing = beginFinishing(writeWaitingTicks: reason != .writerFellBehind) else { return }
        Task { onEnded(reason, await finishing.value) }
    }

    /// Stops the capture at the recorder's request and finalizes its file;
    /// if the capture is already ending by itself, waits for that.
    func stop() async -> DisplayFileEnd? {
        let finishing = beginFinishing(writeWaitingTicks: true) ?? queue.sync { finishTask }
        return await finishing?.value
    }

    /// Starts finishing the file once; nil when that has begun already.
    private func beginFinishing(writeWaitingTicks: Bool) -> Task<DisplayFileEnd?, Never>? {
        let begin = { () -> Task<DisplayFileEnd?, Never>? in
            guard self.finishTask == nil else { return nil }
            self.isEnding = true
            self.timer?.cancel()
            self.timer = nil
            let task = Task { await self.finish(writeWaitingTicks: writeWaitingTicks) }
            self.finishTask = task
            return task
        }
        return DispatchQueue.getSpecific(key: Self.queueKey) == ObjectIdentifier(self).hashValue ? begin() : queue.sync(execute: begin)
    }

    private func finish(writeWaitingTicks: Bool) async -> DisplayFileEnd? {
        let stream = queue.sync { self.stream }
        try? await stream?.stopCapture()
        guard let (writer, fileName) = queue.sync(execute: { () -> (DisplayFileWriter, String)? in
            guard let writer = self.writer, let fileName = self.fileName else { return nil }
            return (writer, fileName)
        }) else { return nil }
        var finalized = writeWaitingTicks ? await drain(writer) : false
        let (lastTick, late) = queue.sync { (ticks.lastWrittenTick, ticks.framesRepeatedForLateness) }
        if finalized {
            do { try await writer.finish(lastTick: lastTick) } catch { finalized = false }
        }
        return DisplayFileEnd(
            name: fileName, end: grid.seconds(ofTick: (lastTick ?? writer.firstTick - 1) + 1), finalized: finalized,
            framesRepeatedForLateness: late)
    }

    /// Writes the ticks still waiting, giving the writer up to the late-tick bound's time.
    private func drain(_ writer: DisplayFileWriter) async -> Bool {
        let deadline = ContinuousClock.now + .seconds(RecorderValues.lateTickBoundSeconds)
        while ContinuousClock.now < deadline {
            let left: Int
            do {
                left = try queue.sync { try ticks.drain { tick, frame in try writer.append(frame, tick: tick) } }
            } catch {
                return false
            }
            if left == 0 { return true }
            try? await Task.sleep(for: .milliseconds(5))
        }
        return false
    }
}
