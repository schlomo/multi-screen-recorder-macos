import Foundation

/// Whether a camera's stream still delivers (D74): no first frame within
/// `firstFrameLimit` of the capture's start, or no frame for
/// `frameGapLimit`, is a failing stream, not a still picture; a camera
/// delivers frames whether its picture changes or not.
public struct CameraFrameWatch: Equatable, Sendable {
    public var firstFrameLimit: Duration
    public var frameGapLimit: Duration

    public init(
        firstFrameLimit: Duration = RecorderValues.cameraFirstFrameLimit,
        frameGapLimit: Duration = RecorderValues.cameraFrameGapLimit
    ) {
        self.firstFrameLimit = firstFrameLimit
        self.frameGapLimit = frameGapLimit
    }

    /// The failure at `now`, nil while the camera delivers; times are
    /// nanoseconds on the shared clock.
    public func failure(startedAt: Int64, lastFrameAt: Int64?, now: Int64) -> ErrorDetail? {
        if let lastFrameAt {
            guard now - lastFrameAt >= frameGapLimit.nanoseconds else { return nil }
            return ErrorDetail(message: "the camera delivered no frame for \(Self.text(frameGapLimit))")
        }
        guard now - startedAt >= firstFrameLimit.nanoseconds else { return nil }
        return ErrorDetail(message: "the camera delivered no frame within \(Self.text(firstFrameLimit)) of its start")
    }

    /// How often the capture looks.
    public var checkInterval: Duration { min(firstFrameLimit, frameGapLimit) / 4 }

    private static func text(_ duration: Duration) -> String {
        String(format: "%g s", Double(duration.nanoseconds) / 1e9)
    }
}
