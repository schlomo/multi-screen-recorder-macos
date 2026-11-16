/// When an audio capture reports its clock drift correction: its status to
/// the recorder at the first buffer and then about once a second, and with
/// `--debug` a detail line every 10 s, at a status report. Times are
/// nanoseconds on the shared clock.
public struct ClockDriftSchedule: Sendable {
    public let statusInterval: Int64
    public let debugInterval: Int64
    private var lastStatus: Int64?
    private var lastDebugLine: Int64?

    public init(
        statusInterval: Duration = RecorderValues.clockDriftStatusInterval,
        debugInterval: Duration = RecorderValues.clockDriftDebugInterval
    ) {
        self.statusInterval = statusInterval.nanoseconds
        self.debugInterval = debugInterval.nanoseconds
    }

    /// What is due for a buffer that arrived at `now`.
    public mutating func due(at now: Int64) -> (status: Bool, debugLine: Bool) {
        let lastDebugLine = lastDebugLine ?? now
        self.lastDebugLine = lastDebugLine
        if let lastStatus, now - lastStatus < statusInterval { return (false, false) }
        lastStatus = now
        guard now - lastDebugLine >= debugInterval else { return (true, false) }
        self.lastDebugLine = now
        return (true, true)
    }
}
