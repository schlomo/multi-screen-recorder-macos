/// A camera's dropped frames for the recording log (D74): at most one
/// detail line a second, with the count of each reason since the last
/// line. Times are nanoseconds on any clock that does not go back.
public struct DroppedFrames: Sendable {
    public let interval: Int64
    private var counts: [String: Int] = [:]
    private var lastLineAt: Int64?

    public init(interval: Duration = .seconds(1)) {
        self.interval = interval.nanoseconds
    }

    /// A frame dropped for `reason` at `now`: the line to write, if one is due.
    public mutating func dropped(reason: String, at now: Int64) -> String? {
        counts[reason, default: 0] += 1
        if let lastLineAt, now - lastLineAt < interval { return nil }
        lastLineAt = now
        return line()
    }

    /// At the capture's end: the line for the drops not written yet, if any.
    public mutating func remaining() -> String? {
        counts.isEmpty ? nil : line()
    }

    /// "3 frames dropped: FrameWasLate 2, OutOfBuffers 1".
    private mutating func line() -> String {
        defer { counts = [:] }
        let total = counts.values.reduce(0, +)
        let reasons = counts.sorted { ($1.value, $0.key) < ($0.value, $1.key) }.map { "\($0.key) \($0.value)" }
        return "\(total) frame\(total == 1 ? "" : "s") dropped: " + reasons.joined(separator: ", ")
    }
}
