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
        let bufferSeconds = Double(SimulatedDevice.bufferSamples) / Double(SimulatedDevice.sampleRate)
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
        #expect(RecorderValues.clockDriftRateFitMeasurements == 10)
        #expect(RecorderValues.clockDriftShownFitMeasurements == 60)
        #expect(RecorderValues.clockDriftShownMinimumMeasurements == 10)
        #expect(RecorderValues.clockDriftFollowTime == .seconds(5))
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
        #expect(shown.filter { $0.0 < 10 }.allSatisfy { $0.1 == nil })
        for (seconds, drift) in shown where seconds >= 15 {
            let drift = try #require(drift)
            #expect(abs(drift - ppm) < (seconds >= 60 ? 2 : 10), "\(drift) ppm at \(seconds) s")
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
    /// rejected for 10 windows, then followed at the largest rate.
    @Test func aLastingStepIsFollowedAfterTenRejectedWindows() {
        let device = SimulatedDevice(offset: { seconds in 50e-6 * seconds + (seconds >= 30 ? 0.05 : 0) })
        let run = run(device, seconds: 125)
        let rateAt = { (seconds: Double) in run.rate[run.seconds.firstIndex { $0 >= seconds }!] }
        // The 10 windows from the step on (30 s to 40 s) are rejected: the rate stays as it was.
        let rejected = zip(run.seconds, run.rate).filter { (30.5..<40.5).contains($0.0) }.map(\.1)
        #expect(Set(rejected).count == 1)
        #expect(abs(rateAt(30.5) - 50e-6) < 50e-6)
        // Then followed at the largest rate.
        #expect(rateAt(42) == 0.001)
        #expect(run.worstError(from: 120) < 0.001, "\(run.worstError(from: 120) * 1000) ms")
        #expect(run.rate.allSatisfy { abs($0) <= 0.001 })
    }

    @Test func aWindowWithFewerThanTenBuffersChangesNothing() {
        var tracker = ClockDriftTracker()
        let second: Int64 = 1_000_000_000
        // Window 0 with 10 buffers: the reference; window 1 with 9 buffers late by 3 ms.
        for index in 0..<10 { tracker.record(time: Int64(index) * second / 10, arrival: Int64(index) * second / 10 + 1_000_000, applied: 0) }
        for index in 0..<9 { tracker.record(time: second + Int64(index) * second / 10, arrival: second + Int64(index) * second / 10 + 4_000_000, applied: 0) }
        // Window 0 is the reference.
        #expect(tracker.target == 0)
        tracker.record(time: 2 * second, arrival: 2 * second + 1_000_000, applied: 0)
        // Window 0 measured; window 1 gave nothing.
        #expect(tracker.target == 0)
        #expect(tracker.rate == 0)
        for index in 1..<10 { tracker.record(time: 2 * second + Int64(index) * second / 10, arrival: 2 * second + Int64(index) * second / 10 + 1_000_000, applied: 0) }
        tracker.record(time: 3 * second, arrival: 3 * second + 3_000_000, applied: 0)
        #expect(tracker.target == 0)
        #expect(tracker.rate == 0)
    }

    @Test func theRateClosesWhatIsStillOffWithinTheLimitAndALowerMeasurementIsNeverRejected() throws {
        var tracker = ClockDriftTracker()
        let second: Int64 = 1_000_000_000
        // Ten buffers in the window `index`, each `lateness` late; the
        // window before is measured at its first buffer.
        func window(_ index: Int64, lateness: Int64, applied: Double = 0) {
            for buffer in 0..<10 {
                let time = index * second + 50_000_000 + Int64(buffer) * 90_000_000
                tracker.record(time: time, arrival: time + lateness, applied: applied)
            }
        }
        window(0, lateness: 1_000_000)
        window(1, lateness: 2_000_000)
        #expect(tracker.target == 0)
        #expect(tracker.rate == 0)
        window(2, lateness: 2_000_000, applied: 0.0004)
        // 1 ms to add, 0.4 ms applied: 0.6 ms over 5 s, 120 ppm; no slope yet.
        #expect(abs(try #require(tracker.target) - 0.001) < 1e-12)
        #expect(abs(tracker.rate - 0.00012) < 1e-12)
        #expect(abs(try #require(tracker.remaining) - 0.0006) < 1e-12)
        // 2.8 ms above the expected 1.7 ms is no stall; 4.5 ms to add is beyond the limit.
        window(3, lateness: 5_500_000)
        window(4, lateness: 5_500_000)
        #expect(try #require(tracker.target) > 0.0045)
        #expect(tracker.rate == 0.001)
        window(5, lateness: -30_000_000)
        window(6, lateness: -30_000_000)
        #expect(try #require(tracker.target) < -0.03)
        #expect(tracker.rate == -0.001)
    }
}
