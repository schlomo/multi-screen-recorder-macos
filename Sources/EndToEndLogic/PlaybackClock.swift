/// Where the test tone is in each render cycle of the player: taken from
/// the cycle's own sample time, so a cycle the output skipped leaves the
/// tone where the clock is rather than shifting it, and the skip is told.
public struct PlaybackClock: Sendable {
    public struct Cycle: Sendable, Equatable {
        /// The tone's sample index of the cycle's first frame.
        public var firstIndex: Int64
        /// The samples between the previous cycle's end and this one's start,
        /// when they are not adjacent.
        public var skipped: Int64?

        public init(firstIndex: Int64, skipped: Int64?) {
            self.firstIndex = firstIndex
            self.skipped = skipped
        }
    }

    private var first: Double?
    private var next: Double?

    public init() {}

    public mutating func render(sampleTime: Double, frames: Int) -> Cycle {
        let start = first ?? sampleTime
        first = start
        let skipped = next.flatMap { sampleTime == $0 ? nil : Int64(sampleTime - $0) }
        next = sampleTime + Double(frames)
        return Cycle(firstIndex: Int64(sampleTime - start), skipped: skipped)
    }
}

/// A break in the tone player's output: a skipped stretch of samples, or an
/// overload the output device told of (no sample count then).
public struct PlaybackBreak: Sendable, Equatable {
    /// Seconds of the local day, when the player saw it.
    public var timeOfDay: Double
    public var samples: Int64?

    public init(timeOfDay: Double, samples: Int64?) {
        self.timeOfDay = timeOfDay
        self.samples = samples
    }
}
