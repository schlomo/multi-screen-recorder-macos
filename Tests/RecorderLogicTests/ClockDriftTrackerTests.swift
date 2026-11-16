import Testing
@testable import RecorderLogic

/// The tracker against simulated devices, the correction applied exactly
/// at the rate it gives: what matters is the correction against the
/// device's true offset.
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

        /// The largest error of one sign: positive, the correction fell
        /// short of the offset or went below it after a step down.
        func largestError(from start: Double, sign: Double) -> Double {
            zip(seconds, error).filter { $0.0 >= start }.map { $0.1 * sign }.max() ?? 0
        }

        func rate(at seconds: Double) -> Double { rate[self.seconds.firstIndex { $0 >= seconds }!] }
    }

    /// The device through a tracker; `corrected: false` applies nothing,
    /// the error then being the device's own wander.
    private func run(_ device: SimulatedDevice, seconds: Double, seed: UInt64 = 1, corrected: Bool = true) -> Run {
        var tracker = ClockDriftTracker()
        var applied = 0.0
        var run = Run()
        let bufferSeconds = Double(device.bufferSamples) / Double(SimulatedDevice.sampleRate)
        for buffer in device.buffers(for: seconds, seed: seed) {
            tracker.record(time: buffer.time, arrival: buffer.arrival, applied: applied)
            if corrected { applied += tracker.rate * bufferSeconds }
            run.seconds.append(buffer.seconds)
            run.error.append(device.offset(buffer.seconds) - applied)
            run.rate.append(tracker.rate)
            run.drift.append(tracker.clockDriftPpm)
        }
        return run
    }

    @Test func theValuesAreTheDesignsStartingPoints() {
        #expect(RecorderValues.clockDriftInterval == .seconds(1))
        #expect(RecorderValues.clockDriftIntervalMinimumBuffers == 3)
        #expect(RecorderValues.clockDriftRollingIntervals == 5)
        #expect(RecorderValues.clockDriftLoopFrequency == 0.3)
        #expect(RecorderValues.clockDriftShownFitMeasurements == 60)
        #expect(RecorderValues.clockDriftShownMinimumMeasurements == 10)
        #expect(RecorderValues.clockDriftShownSettlingMeasurements == 10)
        #expect(RecorderValues.clockDriftMaximumRatePpm == 1000)
        #expect(RecorderValues.clockDriftStep == .milliseconds(5))
        #expect(RecorderValues.clockDriftRejectedIntervalsInARow == 10)
    }

    /// The error includes the device's offset when the reference was
    /// taken, which no correction can know: up to about 0.25 ms here.
    @Test(arguments: [-116.0, 50.0], [UInt64(1), 2, 3])
    func aSteadyDeviceIsFollowed(ppm: Double, seed: UInt64) throws {
        let run = run(.steady(ppm: ppm), seconds: 150, seed: seed)
        #expect(run.worstError(from: 15) < 0.0005, "\(run.worstError(from: 15) * 1000) ms")
        #expect(run.worstError(from: 60) < 0.00035, "\(run.worstError(from: 60) * 1000) ms")
        #expect(run.rate.allSatisfy { abs($0) <= 0.001 })
        let shown = zip(run.seconds, run.drift)
        // The reference after 5 intervals, 10 left out, 10 fitted.
        #expect(shown.filter { $0.0 < 20 }.allSatisfy { $0.1 == nil })
        let off45 = shown.filter { $0.0 >= 45 }.map { abs(($0.1 ?? .infinity) - ppm) }.max()!
        let off120 = shown.filter { $0.0 >= 120 }.map { abs(($0.1 ?? .infinity) - ppm) }.max()!
        #expect(off45 < 5, "\(off45) ppm off from 45 s")
        #expect(off120 < 2, "\(off120) ppm off from 120 s")
    }

    /// A device whose rate alternates between +100 and −100 ppm every 12 s:
    /// corrected, it is closer than uncorrected.
    @Test func anAlternatingDeviceIsCloserCorrectedThanNot() {
        let device = SimulatedDevice(offset: { seconds in
            let half = Int(seconds / 12)
            let into = seconds - Double(half) * 12
            return (half % 2 == 0 ? 0 : 12 * 100e-6) + (half % 2 == 0 ? 100e-6 : -100e-6) * into
        })
        let corrected = run(device, seconds: 180).worstError(from: 60)
        let uncorrected = run(device, seconds: 180, corrected: false).worstError(from: 60)
        #expect(corrected < uncorrected, "\(corrected * 1000) ms against \(uncorrected * 1000) ms")
        #expect(corrected < 0.0012, "\(corrected * 1000) ms")
    }

    /// Devices wandering ±0.5 ms in triangles of 25, 40 and 60 s, as the
    /// Logitech BRIO does: the rolling minimum flattens a fast wander's
    /// peaks, but the loop does not amplify it.
    @Test(arguments: [(25.0, 0.001), (40, 0.0007), (60, 0.0007)])
    func aWanderingDeviceStaysWithinAMillisecond(period: Double, bound: Double) {
        let corrected = run(.triangle(amplitude: 0.0005, period: period), seconds: 180).worstError(from: 60)
        #expect(corrected < bound, "\(corrected * 1000) ms")
    }

    /// The system audio: buffers of 960 samples, no clock drift, but
    /// delivered in bursts, so each second's smallest lateness follows a
    /// sawtooth of 0, 2.7, 5.6 and 1.5 ms. The rolling minimum finds the
    /// lowest; the correction stays within 0.5 ms of a constant, the rate
    /// swinging by at most 200 ppm, which is inaudible.
    @Test func aSourceDeliveringInBurstsIsNotCorrected() {
        var device = SimulatedDevice.steady(ppm: 0)
        device.bufferSamples = 960
        device.extraLateness = { captured, _ in [0, 0.0027, 0.0056, 0.0015][Int(captured) % 4] }
        let run = run(device, seconds: 120)
        // With no clock drift, applied is minus the error; the true lowest lateness is at 0.
        let applied = zip(run.seconds, run.error).filter { $0.0 >= 30 }.map { -$0.1 }
        let constant = (applied.max()! + applied.min()!) / 2
        #expect(applied.max()! - applied.min()! <= 0.001, "\(applied.min()! * 1000) to \(applied.max()! * 1000) ms")
        #expect(abs(constant) < 0.001, "\(constant * 1000) ms")
        let largestRate = run.rate.map { abs($0) }.max()!
        #expect(largestRate <= 200e-6, "\(largestRate * 1e6) ppm")
    }

    /// For 4 s every buffer arrives 0.5 to 4 s late: the intervals are
    /// rejected, the correction goes on at its rate.
    @Test func aStallIsRejected() {
        var device = SimulatedDevice.steady(ppm: -116)
        device.extraLateness = { captured, random in
            (20..<24).contains(captured) ? Double.random(in: 0.5...4, using: &random) : 0
        }
        let run = run(device, seconds: 80)
        #expect(run.worstError(from: 15, to: 54) < 0.001, "\(run.worstError(from: 15) * 1000) ms")
        #expect(run.worstError(from: 54) < 0.0003, "\(run.worstError(from: 54) * 1000) ms")
        #expect(run.rate.allSatisfy { abs($0) <= 0.001 })
    }

    /// The device loses 50 ms at once without its timestamps showing it:
    /// rejected for 10 intervals, then followed at the largest rate, within
    /// 1 ms from 120 s after the step.
    @Test func aLastingStepUpIsFollowedAfterTenRejectedIntervals() {
        let device = SimulatedDevice(offset: { seconds in 50e-6 * seconds + (seconds >= 30 ? 0.05 : 0) })
        let run = run(device, seconds: 160)
        // Interval 30 still has its least late buffer before the step; the
        // 10 intervals from 31 s to 41 s are rejected: the rate stays as it was.
        let rejected = zip(run.seconds, run.rate).filter { (31.1..<40.9).contains($0.0) }.map(\.1)
        #expect(Set(rejected).count == 1)
        #expect(abs(run.rate(at: 31.1) - 50e-6) < 50e-6)
        // Then followed at the largest rate.
        #expect(run.rate(at: 42) == 0.001)
        #expect(run.worstError(from: 150) < 0.001, "\(run.worstError(from: 150) * 1000) ms")
        #expect(run.rate.allSatisfy { abs($0) <= 0.001 })
    }

    /// A step down cannot be a late buffer: accepted at once, followed
    /// without overshooting, and the clock drift shown starts again.
    @Test func aStepDownIsFollowedAtOnce() throws {
        let device = SimulatedDevice(offset: { seconds in 50e-6 * seconds - (seconds >= 30 ? 0.01 : 0) })
        let run = run(device, seconds: 210)
        #expect(run.largestError(from: 30, sign: 1) < 0.001, "overshoot \(run.largestError(from: 30, sign: 1) * 1000) ms")
        #expect(run.worstError(from: 90) < 0.0005, "\(run.worstError(from: 90) * 1000) ms")
        #expect(run.drift.compactMap(\.self).allSatisfy { abs($0) <= 1000 })
        let off = zip(run.seconds, run.drift).filter { $0.0 >= 150 }.map { abs(($0.1 ?? .infinity) - -50) }.max()!
        #expect(off < 5, "\(off) ppm off from 150 s")
    }

    /// A step up under 5 ms is simply followed, without overshooting.
    @Test func aSmallStepUpIsFollowed() {
        let device = SimulatedDevice(offset: { seconds in 50e-6 * seconds + (seconds >= 30 ? 0.004 : 0) })
        let run = run(device, seconds: 150)
        #expect(run.largestError(from: 30, sign: -1) < 0.0005, "overshoot \(run.largestError(from: 30, sign: -1) * 1000) ms")
    }

    /// Buffers of 8192 samples, about 6 a second, are enough for a measurement.
    @Test func largeBuffersAreMeasured() throws {
        var device = SimulatedDevice.steady(ppm: -116)
        device.bufferSamples = 8192
        let run = run(device, seconds: 90)
        #expect(run.worstError(from: 30) < 0.0005, "\(run.worstError(from: 30) * 1000) ms")
        #expect(abs(try #require(run.drift.last ?? nil) - -116) < 5)
    }

    /// No buffers for 60 s, then on: the correction catches up.
    @Test func aPauseIsCaughtUp() {
        var device = SimulatedDevice.steady(ppm: -116)
        device.paused = { (30..<90).contains($0) }
        let run = run(device, seconds: 150)
        #expect(run.worstError(from: 120) < 0.0005, "\(run.worstError(from: 120) * 1000) ms")
        #expect(run.rate.allSatisfy { abs($0) <= 0.001 })
    }

    /// A tracker whose intervals start on whole seconds: its first buffer,
    /// at 0, is interval 0's only one, too few for a measurement.
    private func tracker() -> ClockDriftTracker {
        var tracker = ClockDriftTracker()
        tracker.record(time: 0, arrival: 0, applied: 0)
        return tracker
    }

    /// `count` buffers in the interval `index`, each `lateness` late; the
    /// interval before is measured at the first of them.
    private func interval(_ tracker: inout ClockDriftTracker, _ index: Int64, lateness: Int64, count: Int = 10, applied: Double = 0) {
        let second: Int64 = 1_000_000_000
        for buffer in 0..<count {
            let time = index * second + 50_000_000 + Int64(buffer) * 90_000_000
            tracker.record(time: time, arrival: time + lateness, applied: applied)
        }
    }

    @Test func noCorrectionUntilFiveIntervalsWereSeenAndTheLowestIsTheReference() {
        var tracker = tracker()
        for (index, lateness) in [3_000_000, 1_000_000, 4_000_000, 2_000_000, 3_000_000].enumerated() {
            interval(&tracker, Int64(index) + 1, lateness: Int64(lateness))
        }
        #expect(tracker.target == nil)
        #expect(tracker.rate == 0)
        // Interval 5 measured: the reference is the lowest of the five, 1 ms.
        interval(&tracker, 6, lateness: 1_000_000, count: 1)
        #expect(tracker.target == 0)
        #expect(tracker.rate == 0)
    }

    @Test func anIntervalWithFewerThanThreeBuffersChangesNothing() {
        var tracker = tracker()
        for index in 1...5 { interval(&tracker, Int64(index), lateness: 1_000_000) }
        // Interval 6 with 2 buffers 3 ms early would lower the rolling minimum.
        interval(&tracker, 6, lateness: -2_000_000, count: 2)
        #expect(tracker.target == 0)
        interval(&tracker, 7, lateness: 1_000_000, count: 3)
        interval(&tracker, 8, lateness: 1_000_000, count: 1)
        // Interval 7 measured; interval 6 gave nothing.
        #expect(tracker.target == 0)
        #expect(tracker.rate == 0)
    }

    @Test func theLoopIsProportionalAndIntegralWithinTheLimit() throws {
        var tracker = tracker()
        for index in 1...5 { interval(&tracker, Int64(index), lateness: 1_000_000) }
        interval(&tracker, 6, lateness: 0, applied: -0.0004)
        #expect(tracker.target == 0)
        interval(&tracker, 7, lateness: 0, applied: -0.0004)
        // Interval 6: 1 ms to remove, 0.4 ms removed before its least late
        // buffer, 0.999 s after interval 5's (which arrived 1 ms later into
        // its second): the integral ω² · -0.6 ms · 0.999 s, the rate that
        // plus 2ω · -0.6 ms.
        let frequency = RecorderValues.clockDriftLoopFrequency
        let integral = frequency * frequency * -0.0006 * 0.999
        #expect(abs(try #require(tracker.target) - -0.001) < 1e-12)
        #expect(abs(tracker.integral - integral) < 1e-12)
        #expect(abs(tracker.rate - (integral + 2 * frequency * -0.0006)) < 1e-12)
        #expect(abs(try #require(tracker.remaining) - -0.0006) < 1e-12)
        // Interval 7 the same, 1 s later: interval 6 moved along the
        // integral is the smallest. Then 30 ms lower is a step, accepted at
        // once; beyond the limit, the integral holds.
        interval(&tracker, 8, lateness: -30_000_000, applied: -0.0004)
        let measured = -0.001 + integral * 1
        let integrated = integral + frequency * frequency * (measured - -0.0004)
        #expect(abs(try #require(tracker.target) - measured) < 1e-12)
        #expect(abs(tracker.integral - integrated) < 1e-12)
        interval(&tracker, 9, lateness: -30_000_000, applied: -0.0004)
        #expect(abs(try #require(tracker.target) - -0.031) < 1e-12)
        #expect(tracker.rate == -0.001)
        #expect(abs(tracker.integral - integrated) < 1e-12)
    }
}
