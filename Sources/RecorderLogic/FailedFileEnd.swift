import Foundation

/// What a file whose writer failed really holds (D66): its end is its
/// start plus the duration the file itself reports, never the end its
/// writer was last given; what the writer was given and the file does not
/// hold is lost, and said so. All times are seconds from the recording's start.
public struct FailedFileEnd: Equatable, Sendable {
    /// What reading the failed file's duration gave.
    public enum Duration: Equatable, Sendable {
        case seconds(Double)
        case unreadable(ErrorDetail)
    }

    /// The file's end: what it really holds.
    public var end: Double
    /// The end the writer had been given, the time of the failure.
    public var failedAt: Double
    /// The problem's text: what was lost; nil when nothing was.
    public var lost: String?

    public init(start: Double, failedAt: Double, duration: Duration) {
        self.failedAt = failedAt
        switch duration {
        case .seconds(let seconds):
            end = start + seconds
            let lostSeconds = failedAt - end
            lost = lostSeconds > 0.0005
                ? "the file ends at \(Self.text(end)), the writer failed at \(Self.text(failedAt)): \(Self.text(lostSeconds)) of the recording are lost"
                : nil
        case .unreadable(let error):
            end = start
            lost = "the file cannot be read (\(error.text)), so its end is its start, \(Self.text(start)); "
                + "everything up to the failure at \(Self.text(failedAt)) is lost"
        }
    }

    private static func text(_ seconds: Double) -> String { String(format: "%.3f s", seconds) }
}
