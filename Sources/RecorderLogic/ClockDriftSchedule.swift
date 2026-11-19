/// When an audio capture reports its clock drift correction: its status to
/// the recorder at the first buffer and then about once a second. Times
/// are nanoseconds on the shared clock.
public struct ClockDriftSchedule: Sendable {
    public let statusInterval: Int64
    private var lastStatus: Int64?

    public init(statusInterval: Duration = RecorderValues.clockDriftStatusInterval) {
        self.statusInterval = statusInterval.nanoseconds
    }

    /// Whether the status is due for a buffer that arrived at `now`.
    public mutating func due(at now: Int64) -> Bool {
        if let lastStatus, now - lastStatus < statusInterval { return false }
        lastStatus = now
        return true
    }
}

/// When the recorder writes the clock drift lines of all its audio sources
/// to the recording log, as one block: every 10 s from the first check.
public struct ClockDriftDetailSchedule: Sendable {
    public let interval: Int64
    private var lastBlock: Int64?

    public init(interval: Duration = RecorderValues.clockDriftDetailInterval) {
        self.interval = interval.nanoseconds
    }

    public mutating func due(at now: Int64) -> Bool {
        let last = lastBlock ?? now
        lastBlock = last
        guard now - last >= interval else { return false }
        lastBlock = now
        return true
    }
}
