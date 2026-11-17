import Foundation
import Testing
@testable import RecorderLogic

/// The tracker against simulated devices, the correction applied exactly
/// at the rate it gives and at a gap grown by the drift during it: what
/// matters is the correction against the device's true offset since the
/// start. The bounds are the design's simulation's worst over 20 seeds
/// plus a margin, checked against this simulation, whose buffers arrive
/// in order. The full matrix (seeds 1 to 10, 30 minutes for every steady
/// device and burst pattern) was run once on 2026-11-17; here seeds 1 to
/// 3 and one seed for the two 30-minute runs, to keep the suite fast.
@Suite struct ClockDriftTrackerTests {
    struct Run {
        /// Per buffer: its timestamp in seconds, the correction applied
        /// against the device's true offset, the rate, and the drift shown.
        var seconds: [Double] = []
        var error: [Double] = []
        var rate: [Double] = []
        var drift: [Double?] = []

        func worstError(from start: Double, to end: Double = .infinity) -> Double {
            zip(seconds, error).filter { $0.0 >= start && $0.0 < end }.map { abs($0.1) }.max() ?? 0
        }

        var largestRate: Double { rate.map(abs).max() ?? 0 }

        func largestRate(from start: Double) -> Double {
            zip(seconds, rate).filter { $0.0 >= start }.map { abs($0.1) }.max() ?? 0
        }

        /// How far the clock drift shown is from `ppm` at the worst from
        /// `start` on; infinity if it is not shown.
        func shownOff(_ ppm: Double, from start: Double) -> Double {
            zip(seconds, drift).filter { $0.0 >= start }.map { abs(($0.1 ?? .infinity) - ppm) }.max() ?? 0
        }
    }

    /// The device through a tracker; `corrected: false` applies nothing,
    /// the error then being the device's own offset.
    private func run(_ device: SimulatedDevice, seconds: Double, seed: Int = 1, corrected: Bool = true) -> Run {
        var tracker = ClockDriftTracker()
        var applied = 0.0
        var run = Run()
        let bufferSeconds = Double(device.bufferSamples) / Double(SimulatedDevice.sampleRate)
        let bufferLength = Int64(bufferSeconds * 1e9)
        let start = device.offset(0)
        var next: Int64?
        for buffer in device.buffers(for: seconds, seed: UInt64(seed)) {
            // A gap, as `ClockDriftCorrection` finds it: the drift during it is added.
            if corrected, let next, buffer.time - next > RecorderValues.audioGapTolerance.nanoseconds {
                applied += tracker.drift(over: buffer.time - next)
            }
            next = buffer.time + bufferLength
            tracker.record(time: buffer.time, arrival: buffer.arrival, applied: applied)
            if corrected { applied += tracker.rate * bufferSeconds }
            run.seconds.append(buffer.seconds)
            run.error.append(device.offset(buffer.seconds) - start - applied)
            run.rate.append(tracker.rate)
            run.drift.append(tracker.clockDriftPpm)
        }
        return run
    }

    private func ms(_ seconds: Double) -> String { String(format: "%.3f ms", seconds * 1000) }

    @Test func theValuesAreTheDesignsStartingPoints() {
        #expect(RecorderValues.clockDriftInterval == .seconds(1))
        #expect(RecorderValues.clockDriftHorizon == .seconds(20))
        #expect(RecorderValues.clockDriftEstimateMinimumPoints == 5)
        #expect(RecorderValues.clockDriftEstimateMinimumSpan == .seconds(10))
        #expect(RecorderValues.clockDriftCatchUpTime == .seconds(10))
        #expect(RecorderValues.clockDriftMaximumRatePpm == 1000)
        #expect(RecorderValues.clockDriftShownEstimates == 60)
        #expect(RecorderValues.clockDriftShownMinimumEstimates == 10)
    }

    // MARK: Steady devices

    @Test(arguments: [-116.0, 50, 0], 1...3)
    func aSteadyDeviceIsFollowed(ppm: Double, seed: Int) {
        let run = run(.steady(ppm: ppm), seconds: 180, seed: seed)
        #expect(run.worstError(from: 30) < 0.0005, "\(ms(run.worstError(from: 30)))")
        #expect(run.shownOff(ppm, from: 60) < 5, "\(run.shownOff(ppm, from: 60)) ppm off from 60 s")
        #expect(run.shownOff(ppm, from: 120) < 3, "\(run.shownOff(ppm, from: 120)) ppm off from 120 s")
    }

    @Test func aSteadyDeviceIsFollowedForHalfAnHour() {
        let run = run(.steady(ppm: -116), seconds: 1800)
        #expect(run.worstError(from: 30) < 0.0005, "\(ms(run.worstError(from: 30)))")
    }

    // MARK: Late, sparse and missing buffers

    private func stall(seconds: Double) -> SimulatedDevice {
        var device = SimulatedDevice.steady(ppm: -116)
        device.extraLateness = { captured, random in
            (100..<(100 + seconds)).contains(captured) ? Double.random(in: 0.5...4, using: &random) : 0
        }
        return device
    }

    /// For 4 s every buffer arrives 0.5 to 4 s late, and those queued
    /// behind them too: those points lie far above the line and do not move it.
    @Test(arguments: 1...3)
    func aShortStallLiesAboveTheLine(seed: Int) {
        let run = run(stall(seconds: 4), seconds: 200, seed: seed)
        #expect(run.worstError(from: 30) < 0.0006, "\(ms(run.worstError(from: 30)))")
    }

    /// A known limit: a late stretch filling about half the horizon or
    /// more (9 s of stall and the queue behind it, until about 113 s)
    /// tilts the line until it leaves the horizon.
    @Test(arguments: 1...3)
    func aLongStallTiltsTheLineUntilItLeavesTheHorizon(seed: Int) {
        let run = run(stall(seconds: 9), seconds: 200, seed: seed)
        #expect(run.worstError(from: 30) < 0.008, "\(ms(run.worstError(from: 30)))")
        #expect(run.worstError(from: 153) < 0.0006, "\(ms(run.worstError(from: 153)))")
    }

    /// No buffers for a while, then on after a gap: the correction grows
    /// by the drift during it and goes on from the points it has.
    @Test(arguments: [(5.0, 48.6), (20, 0), (20, 48.6), (60, -116)], 1...3)
    func aPauseIsCaughtUp(pause: (seconds: Double, ppm: Double), seed: Int) {
        var device = SimulatedDevice.steady(ppm: pause.ppm)
        device.paused = { (100..<(100 + pause.seconds)).contains($0) }
        let run = run(device, seconds: 250, seed: seed)
        let worst = run.worstError(from: 100 + pause.seconds)
        #expect(worst < 0.0006, "\(ms(worst))")
    }

    /// The buffers are delivered in 1 s of every 2 s, those of the other
    /// second held back to the next.
    @Test(arguments: 1...3)
    func deliveryEveryOtherSecondIsFollowed(seed: Int) {
        var device = SimulatedDevice.steady(ppm: 0)
        device.delivered = { arrival in Int(arrival) % 2 == 1 ? arrival.rounded(.down) + 1 : arrival }
        let run = run(device, seconds: 300, seed: seed)
        #expect(run.worstError(from: 30) < 0.0003, "\(ms(run.worstError(from: 30)))")
        #expect(run.largestRate(from: 30) <= 100e-6, "\(run.largestRate(from: 30) * 1e6) ppm")
    }

    // MARK: Bursts

    /// A source delivering in bursts like the system audio: buffers of 960
    /// samples, no clock drift, each second's smallest lateness raised by
    /// the pattern.
    private func burst(_ pattern: [Double]) -> SimulatedDevice {
        var device = SimulatedDevice.steady(ppm: 0)
        device.bufferSamples = 960
        device.extraLateness = { captured, _ in pattern[Int(captured) % pattern.count] }
        return device
    }

    private static let measuredBursts = [0, 0.0027, 0.0056, 0.0015]

    @Test(arguments: [1.0, 2], 1...3)
    func aSourceDeliveringInBurstsIsHardlyCorrected(depth: Double, seed: Int) {
        let run = run(burst(Self.measuredBursts.map { $0 * depth }), seconds: 300, seed: seed)
        #expect(run.worstError(from: 30) < 0.0005, "\(ms(run.worstError(from: 30)))")
        #expect(run.largestRate(from: 30) <= 200e-6, "\(run.largestRate(from: 30) * 1e6) ppm")
    }

    @Test func aSourceDeliveringInBurstsIsHardlyCorrectedForHalfAnHour() {
        let run = run(burst(Self.measuredBursts), seconds: 1800)
        #expect(run.worstError(from: 30) < 0.0005, "\(ms(run.worstError(from: 30)))")
        #expect(run.largestRate(from: 30) <= 200e-6, "\(run.largestRate(from: 30) * 1e6) ppm")
    }

    @Test(arguments: 1...3)
    func aSourceAtItsLowestOnlyOnceInEightSeconds(seed: Int) {
        let run = run(burst([0, 0.003, 0.005, 0.004, 0.002, 0.005, 0.003, 0.004]), seconds: 300, seed: seed)
        #expect(run.worstError(from: 30) < 0.0008, "\(ms(run.worstError(from: 30)))")
    }

    // MARK: Large buffers

    /// Buffers of 8192 or 16384 samples, about 6 or 3 a second: an
    /// interval's smallest lateness scatters more.
    @Test(arguments: [(8192, 0.0012), (16384, 0.0025)], 1...3)
    func largeBuffersAreFollowed(buffer: (samples: Int, bound: Double), seed: Int) {
        var device = SimulatedDevice.steady(ppm: -116)
        device.bufferSamples = buffer.samples
        let run = run(device, seconds: 300, seed: seed)
        #expect(run.worstError(from: 30) < buffer.bound, "\(ms(run.worstError(from: 30)))")
    }

    // MARK: Steps and glitches

    /// The device's lateness steps by `size` for good at 100 s: up, it is
    /// followed once the points before the step leave the horizon; down,
    /// at once; at most at the largest rate.
    @Test(arguments: [0.004, -0.004, -0.010, 0.050], 1...3)
    func aLastingStepIsFollowed(size: Double, seed: Int) {
        let device = SimulatedDevice(offset: { seconds in 50e-6 * seconds + (seconds >= 100 ? size : 0) })
        let run = run(device, seconds: 300, seed: seed)
        #expect(run.worstError(from: 250) < 0.0005, "\(ms(run.worstError(from: 250)))")
        #expect(run.largestRate <= 0.001)
    }

    /// A known limit: one buffer told to have arrived 20 ms early pulls the
    /// line down for the horizon.
    @Test(arguments: 1...3)
    func oneEarlyBufferPullsTheLineDownForTheHorizon(seed: Int) {
        var device = SimulatedDevice.steady(ppm: -116)
        let index = 100 * SimulatedDevice.sampleRate / device.bufferSamples
        device.early = { $0 == index ? 0.020 : 0 }
        let run = run(device, seconds: 250, seed: seed)
        #expect(run.worstError(from: 30) < 0.014, "\(ms(run.worstError(from: 30)))")
        #expect(run.worstError(from: 160) < 0.0005, "\(ms(run.worstError(from: 160)))")
    }

    // MARK: Wander

    /// A wander of ±5 ms over 300 s is followed: closer corrected than not.
    @Test(arguments: 1...3)
    func aSlowWanderIsFollowed(seed: Int) {
        let device = SimulatedDevice.triangle(amplitude: 0.005, period: 300)
        let corrected = run(device, seconds: 600, seed: seed).worstError(from: 30)
        let uncorrected = run(device, seconds: 600, seed: seed, corrected: false).worstError(from: 30)
        #expect(corrected < 0.002, "\(ms(corrected))")
        #expect(corrected < uncorrected, "\(ms(corrected)) against \(ms(uncorrected))")
    }

    /// A fast wander is not followed, and comes out worse corrected than
    /// not: ±0.5 ms in triangles of 12, 25 and 40 s (as the Logitech BRIO
    /// does), and a rate alternating between +100 and −100 ppm every 12 s.
    /// This bounds how much worse it gets; it is no claim that it is followed.
    @Test(arguments: [12.0, 25, 40, 0], 1...3)
    func aFastWanderGetsAtMostTwoMillisecondsOff(period: Double, seed: Int) {
        let device = period == 0 ? SimulatedDevice(offset: { seconds in
            let half = Int(seconds / 12)
            let into = seconds - Double(half) * 12
            return (half % 2 == 0 ? 0 : 12 * 100e-6) + (half % 2 == 0 ? 100e-6 : -100e-6) * into
        }) : .triangle(amplitude: 0.0005, period: period)
        let run = run(device, seconds: 300, seed: seed)
        #expect(run.worstError(from: 30) < 0.002, "\(ms(run.worstError(from: 30)))")
    }

    // MARK: The tracker's steps

    /// A tracker whose intervals start on whole seconds: its first buffer,
    /// at 0, is interval 0's only one.
    private func tracker() -> ClockDriftTracker {
        var tracker = ClockDriftTracker()
        tracker.record(time: 0, arrival: 0, applied: 0)
        return tracker
    }

    /// A buffer `lateness` late in the interval `index`, 0.5 s into it; the
    /// interval before ends with it.
    private func interval(_ tracker: inout ClockDriftTracker, _ index: Int64, lateness: Double, applied: Double = 0) {
        let time = index * 1_000_000_000 + 500_000_000
        tracker.record(time: time, arrival: time + Int64((lateness * 1e9).rounded()), applied: applied)
    }

    @Test func noEstimateUntilFivePointsSpanTenSeconds() {
        var tracker = tracker()
        for index in 1...10 { interval(&tracker, Int64(index), lateness: 0.001 + 0.0001 * Double(index)) }
        // Points of intervals 0 to 9: 0 s to 9.5 s, too short a span.
        #expect(tracker.target == nil)
        #expect(tracker.rate == 0)
        interval(&tracker, 11, lateness: 0.0021)
        // Interval 10's point, at 10.5 s, spans 10.5 s with interval 0's at 0 s.
        #expect(tracker.target != nil)
        #expect(tracker.remaining == tracker.target)
    }

    @Test func theRateIsTheSlopePlusWhatIsOffOverTheCatchUpTime() throws {
        var tracker = tracker()
        // Points rising 0.1 ms a second from interval 1 on (interval 0's at 0 s is lower still).
        for index in 1...12 { interval(&tracker, Int64(index), lateness: 0.0001 * Double(index), applied: 0.0002) }
        let target = try #require(tracker.target)
        // Each point arrives 0.1 ms later than the one before, so 1.0001 s after it.
        let slope = (tracker.rate - (target - 0.0002) / 10)
        #expect(abs(slope - 0.0001 / 1.0001) < 1e-12, "\(slope * 1e6) ppm")
        #expect(abs(try #require(tracker.remaining) - (target - 0.0002)) < 1e-12)
    }

    @Test func intervalsWithoutBuffersLeaveTheRateAtTheLastSlope() throws {
        var tracker = tracker()
        for index in 1...12 { interval(&tracker, Int64(index), lateness: 0.0001 * Double(index), applied: 0.0005) }
        #expect(abs(tracker.rate - 0.0001 / 1.0001) > 1e-6)
        // Intervals 13 and 14 have no buffer.
        interval(&tracker, 15, lateness: 0.0015, applied: 0.0005)
        #expect(abs(tracker.rate - 0.0001 / 1.0001) < 1e-12)
    }

    // MARK: The support line

    private func line(_ points: [(Double, Double)], maximum: Double = 0.001) -> ClockDriftTracker.Line {
        ClockDriftTracker.supportLine(points.map { (time: $0.0, lateness: $0.1) }, maximumSlope: maximum)
    }

    @Test func theSupportLineRunsThroughTheTwoLowestPoints() {
        // Points on a line rising 0.1 ms a second, all but two raised.
        let line = line([(0, 0.0010), (1, 0.0013), (2, 0.0012), (3, 0.0015), (4, 0.0014)])
        #expect(abs(line.slope - 0.0001) < 1e-12)
        #expect(abs(line.value(at: 0) - 0.0010) < 1e-12)
        #expect(abs(line.value(at: 2) - 0.0012) < 1e-12)
    }

    @Test func aPointAboveTheLineDoesNotMoveIt() {
        let points: [(Double, Double)] = [(0, 0.001), (1, 0.001), (2, 0.001), (3, 0.001)]
        let flat = line(points)
        let withStall = line(points + [(1.5, 3.0)])
        #expect(flat.slope == 0 && withStall.slope == 0)
        #expect(flat.value(at: 1) == withStall.value(at: 1))
    }

    @Test func theSupportLineIsNoSteeperThanTheLimit() {
        // Points 10 ms apart in 1 s: 10000 ppm, held at 1000 ppm, under both.
        let line = line([(0, 0.0), (1, 0.010)])
        #expect(line.slope == 0.001)
        #expect(line.value(at: 0) <= 0 && line.value(at: 1) <= 0.010)
        #expect(abs(line.value(at: 0)) < 1e-12)
    }

    @Test func aSupportLineThroughOnePoint() {
        let line = line([(5, 0.002)])
        #expect(abs(line.value(at: 5) - 0.002) < 1e-12)
        #expect(abs(line.slope) <= 0.001)
    }
}
