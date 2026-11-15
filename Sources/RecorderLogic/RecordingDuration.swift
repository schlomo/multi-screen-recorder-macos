/// The value of `msr record --duration`: hours, minutes and seconds, each
/// optional but in this order, such as `1h30m`, `45m` or `90s`; a number
/// without a suffix is minutes (the owner, 2026-11-15).
public struct RecordingDuration: Equatable, Sendable, CustomStringConvertible {
    public let seconds: Int

    public init?(_ text: String) {
        if let minutes = Int(text), text.allSatisfy(\.isASCII), text.allSatisfy(\.isNumber) {
            guard minutes > 0 else { return nil }
            seconds = minutes * 60
            return
        }
        guard let match = text.wholeMatch(of: /(?:(\d+)h)?(?:(\d+)m)?(?:(\d+)s)?/),
              match.output.1 != nil || match.output.2 != nil || match.output.3 != nil
        else { return nil }
        let parts = [match.output.1, match.output.2, match.output.3].map { $0.flatMap { Int($0) } ?? 0 }
        let seconds = parts[0] * 3600 + parts[1] * 60 + parts[2]
        guard seconds > 0 else { return nil }
        self.seconds = seconds
    }

    public var description: String { RecordingSummary.elapsed(seconds: Double(seconds)) }

    public var duration: Duration { .seconds(seconds) }
}
