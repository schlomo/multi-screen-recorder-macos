import Foundation

/// The screen check (D45): every frame's screen rectangle, as
/// ScreenCaptureKit attaches it, must be its screen's bounds. It reads no
/// pixels. A frame that fails is never written. After
/// `RecorderValues.screenCheckFailuresInARow` failing frames in a row, not
/// counting those within the settle time after a screen change, the
/// screen shows another screen's picture.
///
/// That the frame's rectangle and `CGDisplayBounds` are comparable as they
/// are, in points and the same coordinates, is [ASSUMED] (recorder.md).
public struct ScreenCheck: Sendable {
    public enum Verdict: Equatable, Sendable {
        case passes
        case fails
        /// Failed too often in a row: the screen file ends.
        case showsAnotherScreen
    }

    public let failuresInARow: Int
    public let settleTime: Duration
    public let tolerance: Double
    public private(set) var failuresSoFar = 0

    public init(
        failuresInARow: Int = RecorderValues.screenCheckFailuresInARow,
        settleTime: Duration = RecorderValues.settleTime,
        tolerance: Double = RecorderValues.screenCheckTolerancePoints
    ) {
        self.failuresInARow = failuresInARow
        self.settleTime = settleTime
        self.tolerance = tolerance
    }

    /// Judges one frame captured at `time`; `lastScreenChange` is the time
    /// of the newest screen change, all times in nanoseconds from t0.
    public mutating func judge(
        frameRect: ScreenRect, screenBounds: ScreenRect, capturedAt time: Int64, lastScreenChange: Int64?
    ) -> Verdict {
        if matches(frameRect, screenBounds) {
            failuresSoFar = 0
            return .passes
        }
        if let change = lastScreenChange, time - change < settleTime.nanoseconds { return .fails }
        failuresSoFar += 1
        return failuresSoFar >= failuresInARow ? .showsAnotherScreen : .fails
    }

    private func matches(_ lhs: ScreenRect, _ rhs: ScreenRect) -> Bool {
        abs(lhs.x - rhs.x) <= tolerance && abs(lhs.y - rhs.y) <= tolerance
            && abs(lhs.width - rhs.width) <= tolerance && abs(lhs.height - rhs.height) <= tolerance
    }
}

extension Duration {
    /// The whole duration in nanoseconds.
    public var nanoseconds: Int64 {
        let (seconds, attoseconds) = components
        return seconds * 1_000_000_000 + attoseconds / 1_000_000_000
    }
}
