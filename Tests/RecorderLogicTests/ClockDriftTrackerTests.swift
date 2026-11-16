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
    }

    private func run(_ device: SimulatedDevice, seconds: Double, seed: UInt64 = 1) -> Run {
        var tracker = ClockDriftTracker()
        var applied = 0.0
        var run = Run()
        let bufferSeconds = Double(device.bufferSamples) / Double(SimulatedDevice.sampleRate)
        for buffer in device.buffers(for: seconds, seed: seed) {
            tracker.record(time: buffer.time, arrival: buffer.arrival, applied: applied)
            applied += tracker.rate * bufferSeconds
            run.seconds.append(buffer.seconds)
            run.error.append(device.offset(buffer.seconds) - applied)
            run.rate.append(tracker.rate)
            run.drift.append(tracker.clockDriftPpm)
        }
        return run
    }

    @Test func theValuesAreTheDesignsStartingPoints() {
        #expect(RecorderValues.clockDriftWindow == .seconds(1))
        #expect(RecorderValues.clockDriftWindowMinimumBuffers == 10)
        #expect(RecorderValues.clockDriftRollingWindows == 5)
        #expect(RecorderValues.clockDriftRateFitMeasurements == 30)
        #expect(RecorderValues.clockDriftShownFitMeasurements == 60)
        #expect(RecorderValues.clockDriftShownMinimumMeasurements == 10)
        #expect(RecorderValues.clockDriftFollowTime == .seconds(15))
        #expect(RecorderValues.clockDriftMaximumRatePpm == 1000)
        #expect(RecorderValues.clockDriftRejectedLateness == .milliseconds(5))
        #expect(RecorderValues.clockDriftRejectedWindowsInARow == 10)
    }

    @Test(arguments: [-116.0, 50.0], [UInt64(1), 2, 3])
    func aSteadyDeviceIsFollowedWithinAThirdOfAMillisecond(ppm: Double, seed: UInt64) throws {
        let run = run(.steady(ppm: ppm), seconds: 90, seed: seed)
        #expect(run.worstError(from: 15) < 0.0003, "\(run.worstError(from: 15) * 1000) ms")
        #expect(run.rate.allSatisfy { abs($0) <= 0.001 })
        let shown = zip(run.seconds, run.drift)
        #expect(shown.filter { $0.0 < 13 }.allSatisfy { $0.1 == nil })
        for (seconds, drift) in shown where seconds >= 30 {
            let drift = try #require(drift)
            #expect(abs(drift - ppm) < (seconds >= 60 ? 2 : 12), "\(drift) ppm at \(seconds) s")
        }
    }

    /// A device whose rate alternates between +100 and −100 ppm every 12 s,
    /// as the Logitech BRIO's wanders.
    @Test func aWanderingDeviceIsFollowedWithinOneAndAHalfMilliseconds() {
        let device = SimulatedDevice(offset: { seconds in
            let period = Int(seconds / 12)
            let into = seconds - Double(period) * 12
            let atPeriodStart = period % 2 == 0 ? 0 : 12 * 100e-6
            return atPeriodStart + (period % 2 == 0 ? 100e-6 : -100e-6) * into
        })
        let run = run(device, seconds: 90)
        #expect(run.worstError(from: 15) < 0.0015, "\(run.worstError(from: 15) * 1000) ms")
        #expect(run.rate.allSatisfy { abs($0) <= 0.001 })
    }

    /// The system audio: buffers of 960 samples, no clock drift, but
    /// delivered in bursts, so each second's smallest lateness follows a
    /// sawtooth of 0, 2.7, 5.6 and 1.5 ms. The rolling minimum finds the
    /// lowest; the correction stays put.
    @Test func aSourceDeliveringInBurstsIsNotCorrected() {
        var device = SimulatedDevice.steady(ppm: 0)
        device.bufferSamples = 960
        device.extraLateness = { captured, _ in [0, 0.0027, 0.0056, 0.0015][Int(captured) % 4] }
        let run = run(device, seconds: 120)
        let applied = zip(run.seconds, run.error).filter { $0.0 >= 30 }.map { -$0.1 }
        let constant = (applied.max()! + applied.min()!) / 2
        #expect(applied.max()! - applied.min()! <= 0.001, "\(applied.min()! * 1000) to \(applied.max()! * 1000) ms")
        #expect(abs(constant) < 0.001, "\(constant * 1000) ms")
        #expect(zip(run.seconds, run.rate).filter { $0.0 >= 30 }.allSatisfy { abs($0.1) <= 30e-6 })
        #expect(run.rate.allSatisfy { abs($0) <= 0.001 })
    }

    /// For 4 s every buffer arrives 0.5 to 4 s late: the windows are
    /// rejected, the correction goes on at its rate.
    @Test func aStallIsRejected() {
        var device = SimulatedDevice.steady(ppm: -116)
        device.extraLateness = { captured, random in
            (20..<24).contains(captured) ? Double.random(in: 0.5...4, using: &random) : 0
        }
        let run = run(device, seconds: 80)
        #expect(run.worstError(from: 15) < 0.001, "\(run.worstError(from: 15) * 1000) ms")
        #expect(run.worstError(from: 54) < 0.0003, "\(run.worstError(from: 54) * 1000) ms")
        #expect(run.rate.allSatisfy { abs($0) <= 0.001 })
    }

    /// The device loses 50 ms at once without its timestamps showing it:
    /// rejected for 10 windows, then followed at the largest rate, within
    /// 1 ms 105 s after the step.
    @Test func aLastingStepIsFollowedAfterTenRejectedWindows() {
        let device = SimulatedDevice(offset: { seconds in 50e-6 * seconds + (seconds >= 30 ? 0.05 : 0) })
        let run = run(device, seconds: 140)
        let rateAt = { (seconds: Double) in run.rate[run.seconds.firstIndex { $0 >= seconds }!] }
        // The rolling minimum still holds the windows before the step for 4
        // windows; then 10 windows (34 s to 44 s) are rejected: the rate stays as it was.
        let rejected = zip(run.seconds, run.rate).filter { (34.5..<44.5).contains($0.0) }.map(\.1)
        #expect(Set(rejected).count == 1)
        #expect(abs(rateAt(34.5) - 50e-6) < 50e-6)
        // Then followed at the largest rate.
        #expect(rateAt(46) == 0.001)
        #expect(run.worstError(from: 135) < 0.001, "\(run.worstError(from: 135) * 1000) ms")
        #expect(run.rate.allSatisfy { abs($0) <= 0.001 })
    }

    /// A tracker whose windows start on whole seconds: its first buffer, at
    /// 0, is window 0's only one, too few for a measurement.
    private func tracker() -> ClockDriftTracker {
        var tracker = ClockDriftTracker()
        tracker.record(time: 0, arrival: 0, applied: 0)
        return tracker
    }

    /// `count` buffers in the window `index`, each `lateness` late; the
    /// window before is measured at the first of them.
    private func window(_ tracker: inout ClockDriftTracker, _ index: Int64, lateness: Int64, count: Int = 10, applied: Double = 0) {
        let second: Int64 = 1_000_000_000
        for buffer in 0..<count {
            let time = index * second + 50_000_000 + Int64(buffer) * 90_000_000
            tracker.record(time: time, arrival: time + lateness, applied: applied)
        }
    }

    @Test func noCorrectionUntilFiveWindowsWereSeenAndTheLowestIsTheReference() {
        var tracker = tracker()
        for (index, lateness) in [3_000_000, 1_000_000, 4_000_000, 2_000_000, 3_000_000].enumerated() {
            window(&tracker, Int64(index) + 1, lateness: Int64(lateness))
        }
        #expect(tracker.target == nil)
        #expect(tracker.rate == 0)
        // Window 5 measured: the reference is the lowest of the five, 1 ms.
        window(&tracker, 6, lateness: 1_000_000, count: 1)
        #expect(tracker.target == 0)
        #expect(tracker.rate == 0)
    }

    @Test func aWindowWithFewerThanTenBuffersChangesNothing() {
        var tracker = tracker()
        for index in 1...5 { window(&tracker, Int64(index), lateness: 1_000_000) }
        // Window 6 with 9 buffers 3 ms early would lower the rolling minimum.
        window(&tracker, 6, lateness: -2_000_000, count: 9)
        #expect(tracker.target == 0)
        window(&tracker, 7, lateness: 1_000_000)
        window(&tracker, 8, lateness: 1_000_000, count: 1)
        // Window 7 measured; window 6 gave nothing.
        #expect(tracker.target == 0)
        #expect(tracker.rate == 0)
    }

    @Test func theRateClosesWhatIsStillOffWithinTheLimitAndALowerMeasurementIsNeverRejected() throws {
        var tracker = tracker()
        for index in 1...5 { window(&tracker, Int64(index), lateness: 1_000_000) }
        window(&tracker, 6, lateness: 0)
        #expect(tracker.target == 0)
        window(&tracker, 7, lateness: 0, applied: -0.0004)
        // 1 ms to remove, 0.4 ms removed: -0.6 ms over 15 s, -40 ppm; no slope yet.
        #expect(abs(try #require(tracker.target) - -0.001) < 1e-12)
        #expect(abs(tracker.rate - -0.00004) < 1e-12)
        #expect(abs(try #require(tracker.remaining) - -0.0006) < 1e-12)
        // 31 ms to remove is beyond the limit, and a lower lateness is never a stall.
        window(&tracker, 8, lateness: -30_000_000)
        window(&tracker, 9, lateness: -30_000_000)
        #expect(try #require(tracker.target) < -0.03)
        #expect(tracker.rate == -0.001)
    }
}
