/// What a run's scenarios came to, and whether the run passed: only when
/// every scenario asked for ran and passed, nothing stopped the run, and
/// the final restore put the Mac back.
public struct RunTally: Sendable {
    public enum Verdict: Sendable, Equatable {
        /// The line for standard output.
        case passed(String)
        /// The lines for standard error; the run exits non-zero.
        case failed([String])
    }

    public let total: Int
    public private(set) var passedCount = 0
    public private(set) var failedCount = 0
    /// Why the run stopped before its last scenario, if it did.
    public private(set) var stopReason: String?
    /// The steps besides the scenarios that failed, such as the start window.
    public private(set) var failedSteps: [String] = []

    public init(total: Int) {
        self.total = total
    }

    public mutating func passed() { passedCount += 1 }
    public mutating func failed() { failedCount += 1 }
    public mutating func stopped(_ reason: String) { stopReason = reason }
    public mutating func stepFailed(_ reason: String) { failedSteps.append(reason) }

    public func verdict(finalRestoreSucceeded: Bool) -> Verdict {
        let ran = passedCount + failedCount
        var lines = failedSteps.map { "msr-end-to-end: \($0)" }
        if let stopReason {
            lines.append("msr-end-to-end: stopped, \(stopReason); \(ran) of \(total) scenarios ran")
        } else if ran < total {
            lines.append("msr-end-to-end: only \(ran) of \(total) scenarios ran")
        }
        if failedCount > 0 { lines.append("msr-end-to-end: \(failedCount) of \(total) scenarios failed") }
        if !finalRestoreSucceeded { lines.append("msr-end-to-end: the final restore failed; run scripts/end-to-end-test restore") }
        return lines.isEmpty ? .passed("msr-end-to-end: all \(total) scenarios passed") : .failed(lines)
    }
}
