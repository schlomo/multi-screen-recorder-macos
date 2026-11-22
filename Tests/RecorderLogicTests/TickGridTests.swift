import Foundation
import Testing
@testable import RecorderLogic

@Suite struct TickGridTests {
    private let second: Int64 = 1_000_000_000

    @Test(arguments: [RecorderValues.framesPerSecond, 60])
    func ticksAreComputedFromTheStartNeverAccumulated(rate: Int) {
        let grid = TickGrid(framesPerSecond: rate)
        #expect(grid.time(ofTick: 0) == 0)
        #expect(grid.time(ofTick: Int64(rate)) == second)
        // Ten hours in, tick k is still exactly k / rate seconds.
        let tenHours = Int64(rate) * 36_000
        #expect(grid.time(ofTick: tenHours) == 36_000 * second)
        #expect(grid.seconds(ofTick: Int64(rate) * 3 / 2) == 1.5)
    }

    @Test(arguments: [RecorderValues.framesPerSecond, 60])
    func aFrameFirstAppearsAtTheFirstTickAtOrAfterItsCapture(rate: Int) {
        let grid = TickGrid(framesPerSecond: rate)
        #expect(grid.firstTick(atOrAfter: -5) == 0)
        #expect(grid.firstTick(atOrAfter: 0) == 0)
        #expect(grid.firstTick(atOrAfter: 1) == 1)
        for tick in Int64(0)..<Int64(3 * rate) {
            let time = grid.time(ofTick: tick)
            #expect(grid.firstTick(atOrAfter: time) == tick)
            #expect(grid.firstTick(atOrAfter: time + 1) == tick + 1)
            #expect(grid.lastTick(atOrBefore: time) == tick)
            #expect(grid.lastTick(atOrBefore: grid.time(ofTick: tick + 1) - 1) == tick)
        }
        #expect(grid.lastTick(atOrBefore: -1) == nil)
    }

    private func loop(rate: Int = RecorderValues.framesPerSecond, bound: Int? = nil) -> TickLoop<String> {
        TickLoop(grid: TickGrid(framesPerSecond: rate), lateTickBound: bound ?? 2 * rate)
    }

    @Test func eachTickWritesTheNewestFrameCapturedAtOrBeforeIt() {
        var ticks = loop()
        let grid = ticks.grid
        var written: [(Int64, String)] = []
        ticks.receive("a", capturedAt: grid.time(ofTick: 2) - 10)
        ticks.receive("b", capturedAt: grid.time(ofTick: 2) + 10)
        ticks.receive("c", capturedAt: grid.time(ofTick: 3))
        #expect(ticks.firstTick == 2)
        // Late in waking up: tick 2 still gets "a", never "b", captured after it.
        _ = ticks.advance(to: grid.time(ofTick: 4) + 5) { written.append(($0, $1)); return true }
        #expect(written.map(\.0) == [2, 3, 4])
        #expect(written.map(\.1) == ["a", "c", "c"])
        #expect(ticks.framesRepeatedForLateness == 0)
    }

    @Test func aStillPictureOfAMinuteAndMoreRepeatsItsFrameOnEveryTick() {
        var ticks = loop()
        var written: [Int64] = []
        ticks.receive("still", capturedAt: 0)
        for step in 1...(75 * RecorderValues.framesPerSecond) {
            _ = ticks.advance(to: ticks.grid.time(ofTick: Int64(step))) { tick, frame in
                #expect(frame == "still")
                written.append(tick)
                return true
            }
        }
        #expect(written == Array(0...Int64(75 * RecorderValues.framesPerSecond)))
    }

    @Test func aTickTheWriterCannotTakeIsWrittenLateWithItsOwnFrame() {
        var ticks = loop()
        let grid = ticks.grid
        var written: [(Int64, String)] = []
        ticks.receive("a", capturedAt: 0)
        #expect(ticks.advance(to: grid.time(ofTick: 1)) { _, _ in false } == .running)
        #expect(ticks.waitingTicks == 2)
        ticks.receive("b", capturedAt: grid.time(ofTick: 1) + 1)
        _ = ticks.advance(to: grid.time(ofTick: 2)) { written.append(($0, $1)); return true }
        #expect(written.map(\.0) == [0, 1, 2])
        // Ticks 0 and 1 waited, but carry the frame of their own time.
        #expect(written.map(\.1) == ["a", "a", "b"])
        #expect(ticks.framesRepeatedForLateness == 2)
    }

    /// A video file's writer may fall 6 s behind, also at the file's end;
    /// the guide track wait and the audio drain keep 2 s.
    @Test func aVideoFileMayFallSixSecondsBehind() {
        #expect(RecorderValues.videoFileLateTickSeconds == 6)
        #expect(RecorderValues.lateTickBound == 6 * RecorderValues.framesPerSecond)
        #expect(TickLoop<String>().lateTickBound == 6 * RecorderValues.framesPerSecond)
        #expect(RecorderValues.audioWaitBoundSeconds == 2)
    }

    @Test(arguments: [RecorderValues.framesPerSecond, 60])
    func moreThanTheBoundOfWaitingTicksMeansTheWriterFellBehind(rate: Int) {
        var ticks = loop(rate: rate, bound: RecorderValues.videoFileLateTickSeconds * rate)
        ticks.receive("a", capturedAt: 0)
        let bound = Int64(RecorderValues.videoFileLateTickSeconds * rate)
        // Ticks 0 to bound - 1 wait: exactly the bound.
        #expect(ticks.advance(to: ticks.grid.time(ofTick: bound - 1)) { _, _ in false } == .running)
        #expect(ticks.advance(to: ticks.grid.time(ofTick: bound)) { _, _ in false } == .writerFellBehind)
    }

    @Test func theFirstTickIsNeverBeforeTheCapturesStart() {
        let grid = TickGrid.recording
        var ticks = TickLoop<String>(notBefore: grid.time(ofTick: 10) + 1)
        // A frame stamped before the capture started, as a stream's first frame can be.
        ticks.receive("early", capturedAt: grid.time(ofTick: 3))
        #expect(ticks.firstTick == 11)
        var written: [Int64] = []
        _ = ticks.advance(to: grid.time(ofTick: 12)) { tick, _ in written.append(tick); return true }
        #expect(written == [11, 12])
    }

    @Test func noTickIsWrittenBeforeTheFirstFrame() {
        var ticks = loop()
        var calls = 0
        #expect(ticks.advance(to: 10 * second) { _, _ in calls += 1; return true } == .running)
        #expect(calls == 0)
        #expect(ticks.lastWrittenTick == nil)
    }

    @Test func aFrameOlderThanTheNewestIsIgnored() {
        var ticks = loop()
        var written: [String] = []
        ticks.receive("new", capturedAt: 100)
        ticks.receive("old", capturedAt: 50)
        _ = ticks.advance(to: ticks.grid.time(ofTick: 1)) { written.append($1); return true }
        #expect(written == ["new"])
    }

    @Test func withoutADecisionDelayEachTickIsDecidedAtItsTime() {
        var ticks = loop()
        let grid = ticks.grid
        var written: [(Int64, String)] = []
        ticks.receive("a", capturedAt: 0)
        _ = ticks.advance(to: grid.time(ofTick: 1)) { written.append(($0, $1)); return true }
        // Captured before tick 1, arrived after it was decided.
        ticks.receive("b", capturedAt: grid.time(ofTick: 1) - 1, arrivedAt: grid.time(ofTick: 1) + 5)
        _ = ticks.advance(to: grid.time(ofTick: 2)) { written.append(($0, $1)); return true }
        #expect(written.map(\.1) == ["a", "a", "b"])
        #expect(ticks.framesPlacedLate == 1)
    }

    private let delay = RecorderValues.cameraDecisionDelay.nanoseconds

    @Test func aCameraFrameArrivingWithinTheDecisionDelayIsPlacedOnItsTick() {
        var ticks = TickLoop<String>(decisionDelay: delay)
        let grid = ticks.grid
        var written: [(Int64, String)] = []
        ticks.receive("a", capturedAt: 0)
        // Tick 1 waits: no frame captured after it has arrived and the delay has not passed.
        _ = ticks.advance(to: grid.time(ofTick: 1) + delay - 1) { written.append(($0, $1)); return true }
        #expect(written.map(\.0) == [0])
        ticks.receive("b", capturedAt: grid.time(ofTick: 1) - 1, arrivedAt: grid.time(ofTick: 1) + delay - 1)
        ticks.receive("c", capturedAt: grid.time(ofTick: 2) + 1, arrivedAt: grid.time(ofTick: 1) + delay - 1)
        // "c" was captured after tick 1 and tick 2: both are decided, tick 3 still waits.
        _ = ticks.advance(to: grid.time(ofTick: 3)) { written.append(($0, $1)); return true }
        #expect(written.map(\.0) == [0, 1, 2])
        #expect(written.map(\.1) == ["a", "b", "b"])
        #expect(ticks.framesPlacedLate == 0)
    }

    @Test func aCameraTickIsDecidedOnceTheDecisionDelayHasPassed() {
        var ticks = TickLoop<String>(decisionDelay: delay)
        let grid = ticks.grid
        var written: [Int64] = []
        ticks.receive("a", capturedAt: 0)
        _ = ticks.advance(to: grid.time(ofTick: 2) + delay) { tick, _ in written.append(tick); return true }
        // Ticks 0 to 2 are 0.5 s old and more; the later ones wait.
        #expect(written == [0, 1, 2])
    }

    @Test func aCameraFrameArrivingAfterTheDecisionDelayIsPlacedLateAndCounted() {
        var ticks = TickLoop<String>(decisionDelay: delay)
        let grid = ticks.grid
        var written: [(Int64, String)] = []
        ticks.receive("a", capturedAt: 0)
        _ = ticks.advance(to: grid.time(ofTick: 1) + delay) { written.append(($0, $1)); return true }
        let late = grid.time(ofTick: 1) - 1
        ticks.receive("b", capturedAt: late, arrivedAt: late + delay + 300_000_000)
        _ = ticks.advance(to: grid.time(ofTick: 2) + delay) { written.append(($0, $1)); return true }
        #expect(written.map(\.1) == ["a", "a", "b"])
        #expect(ticks.framesPlacedLate == 1)
        #expect(ticks.largestLateArrival == delay + 300_000_000)
    }

    @Test func atTheFilesEndEveryDueTickIsDecided() {
        var ticks = TickLoop<String>(decisionDelay: delay)
        var written: [Int64] = []
        ticks.receive("a", capturedAt: 0)
        _ = ticks.advance(to: ticks.grid.time(ofTick: 3), waitingForLateFrames: false) { tick, _ in written.append(tick); return true }
        #expect(written == [0, 1, 2, 3])
    }

    @Test func drainingWritesTheWaitingTicksInOrder() {
        var ticks = loop()
        ticks.receive("a", capturedAt: 0)
        _ = ticks.advance(to: ticks.grid.time(ofTick: 3)) { _, _ in false }
        var written: [Int64] = []
        #expect(ticks.drain { tick, _ in written.append(tick); return true } == 0)
        #expect(written == [0, 1, 2, 3])
        #expect(ticks.lastWrittenTick == 3)
        #expect(ticks.framesRepeatedForLateness == 4)
    }
}

@Suite struct SharedClockTests {
    @Test func aFramesHostTimeIsPlacedOnTheSharedClock() {
        let clock = SharedClock(reading: ClockReading(continuous: 5_000, host: 3_000))
        #expect(clock.sinceStart(continuous: 5_000) == 0)
        #expect(clock.sinceStart(continuous: 8_000) == 3_000)
        #expect(clock.sinceStart(host: 3_000) == 0)
        #expect(clock.sinceStart(host: 4_000) == 1_000)
    }

    @Test func afterASleepTheHostClockIsReadAgain() {
        var clock = SharedClock(reading: ClockReading(continuous: 5_000, host: 3_000))
        // A sleep of 60 s: the continuous clock went on, the host clock did not.
        let sleep: UInt64 = 60_000_000_000
        clock.reread(ClockReading(continuous: 10_000 + sleep, host: 8_000))
        #expect(clock.sinceStart(host: 8_000) == Int64(5_000 + sleep))
        #expect(clock.sinceStart(continuous: 10_000 + sleep) == Int64(5_000 + sleep))
    }
}

@Suite struct TimecodeTests {
    private let berlin = TimeZone(identifier: "Europe/Berlin")!

    private func date(_ text: String) throws -> Date {
        try Date(text, strategy: .iso8601.year().month().day().time(includingFractionalSeconds: true).timeZone(separator: .omitted))
    }

    @Test func theExampleOfTheManifest() throws {
        // recorder.md: started 14:03:05.120, timecode 14:03:05:04.
        let timecode = Timecode(start: try date("2026-11-12T13:03:05.120Z"), timeZone: berlin)
        #expect(timecode.text(ofTick: 0) == "14:03:05:04")
        // 1476 s later, 14:27:41:04 (the screen file that came back).
        #expect(timecode.text(ofTick: 1476 * Int64(RecorderValues.framesPerSecond)) == "14:27:41:04")
    }

    @Test(arguments: [RecorderValues.framesPerSecond, 60])
    func framesCountAtTheGridsRate(rate: Int) throws {
        let timecode = Timecode(start: try date("2026-11-12T13:03:05.000Z"), timeZone: berlin, framesPerSecond: rate)
        #expect(timecode.text(ofTick: 0) == "14:03:05:00")
        #expect(timecode.text(ofTick: Int64(rate - 1)) == "14:03:05:\(rate - 1)")
        #expect(timecode.text(ofTick: Int64(rate)) == "14:03:06:00")
        #expect(timecode.frame(ofTick: 1) == timecode.frame(ofTick: 0) + 1)
    }

    /// 2026-10-25 in Berlin: 03:00 CEST becomes 02:00 CET, so the day has 25 hours.
    @Test func onTheDaylightSavingChangeTheTimecodeIsTheClockTime() throws {
        let timecode = Timecode(start: try date("2026-10-25T10:00:00.000Z"), timeZone: berlin)
        #expect(timecode.text(ofTick: 0) == "11:00:00:00")
        let spring = Timecode(start: try date("2026-03-29T10:00:00.000Z"), timeZone: berlin)
        #expect(spring.text(ofTick: 0) == "12:00:00:00")
    }

    @Test func midnightStartsOver() throws {
        let rate = RecorderValues.framesPerSecond
        let timecode = Timecode(start: try date("2026-11-12T22:59:59.000Z"), timeZone: berlin)
        #expect(timecode.text(ofTick: Int64(rate)) == "00:00:00:00")
        #expect(timecode.frame(ofTick: Int64(rate)) == 0)
    }
}
