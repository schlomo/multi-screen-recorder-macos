import Foundation

/// The display check (D45): every frame's screen rectangle, as
/// ScreenCaptureKit attaches it, must be its display's bounds. It reads no
/// pixels. A frame that fails is never written. After
/// `RecorderValues.displayCheckFailuresInARow` failing frames in a row, not
/// counting those within the settle time after a display change, the
/// display shows another display's picture.
///
/// That the frame's rectangle and `CGDisplayBounds` are comparable as they
/// are, in points and the same coordinates, is [ASSUMED] (recorder.md).
public struct DisplayCheck: Sendable {
    public enum Verdict: Equatable, Sendable {
        case passes
        case fails
        /// Failed too often in a row: the display file ends.
        case showsAnotherDisplay
    }

    public let failuresInARow: Int
    public let settleTime: Duration
    public let tolerance: Double
    public private(set) var failuresSoFar = 0

    public init(
        failuresInARow: Int = RecorderValues.displayCheckFailuresInARow,
        settleTime: Duration = RecorderValues.settleTime,
        tolerance: Double = RecorderValues.displayCheckTolerancePoints
    ) {
        self.failuresInARow = failuresInARow
        self.settleTime = settleTime
        self.tolerance = tolerance
    }

    /// Judges one frame captured at `time`; `lastDisplayChange` is the time
    /// of the newest display change, all times in nanoseconds from t0.
    public mutating func judge(
        frameRect: ScreenRect, displayBounds: ScreenRect, capturedAt time: Int64, lastDisplayChange: Int64?
    ) -> Verdict {
        if matches(frameRect, displayBounds) {
            failuresSoFar = 0
            return .passes
        }
        if let change = lastDisplayChange, time - change < settleTime.nanoseconds { return .fails }
        failuresSoFar += 1
        return failuresSoFar >= failuresInARow ? .showsAnotherDisplay : .fails
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
