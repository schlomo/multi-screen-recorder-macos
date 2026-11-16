/// How far an audio source's sound falls behind the shared clock (or runs
/// ahead of it), measured from when its buffers arrive, and the correction
/// rate that follows it. A buffer's lateness is its arrival minus its
/// timestamp; a buffer can arrive late, never early, so the smallest
/// lateness of the last few intervals of buffers (a rolling minimum, each
/// older interval's moved along the loop's integral to the newest) is the
/// device's clock against the shared clock; a source delivering in
/// bursts, such as the system audio, sits high in some intervals. The
/// first measurement, once the rolling minimum spans all its intervals, is
/// the reference; `target`, a measurement minus the reference, is the
/// sound that must have been added so far. A critically damped
/// proportional-integral loop turns what is still off into the rate; its
/// integral is the device's clock drift as the loop has learned it.
/// Times are nanoseconds on the shared clock; lateness, `target` and
/// `applied` are seconds; a rate is output samples per input sample minus 1.
public struct ClockDriftTracker: Sendable {
    public let interval: Int64
    public let minimumBuffers: Int
    public let rollingIntervals: Int
    public let shownFitLength: Int
    public let shownMinimum: Int
    public let shownSettling: Int
    public let proportionalGain: Double
    public let integralGain: Double
    public let maximumRate: Double
    public let step: Double
    public let rejectedInARowLimit: Int

    /// The correction rate until the next measurement.
    public private(set) var rate: Double = 0
    /// The sound that must have been added so far, as of the latest measurement.
    public private(set) var target: Double?
    /// The correction applied so far, as last told.
    private(set) var applied: Double = 0
    /// The loop's integral: the rate it has learned, without what is still off.
    private(set) var integral: Double = 0

    private var firstArrival: Int64?
    private var intervalIndex: Int64 = 0
    private var intervalBuffers = 0
    private var intervalLateness = Double.infinity
    /// When the interval's least late buffer arrived, in seconds from the
    /// first arrival, and the correction applied before it.
    private var intervalLatenessAt = 0.0
    private var intervalApplied = 0.0
    private var reference: Double?
    /// The smallest lateness of the latest intervals that were not
    /// rejected, each with when its least late buffer arrived; the
    /// reference is taken once there are `rollingIntervals`.
    private var rolling: [(time: Double, lateness: Double)] = []
    /// The latest accepted measurement.
    private var latest: (time: Double, target: Double)?
    /// The measurements of the clock drift shown since the last step: when,
    /// and the lateness against the reference.
    private var shownFit: [(time: Double, target: Double)] = []
    /// The measurements accepted since the reference or the last step.
    private var acceptedSinceStart = 0
    private var rejectedInARow = 0

    public init(
        interval: Duration = RecorderValues.clockDriftInterval,
        minimumBuffers: Int = RecorderValues.clockDriftIntervalMinimumBuffers,
        rollingIntervals: Int = RecorderValues.clockDriftRollingIntervals,
        loopFrequency: Double = RecorderValues.clockDriftLoopFrequency,
        shownFitLength: Int = RecorderValues.clockDriftShownFitMeasurements,
        shownMinimum: Int = RecorderValues.clockDriftShownMinimumMeasurements,
        shownSettling: Int = RecorderValues.clockDriftShownSettlingMeasurements,
        maximumRatePpm: Double = RecorderValues.clockDriftMaximumRatePpm,
        step: Duration = RecorderValues.clockDriftStep,
        rejectedInARowLimit: Int = RecorderValues.clockDriftRejectedIntervalsInARow
    ) {
        precondition(interval > .zero && loopFrequency > 0, "the clock drift tracker needs a positive interval and loop frequency")
        precondition(shownFitLength >= shownMinimum && shownMinimum >= 3, "the clock drift shown needs at least 3 measurements")
        precondition(rollingIntervals > 0 && minimumBuffers > 0, "the clock drift tracker needs an interval with a buffer")
        precondition(shownSettling >= 0, "the clock drift shown cannot leave out a negative number of measurements")
        self.interval = interval.nanoseconds
        self.minimumBuffers = minimumBuffers
        self.rollingIntervals = rollingIntervals
        self.shownFitLength = shownFitLength
        self.shownMinimum = shownMinimum
        self.shownSettling = shownSettling
        proportionalGain = 2 * loopFrequency
        integralGain = loopFrequency * loopFrequency
        maximumRate = maximumRatePpm / 1e6
        self.step = Double(step.nanoseconds) / 1e9
        self.rejectedInARowLimit = rejectedInARowLimit
    }

    /// The device's clock drift in parts per million, positive when its
    /// clock runs fast, within ±the largest rate: fitted over the latest
    /// measurements, leaving out the first ones after the reference or a
    /// step; nil until it has enough.
    public var clockDriftPpm: Double? {
        guard shownFit.count >= shownMinimum else { return nil }
        let ppm = -Self.slope(shownFit) * 1e6
        let limit = maximumRate * 1e6
        return min(limit, max(-limit, ppm))
    }

    /// What is still off: `target` minus `applied`; nil before the first measurement.
    var remaining: Double? { target.map { $0 - applied } }

    /// A buffer whose first sample has the timestamp `time` arrived at
    /// `arrival`; `applied` is the correction applied before it.
    public mutating func record(time: Int64, arrival: Int64, applied: Double) {
        self.applied = applied
        let first = firstArrival ?? arrival
        firstArrival = first
        let index = (arrival - first) / interval
        if index > intervalIndex {
            if intervalBuffers >= minimumBuffers { measure(intervalLateness, at: intervalLatenessAt, applied: intervalApplied) }
            intervalIndex = index
            intervalBuffers = 0
            intervalLateness = .infinity
        }
        intervalBuffers += 1
        let lateness = Double(arrival - time) / 1e9
        if lateness < intervalLateness {
            intervalLateness = lateness
            intervalLatenessAt = Double(arrival - first) / 1e9
            intervalApplied = applied
        }
    }

    /// An interval's smallest lateness, at `time`, when `applied` had been
    /// applied: with the intervals before it, the rolling minimum is the
    /// measurement.
    private mutating func measure(_ lateness: Double, at time: Double, applied: Double) {
        let candidates = Array(rolling.suffix(rollingIntervals - 1)) + [(time: time, lateness: lateness)]
        let smallest = candidates.map { $0.lateness + integral * (time - $0.time) }.min()!
        guard let reference, let latest else {
            rolling = candidates
            guard rolling.count >= rollingIntervals else { return }
            self.reference = smallest
            accept(0, at: time, applied: applied)
            return
        }
        let measured = smallest - reference
        let expected = latest.target + integral * (time - latest.time)
        // A stall is judged by the interval's own lateness: the rolling
        // minimum would hide it behind the older intervals moved along the
        // integral, which the stall would then feed back into.
        if lateness - reference - expected > step {
            guard rejectedInARow >= rejectedInARowLimit else {
                rejectedInARow += 1
                return
            }
            restart(lateness - reference, at: time, applied: applied)
        } else if expected - measured > step {
            restart(lateness - reference, at: time, applied: applied)
        } else {
            rolling = candidates
            accept(measured, at: time, applied: applied)
        }
    }

    /// The lateness stepped, up after the rejected intervals or down at
    /// once: the rolling minimum and the clock drift shown start again from
    /// this interval; the integral, the reference and `applied` stay.
    private mutating func restart(_ measured: Double, at time: Double, applied: Double) {
        rolling = [(time, measured + reference!)]
        shownFit = []
        acceptedSinceStart = 0
        accept(measured, at: time, applied: applied)
    }

    /// The loop compares the measurement with the correction applied at
    /// the same moment, before the least late buffer.
    private mutating func accept(_ measured: Double, at time: Double, applied: Double) {
        let elapsed = latest.map { time - $0.time } ?? 0
        rejectedInARow = 0
        latest = (time, measured)
        target = measured
        acceptedSinceStart += 1
        if acceptedSinceStart > shownSettling {
            shownFit.append((time, measured))
            if shownFit.count > shownFitLength { shownFit.removeFirst() }
        }
        let error = measured - applied
        // Anti-windup: the integral holds while the rate is at its limit.
        let integrated = min(maximumRate, max(-maximumRate, integral + integralGain * error * elapsed))
        if abs(integrated + proportionalGain * error) <= maximumRate { integral = integrated }
        rate = min(maximumRate, max(-maximumRate, integral + proportionalGain * error))
    }

    /// The least-squares slope of the targets against their times.
    private static func slope(_ points: [(time: Double, target: Double)]) -> Double {
        let count = Double(points.count)
        let meanTime = points.reduce(0) { $0 + $1.time } / count
        let meanTarget = points.reduce(0) { $0 + $1.target } / count
        var covariance = 0.0
        var variance = 0.0
        for point in points {
            covariance += (point.time - meanTime) * (point.target - meanTarget)
            variance += (point.time - meanTime) * (point.time - meanTime)
        }
        return variance > 0 ? covariance / variance : 0
    }
}
