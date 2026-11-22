import Foundation

/// Whether a camera's stream still delivers (D74); a camera delivers frames
/// whether its picture changes or not. No first frame within
/// `firstFrameLimit` of the capture's start, an iPhone camera's
/// (`isContinuity`) `continuityFirstFrameLimit`, or no frame for
/// `frameGapLimit` is a failing stream; no frame for `stallLimit` is a
/// stall: the stream may recover by itself, and the file goes on.
public struct CameraFrameWatch: Equatable, Sendable {
    public enum Verdict: Equatable, Sendable {
        case delivering
        case stalled
        case failed(ErrorDetail)
    }

    public var firstFrameLimit: Duration
    public var continuityFirstFrameLimit: Duration
    public var stallLimit: Duration
    public var frameGapLimit: Duration

    public init(
        firstFrameLimit: Duration = RecorderValues.cameraFirstFrameLimit,
        continuityFirstFrameLimit: Duration = RecorderValues.continuityCameraFirstFrameLimit,
        stallLimit: Duration = RecorderValues.cameraStallLimit,
        frameGapLimit: Duration = RecorderValues.cameraFrameGapLimit
    ) {
        self.firstFrameLimit = firstFrameLimit
        self.continuityFirstFrameLimit = continuityFirstFrameLimit
        self.stallLimit = stallLimit
        self.frameGapLimit = frameGapLimit
    }

    /// The stream's state at `now`; times are nanoseconds on the shared clock.
    public func verdict(startedAt: Int64, lastFrameAt: Int64?, now: Int64, isContinuity: Bool) -> Verdict {
        if let lastFrameAt {
            if now - lastFrameAt >= frameGapLimit.nanoseconds {
                return .failed(ErrorDetail(message: "the camera delivered no frame for \(Self.text(frameGapLimit))"))
            }
            return now - lastFrameAt >= stallLimit.nanoseconds ? .stalled : .delivering
        }
        let limit = isContinuity ? continuityFirstFrameLimit : firstFrameLimit
        guard now - startedAt >= limit.nanoseconds else { return .delivering }
        return .failed(ErrorDetail(message: "the camera delivered no frame within \(Self.text(limit)) of its start"))
    }

    /// How often the capture looks.
    public var checkInterval: Duration { min(firstFrameLimit, stallLimit) / 4 }

    public static func text(_ duration: Duration) -> String {
        String(format: "%g s", Double(duration.nanoseconds) / 1e9)
    }
}
