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
/// Serialized: these tests compute for seconds without suspending, so run in
/// parallel they hold every thread of the cooperative pool (3 on a CI
/// runner) and the async tests waiting for a 20 ms task starve until their
/// own timeouts; serialized, a suite holds one thread.
@Suite(.serialized) struct ClockDriftTrackerTests {
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
                applied += tracker.driftAcrossGap(of: buffer.time - next, arrival: buffer.arrival, applied: applied)
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

    /// A known limit: late points that outweigh the others in the horizon
    /// (9 s of stall and the queue behind it, until about 113 s) tilt the
    /// line until they leave the horizon.
    @Test(arguments: 1...3)
    func aLongStallTiltsTheLineUntilItLeavesTheHorizon(seed: Int) {
        let run = run(stall(seconds: 9), seconds: 200, seed: seed)
        #expect(run.worstError(from: 30) < 0.008, "\(ms(run.worstError(from: 30)))")
        #expect(run.worstError(from: 153) < 0.0006, "\(ms(run.worstError(from: 153)))")
    }

    /// A 9 s stall tilts the line, then 30 s with no buffers end in a gap:
    /// the tilted estimates are under half of the kept ones, so the drift
    /// added across the gap is their median's, the device's; what the tilt
    /// put off before the gap is still off after it and caught up.
    @Test(arguments: 1...3)
    func aGapAfterATiltedLineAddsTheKeptSlope(seed: Int) {
        var device = stall(seconds: 9)
        device.paused = { (109..<139).contains($0) }
        let run = run(device, seconds: 250, seed: seed)
        #expect(run.worstError(from: 139) < 0.0035, "\(ms(run.worstError(from: 139)))")
        #expect(run.worstError(from: 169) < 0.002, "\(ms(run.worstError(from: 169)))")
    }

    /// An hour with no buffers on a steady device: the drift across it is
    /// the kept slope's over the hour.
    @Test func anHourWithoutBuffersIsBridged() {
        var device = SimulatedDevice.steady(ppm: -116)
        device.paused = { (100..<3700).contains($0) }
        let run = run(device, seconds: 3800)
        #expect(run.worstError(from: 3700) < 0.0013, "\(ms(run.worstError(from: 3700)))")
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

    /// The buffers are delivered from 0.05 s to 1 s of every 2 s, the
    /// others held back to the next delivery (0.05 s, or 0.1 s after the
    /// odd second), so the intervals, which start at the first arrival at
    /// 0.05 s, are empty every other second: the catch-up after each
    /// estimate still holds.
    @Test(arguments: [0.0, -116], 1...3)
    func deliveryEveryOtherSecondIsFollowed(ppm: Double, seed: Int) {
        var device = SimulatedDevice.steady(ppm: ppm)
        device.delivered = { arrival in
            let into = arrival.truncatingRemainder(dividingBy: 2)
            return into >= 1 ? arrival - into + 2.1 : into < 0.05 ? arrival - into + 0.05 : arrival
        }
        let run = run(device, seconds: 300, seed: seed)
        let bound = ppm == 0 ? 0.0003 : 0.0006
        #expect(run.worstError(from: 30) < bound, "\(ms(run.worstError(from: 30)))")
        let swing = zip(run.seconds, run.rate).filter { $0.0 >= 30 }.map { abs($0.1 + ppm * 1e-6) }.max() ?? 0
        #expect(swing <= 100e-6, "\(swing * 1e6) ppm off the drift")
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

    private func rotated(_ pattern: [Double], by rotation: Int) -> [Double] {
        Array(pattern[rotation...] + pattern[..<rotation])
    }

    /// The measured pattern, wherever its lowest second falls when the
    /// first estimate takes the reference.
    @Test(arguments: 0..<4)
    func theMeasuredBurstsInEveryPhase(rotation: Int) {
        let run = run(burst(rotated(Self.measuredBursts, by: rotation)), seconds: 300)
        #expect(run.worstError(from: 30) < 0.0005, "\(ms(run.worstError(from: 30)))")
    }

    /// A known limit: the reference comes from the first estimate's points
    /// and is never revised, so a source at its lowest only once in 8 s
    /// can start off by up to about 3.4 ms for good, depending on where
    /// the lowest second falls; in three of the eight phases it does not.
    @Test(arguments: 0..<8, 1...3)
    func aSourceAtItsLowestOnlyOnceInEightSeconds(rotation: Int, seed: Int) {
        let run = run(burst(rotated([0, 0.003, 0.005, 0.004, 0.002, 0.005, 0.003, 0.004], by: rotation)), seconds: 300, seed: seed)
        let bound = [0, 6, 7].contains(rotation) ? 0.0008 : 0.004
        #expect(run.worstError(from: 30) < bound, "\(ms(run.worstError(from: 30)))")
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

    @Test func noEstimateFromFourPointsSpanningTenSeconds() {
        var tracker = tracker()
        // Points of intervals 0, 4, 8 and 12: four, spanning 12.5 s.
        for index in [4, 8, 12, 16] { interval(&tracker, Int64(index), lateness: 0.001) }
        #expect(tracker.target == nil)
        // Interval 16's point is the fifth.
        interval(&tracker, 17, lateness: 0.001)
        #expect(tracker.target != nil)
    }

    /// Points on a line rising 0.1 ms a second, the first at the first
    /// arrival: the target is the line at the interval's end, not at its
    /// point and not at the buffer that ended it.
    @Test func theTargetIsTheLineAtTheIntervalsEnd() throws {
        var tracker = ClockDriftTracker()
        for index in 0...12 {
            let time = Int64(index) * 1_000_000_000 + 500_000_000
            tracker.record(time: time, arrival: time + Int64(index) * 100_000, applied: 0)
        }
        // Interval 11 ended at 12 s from the first arrival; each point
        // arrives 1.0001 s after the one before.
        let slope = 0.0001 / 1.0001
        #expect(abs(try #require(tracker.target) - slope * 12) < 1e-12)
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

    /// Without a fresh estimate the rate holds the catch-up for the
    /// catch-up time since the latest estimate, then is the kept slope.
    @Test func withoutAFreshEstimateTheRateHoldsThenIsTheKeptSlope() throws {
        var tracker = tracker()
        let slope = 0.0001 / 1.0001
        for index in 1...12 { interval(&tracker, Int64(index), lateness: 0.0001 * Double(index), applied: 0.0005) }
        // Intervals 13 to 19 have no buffer; interval 12's estimate, at 13 s, is 7.5 s old.
        interval(&tracker, 20, lateness: 0.0020, applied: 0.0005)
        let held = tracker.rate
        #expect(abs(held - slope) > 1e-6)
        // Nothing until 32.5 s: interval 20's estimate, at 21 s, is 11.5 s old.
        interval(&tracker, 32, lateness: 0.0032, applied: 0.0005)
        #expect(abs(tracker.rate - slope) < 1e-12)
    }

    /// At a gap the interval before it is closed first, against the
    /// correction before the jump; the drift during the gap is the kept
    /// slope's (the median of the latest estimates', not the latest), the
    /// rate becomes the kept slope, and what was still off stays off.
    @Test func aGapClosesTheIntervalThenAddsTheKeptSlopesDrift() throws {
        var tracker = tracker()
        #expect(tracker.driftAcrossGap(of: 1_000_000_000, arrival: 500_000_000, applied: 0) == 0)
        // Points rising 0.1 ms a second: 16 estimates of this slope.
        for index in 1...25 { interval(&tracker, Int64(index), lateness: 0.0001 * Double(index), applied: 0.0005) }
        let slope = 0.0001 / 1.0001
        // A lower point: the next estimates' slopes are others.
        interval(&tracker, 26, lateness: 0.0020, applied: 0.0005)
        let targetBefore = try #require(tracker.target)
        // No buffers from 26.5 s; the first after the gap arrives at 30.5 s.
        let arrival: Int64 = 30_500_000_000 + 3_000_000
        let drift = tracker.driftAcrossGap(of: 4_000_000_000, arrival: arrival, applied: 0.0007)
        let target = try #require(tracker.target)
        #expect(target != targetBefore)
        #expect(try #require(tracker.remaining) == target - 0.0007)
        #expect(abs(drift - 4 * slope) < 1e-12, "\(drift * 1e6) µs")
        #expect(abs(tracker.rate - slope) < 1e-12, "\(tracker.rate * 1e6) ppm")
        tracker.record(time: 30_500_000_000, arrival: arrival, applied: 0.0007 + drift)
        #expect(try #require(tracker.remaining) == target - 0.0007)
        #expect(abs(tracker.rate - slope) < 1e-12, "\(tracker.rate * 1e6) ppm")
    }

    /// The kept slope, shown as the clock drift, is the median of the
    /// latest `shownEstimates` estimates' slopes: the middle one of an odd
    /// count, the mean of the two middle ones of an even count. A horizon
    /// of 2 s holds two points, so each estimate's slope is the one between
    /// them.
    @Test func theKeptSlopeIsTheMedianOfTheLatestSlopes() throws {
        var tracker = ClockDriftTracker(
            horizon: .seconds(2), minimumPoints: 2, minimumSpan: .milliseconds(500), shownEstimates: 4, shownMinimum: 1)
        tracker.record(time: 0, arrival: 0, applied: 0)
        // One point per second, the slope from one to the next `ppm`.
        var latenesses = [0.010]
        for ppm in [400.0, -100, 100, 300, -300] { latenesses.append(latenesses.last! + ppm * 1e-6 / (1 - ppm * 1e-6)) }
        var shown: [Double] = []
        for (index, lateness) in latenesses.enumerated() {
            interval(&tracker, Int64(index + 1), lateness: lateness)
            // From interval 3's first buffer on, each closes an interval with a new estimate.
            if index >= 2 { shown.append(try #require(tracker.clockDriftPpm)) }
        }
        interval(&tracker, Int64(latenesses.count + 1), lateness: 0.020)
        shown.append(try #require(tracker.clockDriftPpm))
        // Medians of 400; 400, -100; then 100; 200; and of the latest four, 0.
        let expected = [-400.0, -150, -100, -200, 0]
        #expect(shown.count == expected.count)
        for (value, want) in zip(shown, expected) { #expect(abs(value - want) < 0.01, "\(shown)") }
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

    /// Three points in a V: every slope between the two sides lies equally
    /// far from them in sum; the one nearer 0 is taken.
    @Test func onATieTheSlopeNearerZeroIsTaken() {
        let line = line([(0, 0.001), (1, 0), (2, 0.001)], maximum: 0.002)
        #expect(line.slope == 0)
        #expect(abs(line.value(at: 1)) < 1e-15)
    }

    @Test func aSupportLineThroughOnePoint() {
        let line = line([(5, 0.002)])
        #expect(abs(line.value(at: 5) - 0.002) < 1e-12)
        #expect(abs(line.slope) <= 0.001)
    }
}
