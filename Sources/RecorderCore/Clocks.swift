import Darwin
import RecorderLogic

private let timebase: mach_timebase_info_data_t = {
    var info = mach_timebase_info_data_t()
    mach_timebase_info(&info)
    return info
}()

/// Mach ticks in nanoseconds.
func nanoseconds(machTicks ticks: UInt64) -> UInt64 {
    ticks * UInt64(timebase.numer) / UInt64(timebase.denom)
}

/// The continuous clock (`mach_continuous_time`, counts sleep) and the host
/// clock (`mach_absolute_time`, stops in sleep), read one right after the
/// other.
public func readClocks() -> ClockReading {
    let continuous = mach_continuous_time()
    let host = mach_absolute_time()
    return ClockReading(continuous: nanoseconds(machTicks: continuous), host: nanoseconds(machTicks: host))
}

/// The continuous clock now, in nanoseconds.
public func continuousNow() -> UInt64 {
    nanoseconds(machTicks: mach_continuous_time())
}
