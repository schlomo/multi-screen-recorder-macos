/// How far an audio source's sound falls behind the shared clock (or runs
/// ahead of it), measured from when its buffers arrive, and the correction
/// rate that follows it. A buffer's lateness is its arrival minus its
/// timestamp; a buffer can arrive late, never early. Each interval with a
/// buffer gives a point: its smallest lateness, at the arrival of that
/// buffer. The device's clock is the lower support line of the points of
/// the horizon: the line on or below every point, no steeper than the
/// largest rate, closest to them in sum. Late stretches, bursts and sparse
/// intervals lie above it and do not move it; the measurement never
/// depends on the correction. Once the points are enough (an estimate),
/// the first estimate's line at the first point is the reference, and the
/// line now minus the reference is `target`, the sound that must have
/// been added so far. The rate is the line's slope plus what is still off
/// over the catch-up time. Times are nanoseconds on the shared clock;
/// lateness, `target` and `applied` are seconds; a rate or a slope is
/// output samples per input sample minus 1 (seconds of lateness per second).
public struct ClockDriftTracker: Sendable {
    /// A line `value + slope · (t − time)`, times in seconds.
    struct Line: Equatable {
        var time: Double
        var value: Double
        var slope: Double

        func value(at time: Double) -> Double { value + slope * (time - self.time) }
    }

    public let interval: Int64
    public let horizon: Double
    public let minimumPoints: Int
    public let minimumSpan: Double
    public let catchUpTime: Double
    public let maximumRate: Double
    public let shownEstimates: Int
    public let shownMinimum: Int

    /// The correction rate until the next estimate.
    public private(set) var rate: Double = 0
    /// The sound that must have been added so far, as of the latest estimate.
    public private(set) var target: Double?
    /// What was still off at the latest estimate: `target` minus the
    /// correction applied then; nil before the first estimate.
    private(set) var remaining: Double?

    private var firstArrival: Int64?
    private var intervalIndex: Int64 = 0
    private var intervalHasBuffer = false
    private var intervalLateness = Double.infinity
    /// When the interval's least late buffer arrived, in seconds from the first arrival.
    private var intervalLatenessAt = 0.0
    /// The points of the horizon: when, and the smallest lateness.
    private var points: [(time: Double, lateness: Double)] = []
    private var firstPointTime: Double?
    private var reference: Double?
    /// The latest estimates' slopes, for the clock drift shown.
    private var slopes: [Double] = []

    public init(
        interval: Duration = RecorderValues.clockDriftInterval,
        horizon: Duration = RecorderValues.clockDriftHorizon,
        minimumPoints: Int = RecorderValues.clockDriftEstimateMinimumPoints,
        minimumSpan: Duration = RecorderValues.clockDriftEstimateMinimumSpan,
        catchUpTime: Duration = RecorderValues.clockDriftCatchUpTime,
        maximumRatePpm: Double = RecorderValues.clockDriftMaximumRatePpm,
        shownEstimates: Int = RecorderValues.clockDriftShownEstimates,
        shownMinimum: Int = RecorderValues.clockDriftShownMinimumEstimates
    ) {
        precondition(interval > .zero && horizon > minimumSpan, "the clock drift tracker needs an interval and a horizon longer than an estimate's span")
        precondition(minimumPoints >= 2 && catchUpTime > .zero, "an estimate needs two points and a positive catch-up time")
        precondition(shownEstimates >= shownMinimum && shownMinimum > 0, "the clock drift shown needs an estimate")
        self.interval = interval.nanoseconds
        self.horizon = Self.seconds(horizon)
        self.minimumPoints = minimumPoints
        self.minimumSpan = Self.seconds(minimumSpan)
        self.catchUpTime = Self.seconds(catchUpTime)
        maximumRate = maximumRatePpm / 1e6
        self.shownEstimates = shownEstimates
        self.shownMinimum = shownMinimum
    }

    /// The device's clock drift in parts per million, positive when its
    /// clock runs fast: the mean slope of the latest estimates; nil until
    /// there are enough.
    public var clockDriftPpm: Double? {
        guard slopes.count >= shownMinimum else { return nil }
        return -slopes.reduce(0, +) / Double(slopes.count) * 1e6
    }

    /// How far the device's clock drifts during a gap of `length`
    /// nanoseconds, in seconds: the latest estimate's slope over it, 0
    /// before the first estimate.
    public func drift(over length: Int64) -> Double {
        (slopes.last ?? 0) * Double(length) / 1e9
    }

    /// A buffer whose first sample has the timestamp `time` arrived at
    /// `arrival`; `applied` is the correction applied before it.
    public mutating func record(time: Int64, arrival: Int64, applied: Double) {
        let first = firstArrival ?? arrival
        firstArrival = first
        let index = (arrival - first) / interval
        if index > intervalIndex {
            if intervalHasBuffer { estimate(applied: applied) }
            // The intervals between gave no point: the rate follows the last slope.
            if index > intervalIndex + 1, let slope = slopes.last { rate = slope }
            intervalIndex = index
            intervalHasBuffer = false
            intervalLateness = .infinity
        }
        intervalHasBuffer = true
        let lateness = Double(arrival - time) / 1e9
        if lateness < intervalLateness {
            intervalLateness = lateness
            intervalLatenessAt = Double(arrival - first) / 1e9
        }
    }

    /// The interval ended: its point joins the horizon's, and with enough
    /// of them the line gives the target and the rate, at the interval's
    /// end; `applied` is the correction applied by then.
    private mutating func estimate(applied: Double) {
        let now = Double((intervalIndex + 1) * interval) / 1e9
        points.append((intervalLatenessAt, intervalLateness))
        if firstPointTime == nil { firstPointTime = intervalLatenessAt }
        points.removeAll { $0.time <= now - horizon }
        guard points.count >= minimumPoints, points.last!.time - points.first!.time >= minimumSpan else {
            if let slope = slopes.last { rate = slope }
            return
        }
        let line = Self.supportLine(points, maximumSlope: maximumRate)
        if reference == nil { reference = line.value(at: firstPointTime!) }
        let target = line.value(at: now) - reference!
        self.target = target
        remaining = target - applied
        slopes.append(line.slope)
        if slopes.count > shownEstimates { slopes.removeFirst() }
        rate = min(maximumRate, max(-maximumRate, line.slope + (target - applied) / catchUpTime))
    }

    /// The lower support line of `points`: on or below every one, its
    /// slope within ±`maximumSlope`, with the smallest sum of distances to
    /// them. The best slope is one between two points or a limit; for a
    /// slope, the line touches the point lowest against it.
    static func supportLine(_ points: [(time: Double, lateness: Double)], maximumSlope: Double) -> Line {
        precondition(!points.isEmpty, "a support line needs a point")
        let newest = points.last!.time
        let times = points.map { $0.time - newest }
        let lateness = points.map(\.lateness)
        let count = points.count
        let sumOfTimes = times.reduce(0, +)
        let sumOfLateness = lateness.reduce(0, +)
        var best = (sum: Double.infinity, line: Line(time: newest, value: 0, slope: 0))
        func consider(_ slope: Double) {
            var value = Double.infinity
            for index in 0..<count { value = min(value, lateness[index] - slope * times[index]) }
            let sum = sumOfLateness - Double(count) * value - slope * sumOfTimes
            if sum < best.sum - 1e-15 { best = (sum, Line(time: newest, value: value, slope: slope)) }
        }
        consider(-maximumSlope)
        consider(maximumSlope)
        for i in 0..<count {
            for j in (i + 1)..<count where times[j] != times[i] {
                let slope = (lateness[j] - lateness[i]) / (times[j] - times[i])
                if abs(slope) <= maximumSlope { consider(slope) }
            }
        }
        return best.line
    }

    private static func seconds(_ duration: Duration) -> Double { Double(duration.nanoseconds) / 1e9 }
}
