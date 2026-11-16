/// How far an audio source's sound falls behind the shared clock (or runs
/// ahead of it), measured from when its buffers arrive, and the correction
/// rate that follows it. A buffer's lateness is its arrival minus its
/// timestamp; a buffer can arrive late, never early, so the smallest
/// lateness of a window of buffers is the device's clock against the shared
/// clock. The first measurement is the reference; `target`, a measurement
/// minus the reference, is the sound that must have been added so far.
/// Times are nanoseconds on the shared clock; lateness, `target` and
/// `applied` are seconds; a rate is output samples per input sample minus 1.
public struct ClockDriftTracker: Sendable {
    public let window: Int64
    public let minimumBuffers: Int
    public let rateFitLength: Int
    public let shownFitLength: Int
    public let shownMinimum: Int
    public let followSeconds: Double
    public let maximumRate: Double
    public let rejectedLateness: Double
    public let rejectedInARowLimit: Int

    /// The correction rate until the next measurement.
    public private(set) var rate: Double = 0
    /// The sound that must have been added so far, as of the latest
    /// measurement, taken forward along the rate fit to the buffer it came with.
    public private(set) var target: Double?
    /// The correction really applied so far, as last told.
    public private(set) var applied: Double = 0

    private var firstArrival: Int64?
    private var windowIndex: Int64 = 0
    private var windowBuffers = 0
    private var windowLateness = Double.infinity
    /// When the window's least late buffer arrived, in seconds from the first arrival.
    private var windowLatenessAt = 0.0
    private var reference: Double?
    /// The accepted measurements: when the least late buffer arrived, in
    /// seconds from the first arrival, and the lateness against the reference.
    private var history: [(time: Double, target: Double)] = []
    private var rejectedInARow = 0

    public init(
        window: Duration = RecorderValues.clockDriftWindow,
        minimumBuffers: Int = RecorderValues.clockDriftWindowMinimumBuffers,
        rateFitLength: Int = RecorderValues.clockDriftRateFitMeasurements,
        shownFitLength: Int = RecorderValues.clockDriftShownFitMeasurements,
        shownMinimum: Int = RecorderValues.clockDriftShownMinimumMeasurements,
        followTime: Duration = RecorderValues.clockDriftFollowTime,
        maximumRatePpm: Double = RecorderValues.clockDriftMaximumRatePpm,
        rejectedLateness: Duration = RecorderValues.clockDriftRejectedLateness,
        rejectedInARowLimit: Int = RecorderValues.clockDriftRejectedWindowsInARow
    ) {
        precondition(window > .zero && followTime > .zero, "the clock drift tracker needs a positive window and follow time")
        precondition(rateFitLength >= 3 && shownFitLength >= shownMinimum && shownMinimum >= 3,
                     "the clock drift tracker's fits need at least 3 measurements")
        self.window = window.nanoseconds
        self.minimumBuffers = minimumBuffers
        self.rateFitLength = rateFitLength
        self.shownFitLength = shownFitLength
        self.shownMinimum = shownMinimum
        followSeconds = Double(followTime.nanoseconds) / 1e9
        maximumRate = maximumRatePpm / 1e6
        self.rejectedLateness = Double(rejectedLateness.nanoseconds) / 1e9
        self.rejectedInARowLimit = rejectedInARowLimit
    }

    /// The device's clock drift in parts per million, positive when its
    /// clock runs fast; nil until enough measurements.
    public var clockDriftPpm: Double? {
        guard history.count >= shownMinimum else { return nil }
        return -Self.slope(history.suffix(shownFitLength)) * 1e6
    }

    /// What is still off: `target` minus `applied`; nil before the first measurement.
    public var remaining: Double? { target.map { $0 - applied } }

    /// A buffer whose first sample has the timestamp `time` arrived at
    /// `arrival`; `applied` is the correction applied before it.
    public mutating func record(time: Int64, arrival: Int64, applied: Double) {
        self.applied = applied
        let first = firstArrival ?? arrival
        firstArrival = first
        let index = (arrival - first) / window
        let now = Double(arrival - first) / 1e9
        if index > windowIndex {
            if windowBuffers >= minimumBuffers { measure(windowLateness, at: windowLatenessAt, now: now) }
            windowIndex = index
            windowBuffers = 0
            windowLateness = .infinity
        }
        windowBuffers += 1
        let lateness = Double(arrival - time) / 1e9
        if lateness < windowLateness {
            windowLateness = lateness
            windowLatenessAt = now
        }
    }

    /// A window's smallest lateness, measured at `time`; `target` and the
    /// rate are taken forward along the fit to `now`, where `applied` is.
    private mutating func measure(_ lateness: Double, at time: Double, now: Double) {
        let reference = reference ?? lateness
        self.reference = reference
        let measured = lateness - reference
        if let expected = expected(at: time), measured - expected > rejectedLateness {
            guard rejectedInARow >= rejectedInARowLimit else {
                rejectedInARow += 1
                return
            }
            history = []
        }
        rejectedInARow = 0
        history.append((time, measured))
        if history.count > shownFitLength { history.removeFirst() }
        let rateFit = history.suffix(rateFitLength)
        let slope = rateFit.count >= 3 ? Self.slope(rateFit) : 0
        let target = measured + slope * (now - time)
        self.target = target
        rate = min(maximumRate, max(-maximumRate, slope + (target - applied) / followSeconds))
    }

    /// The lateness expected at `time`: the rate fit's line, or the last
    /// accepted measurement while there are fewer than 3.
    private func expected(at time: Double) -> Double? {
        let rateFit = history.suffix(rateFitLength)
        guard rateFit.count >= 3 else { return history.last?.target }
        let meanTime = rateFit.reduce(0) { $0 + $1.time } / Double(rateFit.count)
        let meanTarget = rateFit.reduce(0) { $0 + $1.target } / Double(rateFit.count)
        return meanTarget + Self.slope(rateFit) * (time - meanTime)
    }

    /// The least-squares slope of the targets against their times.
    private static func slope(_ points: ArraySlice<(time: Double, target: Double)>) -> Double {
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
