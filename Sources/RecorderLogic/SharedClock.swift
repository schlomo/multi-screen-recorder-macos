/// The shared clock: one clock that counts sleep (`mach_continuous_time`),
/// with the recording's start t0 one instant on it. Frames are stamped with
/// the host clock, which stops while the Mac sleeps; the difference of the
/// two clocks is read at the start and again at every wake. No file spans a
/// sleep, so the conversion within a file is exact.
///
/// All times are in nanoseconds; offsets from t0 are signed.
public struct SharedClock: Equatable, Sendable {
    /// t0 on the continuous clock.
    public let start: UInt64
    /// The continuous clock minus the host clock, as last read.
    public private(set) var hostOffset: Int64

    /// `reading` is the two clocks read together at t0.
    public init(reading: ClockReading) {
        start = reading.continuous
        hostOffset = reading.offset
    }

    /// At wake, the clocks are read again: the host clock lost the sleep.
    public mutating func reread(_ reading: ClockReading) {
        hostOffset = reading.offset
    }

    /// Nanoseconds from t0 to an instant on the continuous clock.
    public func sinceStart(continuous: UInt64) -> Int64 {
        Int64(bitPattern: continuous &- start)
    }

    /// Nanoseconds from t0 to an instant on the host clock.
    public func sinceStart(host: UInt64) -> Int64 {
        Int64(bitPattern: host) &+ hostOffset &- Int64(bitPattern: start)
    }
}

/// The continuous clock and the host clock, read one right after the other,
/// in nanoseconds.
public struct ClockReading: Equatable, Sendable {
    public var continuous: UInt64
    public var host: UInt64

    public init(continuous: UInt64, host: UInt64) {
        self.continuous = continuous
        self.host = host
    }

    var offset: Int64 { Int64(bitPattern: continuous) &- Int64(bitPattern: host) }
}
