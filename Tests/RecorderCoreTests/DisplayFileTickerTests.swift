import CoreVideo
import Foundation
import RecorderLogic
import Synchronization
import Testing
@testable import RecorderCore

/// A display file's ticks with a stand-in writer: what reaches the
/// recording manifest when a writer fails, falls behind or is slow at the end.
@Suite struct DisplayFileTickerTests {
    final class StandInWriter: DisplayFileWriting, @unchecked Sendable {
        let firstTick: Int64
        var isReady = true
        /// Set by a test's task while the ticker drains, so it is locked.
        private let guideReady = Mutex(true)
        var isGuideReady: Bool {
            get { guideReady.withLock { $0 } }
            set { guideReady.withLock { $0 = newValue } }
        }
        var appendError: DisplayFileWriterError?
        var finishError: DisplayFileWriterError?
        private(set) var written: [Int64] = []
        private(set) var finishedAt: Int64??

        private(set) var guides: [(GuideTrack, Int64, Int)] = []
        /// The first channel of every guide sample written, in order.
        private(set) var guideSamples: [GuideTrack: [Float]] = [:]

        init(firstTick: Int64) { self.firstTick = firstTick }

        func appendGuide(_ guide: GuideTrack, _ channels: [[Float]], at position: Int64) throws(DisplayFileWriterError) -> Bool {
            if let appendError { throw appendError }
            guard isReady, isGuideReady else { return false }
            guides.append((guide, position, channels[0].count))
            guideSamples[guide, default: []] += channels[0]
            return true
        }

        func append(_ frame: CVPixelBuffer, tick: Int64) throws(DisplayFileWriterError) -> Bool {
            if let appendError { throw appendError }
            guard isReady else { return false }
            written.append(tick)
            return true
        }

        func finish(lastTick: Int64?) async throws(DisplayFileWriterError) {
            finishedAt = .some(lastTick)
            if let finishError { throw finishError }
        }
    }

    private let grid = TickGrid.recording
    private let frame: CVPixelBuffer = {
        var buffer: CVPixelBuffer?
        CVPixelBufferCreate(nil, 16, 16, kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange, nil, &buffer)
        return buffer!
    }()

    /// A ticker whose writer is kept for inspection.
    private func ticker(captureStart: Int64 = 0, drainTimeout: Duration = .milliseconds(50))
        -> (DisplayFileTicker, () -> StandInWriter?) {
        nonisolated(unsafe) var made: StandInWriter?
        let ticker = DisplayFileTicker(captureStart: captureStart, drainTimeout: drainTimeout) { firstTick throws(DisplayFileWriterError) in
            let writer = StandInWriter(firstTick: firstTick)
            made = writer
            return (writer, RecordingManifest.DisplayFile(
                name: "f.mov", display: "D", displayUUID: "U", frameSize: FrameSize(width: 16, height: 16),
                start: TickGrid.recording.seconds(ofTick: firstTick), timecode: "00:00:00:00"))
        }
        return (ticker, { made })
    }

    @Test func theFileEndCarriesItsStartEntryAndItsFinalState() async throws {
        let (ticker, writer) = ticker()
        guard case .fileStarted(let entry) = ticker.receive(frame, capturedAt: 0) else { Issue.record("no file"); return }
        #expect(entry.name == "f.mov")
        #expect(ticker.tick(now: grid.time(ofTick: 2)) == nil)
        let end = try #require(await ticker.finish(now: grid.time(ofTick: 2), writeWaitingTicks: true))
        #expect(end.file.name == "f.mov")
        #expect(end.file.state == .finalized)
        #expect(end.file.end == grid.seconds(ofTick: 3))
        #expect(end.error == nil)
        #expect(writer()?.written == [0, 1, 2])
    }

    /// Guide samples are placed in the file from its first tick; those
    /// before it are dropped, and those the writer cannot take wait.
    @Test func guideSamplesArePlacedFromTheFilesFirstTick() throws {
        let (ticker, writer) = ticker()
        // Before a file: nothing.
        #expect(ticker.receiveGuide(.microphones, [[0, 0]], positionFromStart: 0) == nil)
        _ = ticker.receive(frame, capturedAt: grid.time(ofTick: 2) - 1)
        let made = try #require(writer())
        #expect(made.firstTick == 2)
        let samplesPerTick = RecorderValues.audioSampleRate / RecorderValues.framesPerSecond
        let chunk = [Float](repeating: 0, count: 4800)
        _ = ticker.receiveGuide(.microphones, [chunk], positionFromStart: 0)
        made.isReady = false
        _ = ticker.receiveGuide(.systemAudio, [chunk, chunk], positionFromStart: 4800)
        made.isReady = true
        #expect(ticker.tick(now: grid.time(ofTick: 2)) == nil)
        #expect(made.guides.map(\.0) == [.microphones, .systemAudio])
        #expect(made.guides.map(\.1) == [0, Int64(4800 - 2 * samplesPerTick)])
        #expect(made.guides.map(\.2) == [4800 - 2 * samplesPerTick, 4800])
    }

    /// A ticker's file from tick 0, its microphones' source delivering
    /// 0.25 from t0 on, handed over up to `handedOver` samples.
    private func guidedFile(
        handedOver: Int, guideReady: Bool = true, drainTimeout: Duration = .milliseconds(50)
    ) throws -> (DisplayFileTicker, StandInWriter, GuideTrackMix) {
        let (ticker, writer) = ticker(drainTimeout: drainTimeout)
        _ = ticker.receive(frame, capturedAt: 0)
        let made = try #require(writer())
        made.isGuideReady = guideReady
        var mix = GuideTrackMix(.microphones)
        mix.add(source: "A", channelCount: 1)
        mix.receive([[Float](repeating: 0.25, count: handedOver)], from: "A", at: 0)
        _ = ticker.receiveGuide(.microphones, mix.mix(upTo: Int64(handedOver)), positionFromStart: 0)
        return (ticker, made, mix)
    }

    private let videoSamples = 31 * RecorderValues.audioSampleRate / RecorderValues.framesPerSecond

    /// The last mix as the capture gives it: what the feed handed over
    /// since `handedOver`, mixed in 100 ms steps, then a peek up to the
    /// video's end.
    private func lastMix(_ mix: inout GuideTrackMix, from handedOver: Int64, handOverUpTo end: Int64, videoEnd: Int64) -> GuideLastMix {
        var pending: [GuideLastMix.Chunk] = []
        var position = handedOver
        while position < end {
            let next = min(end, position + 4800)
            pending.append(.init(guide: .microphones, channels: mix.mix(upTo: next), positionFromStart: position))
            position = next
        }
        let peek = mix.peek(upTo: videoEnd)
        return GuideLastMix(pending: pending, peeks: [.microphones: .init(start: peek.start, channels: peek.channels)])
    }

    /// At the end, the hand-overs that came while the file ended and a peek
    /// at what the sources delivered: the guide tracks end exactly with the
    /// video, with sound, not padding, however long the end took, also when
    /// the video's last ticks waited for the writer and the feed handed over
    /// past the video's end.
    @Test func theGuideTracksEndWithTheVideoAfterAStreamStopLongerThanFiveSeconds() async throws {
        let ticksOfVideo: Int64 = 7 * 30
        let videoSamples = Int((ticksOfVideo + 1) * 1600)
        let handedOver = 48_000
        let (ticker, made, handed) = try guidedFile(handedOver: handedOver, drainTimeout: .seconds(30))
        var mix = handed
        mix.receive([[Float](repeating: 0.25, count: videoSamples - handedOver + 9600)], from: "A", at: 1_000_000_000)
        #expect(ticker.tick(now: grid.time(ofTick: ticksOfVideo - 3)) == nil)
        // The video's last ticks wait for the writer.
        made.isReady = false
        let ready = Task {
            try? await Task.sleep(for: .milliseconds(20))
            made.isReady = true
        }
        // The stream took 6 s to stop; the feed went on handing over, past the video's end.
        let last = lastMix(&mix, from: Int64(handedOver), handOverUpTo: Int64(videoSamples + 4800), videoEnd: Int64(videoSamples))
        let end = try #require(await ticker.finish(now: grid.time(ofTick: ticksOfVideo), writeWaitingTicks: true) { videoEnd in
            #expect(videoEnd == Int64(videoSamples))
            return last
        })
        await ready.value
        #expect(made.written.last == ticksOfVideo)
        let samples = try #require(made.guideSamples[.microphones])
        #expect(samples.count == videoSamples)
        #expect(samples.allSatisfy { $0 == 0.25 })
        #expect(end.guideTracksCut.isEmpty)
    }

    /// A long last mix waits for the writer as one, so the bound on waiting
    /// hand-overs drops none of it.
    @Test func aLongLastMixIsNotDroppedWhileTheWriterWaits() async throws {
        let ticksOfVideo: Int64 = 7 * 30
        let videoSamples = Int((ticksOfVideo + 1) * 1600)
        let handedOver = 48_000
        let (ticker, made, handed) = try guidedFile(handedOver: handedOver, drainTimeout: .seconds(30))
        var mix = handed
        mix.receive([[Float](repeating: 0.25, count: videoSamples - handedOver)], from: "A", at: 1_000_000_000)
        #expect(ticker.tick(now: grid.time(ofTick: ticksOfVideo)) == nil)
        let last = lastMix(&mix, from: Int64(handedOver), handOverUpTo: Int64(videoSamples - 9600), videoEnd: Int64(videoSamples))
        #expect(last.pending.count > 20)
        made.isGuideReady = false
        let ready = Task {
            try? await Task.sleep(for: .milliseconds(20))
            made.isGuideReady = true
        }
        let end = try #require(await ticker.finish(now: grid.time(ofTick: ticksOfVideo), writeWaitingTicks: true) { _ in last })
        await ready.value
        let samples = try #require(made.guideSamples[.microphones])
        #expect(samples.count == videoSamples)
        #expect(samples.allSatisfy { $0 == 0.25 })
        #expect(end.guideTracksCut.isEmpty)
    }

    /// A last mix the writer does not take within the drain timeout is told.
    @Test func aLastMixTheWriterDoesNotTakeInTimeIsTold() async throws {
        let (ticker, made, mix) = try guidedFile(handedOver: 48_000)
        #expect(ticker.tick(now: grid.time(ofTick: 30)) == nil)
        made.isGuideReady = false
        let peek = mix.peek(upTo: Int64(videoSamples))
        let end = try #require(await ticker.finish(now: grid.time(ofTick: 30), writeWaitingTicks: true) { _ in
            GuideLastMix(pending: [], peeks: [.microphones: .init(start: peek.start, channels: peek.channels)])
        })
        #expect(made.guideSamples[.microphones]?.count == 48_000)
        #expect(end.guideTracksCut == [GuideTrackCut(guide: .microphones, why: .writerTimedOut)])
        #expect(end.file.state == .finalized)
    }

    /// Should the feed have mixed past what the file received, the tail is
    /// not padded: nothing is written and the file end says so.
    @Test func aLastMixThatStartsAfterWhatTheFileReceivedWritesNothingAndSaysSo() async throws {
        let (ticker, made, handed) = try guidedFile(handedOver: 48_000)
        var mix = handed
        _ = mix.mix(upTo: 52_800)
        #expect(ticker.tick(now: grid.time(ofTick: 30)) == nil)
        let peek = mix.peek(upTo: 49_600)
        let end = try #require(await ticker.finish(now: grid.time(ofTick: 30), writeWaitingTicks: true) { _ in
            GuideLastMix(pending: [], peeks: [.microphones: .init(start: peek.start, channels: peek.channels)])
        })
        #expect(made.guideSamples[.microphones]?.count == 48_000)
        #expect(end.guideTracksCut == [GuideTrackCut(guide: .microphones, why: .samplesGone)])
    }

    /// The guide samples at the end wait for the writer as the ticks do.
    @Test func theLastGuideSamplesWaitForTheWriterWithinTheDrainTimeout() async throws {
        // A drain timeout far above the writer's wait, so a slow machine passes too.
        let (ticker, made, mix) = try guidedFile(handedOver: videoSamples, guideReady: false, drainTimeout: .seconds(30))
        #expect(ticker.tick(now: grid.time(ofTick: 30)) == nil)
        #expect(made.guides.isEmpty)
        let ready = Task {
            try? await Task.sleep(for: .milliseconds(20))
            made.isGuideReady = true
        }
        let peek = mix.peek(upTo: Int64(videoSamples))
        _ = try #require(await ticker.finish(now: grid.time(ofTick: 30), writeWaitingTicks: true) { _ in
            GuideLastMix(pending: [], peeks: [.microphones: .init(start: peek.start, channels: peek.channels)])
        })
        await ready.value
        #expect(made.guides.map(\.2).reduce(0, +) == videoSamples, "\(made.guides.map(\.2))")
    }

    @Test func aWriterErrorReachesTheFileEnd() async throws {
        let (ticker, writer) = ticker()
        _ = ticker.receive(frame, capturedAt: 0)
        writer()?.appendError = DisplayFileWriterError(description: "cannot write f.mov: no luck", isDiskFull: false)
        #expect(ticker.tick(now: grid.time(ofTick: 1)) == .writerFailed("cannot write f.mov: no luck"))
        writer()?.finishError = DisplayFileWriterError(description: "cannot finalize f.mov: no luck", isDiskFull: false)
        let end = try #require(await ticker.finish(now: grid.time(ofTick: 1), writeWaitingTicks: false))
        #expect(end.file.state == .notFinalized)
        #expect(end.error == DisplayFileWriterError(description: "cannot write f.mov: no luck", isDiskFull: false))
    }

    @Test func aFullDiskEndsAsDiskFull() {
        let (ticker, writer) = ticker()
        _ = ticker.receive(frame, capturedAt: 0)
        writer()?.appendError = DisplayFileWriterError(description: "full", isDiskFull: true)
        #expect(ticker.tick(now: grid.time(ofTick: 1)) == .diskFull)
    }

    @Test func aFullDiskReachesTheFileEndAsAFullDisk() async throws {
        let (ticker, writer) = ticker()
        _ = ticker.receive(frame, capturedAt: 0)
        writer()?.appendError = DisplayFileWriterError(description: "full", isDiskFull: true)
        _ = ticker.tick(now: grid.time(ofTick: 1))
        let end = try #require(await ticker.finish(now: grid.time(ofTick: 1), writeWaitingTicks: false))
        #expect(end.error?.isDiskFull == true)
    }

    /// The writer's allowance before a display file ends includes its end:
    /// the waiting ticks are written for as long as they may wait (D53).
    @Test func theEndWaitsForTheWriterAsLongAsTicksMayWait() {
        #expect(DisplayFileTicker.defaultDrainTimeout == .seconds(RecorderValues.displayFileLateTickSeconds))
        #expect(DisplayFileTicker.defaultDrainTimeout == .seconds(6))
    }

    @Test func aWriterThatFellBehindIsStillFinalized() async throws {
        let (ticker, writer) = ticker()
        _ = ticker.receive(frame, capturedAt: 0)
        writer()?.isReady = false
        let behind = Int64(RecorderValues.lateTickBound) + 1
        #expect(ticker.tick(now: grid.time(ofTick: behind)) == .writerFellBehind)
        let end = try #require(await ticker.finish(now: grid.time(ofTick: behind), writeWaitingTicks: false))
        #expect(writer()?.finishedAt != nil)
        #expect(end.file.state == .finalized)
    }

    @Test func aDrainThatTimesOutStillFinalizesAndSaysSo() async throws {
        let (ticker, writer) = ticker()
        _ = ticker.receive(frame, capturedAt: 0)
        writer()?.isReady = false
        _ = ticker.tick(now: grid.time(ofTick: 3))
        let end = try #require(await ticker.finish(now: grid.time(ofTick: 3), writeWaitingTicks: true))
        #expect(writer()?.finishedAt != nil)
        #expect(end.file.state == .finalized)
        #expect(end.error?.description.contains("4 ticks") == true)
    }

    @Test func theTicksDueAtTheEndAreWrittenBeforeTheFileIsFinalized() async throws {
        let (ticker, writer) = ticker()
        _ = ticker.receive(frame, capturedAt: 0)
        _ = ticker.tick(now: grid.time(ofTick: 1))
        let end = try #require(await ticker.finish(now: grid.time(ofTick: 4), writeWaitingTicks: true))
        #expect(writer()?.written == [0, 1, 2, 3, 4])
        #expect(end.file.end == grid.seconds(ofTick: 5))
    }

    @Test func aWriterThatCannotBeCreatedEndsTheCapture() {
        let ticker = DisplayFileTicker(captureStart: 0) { _ throws(DisplayFileWriterError) in
            throw DisplayFileWriterError(description: "cannot create f.mov", isDiskFull: false)
        }
        #expect(ticker.receive(frame, capturedAt: 0) == .ended(.writerFailed("cannot create f.mov")))
    }

    @Test func noFileNoEnd() async {
        let (ticker, _) = ticker()
        #expect(await ticker.finish(now: 0, writeWaitingTicks: true) == nil)
    }
}

/// Stopping a stream while it is still starting.
@Suite struct StreamLifecycleTests {
    final class StandInStream: CaptureStream, @unchecked Sendable {
        private let lock = NSLock()
        private var events: [String] = []
        private var release: CheckedContinuation<Void, Never>?
        private var startedWaiting: CheckedContinuation<Void, Never>?
        var log: [String] { lock.withLock { events } }

        func startCapture() async throws {
            lock.withLock { events.append("start begun") }
            await withCheckedContinuation { continuation in
                lock.withLock {
                    release = continuation
                    startedWaiting?.resume()
                    startedWaiting = nil
                }
            }
            lock.withLock { events.append("started") }
        }

        func stopCapture() async throws {
            lock.withLock { events.append("stopped") }
        }

        func waitUntilStarting() async {
            await withCheckedContinuation { continuation in
                lock.withLock {
                    if release != nil { continuation.resume() } else { startedWaiting = continuation }
                }
            }
        }

        func finishStarting() {
            lock.withLock { release }?.resume()
        }
    }

    @Test func aStreamStoppedWhileItStartsIsStoppedOnceStarted() async throws {
        let lifecycle = StreamLifecycle()
        let stream = StandInStream()
        let starting = Task { try await lifecycle.start(stream) }
        await stream.waitUntilStarting()
        await lifecycle.stop()
        stream.finishStarting()
        try await starting.value
        #expect(stream.log == ["start begun", "started", "stopped"])
    }

    @Test func aStreamStartedAfterTheStopNeverStarts() async throws {
        let lifecycle = StreamLifecycle()
        await lifecycle.stop()
        let stream = StandInStream()
        try await lifecycle.start(stream)
        #expect(stream.log.isEmpty)
    }

    @Test func aRunningStreamIsStoppedOnce() async throws {
        let lifecycle = StreamLifecycle()
        let stream = StandInStream()
        let starting = Task { try await lifecycle.start(stream) }
        await stream.waitUntilStarting()
        stream.finishStarting()
        try await starting.value
        await lifecycle.stop()
        await lifecycle.stop()
        #expect(stream.log == ["start begun", "started", "stopped"])
    }
}
