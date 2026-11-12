import Foundation

/// How much disk space a recording needs: 1 GB per display per hour at 1080p,
/// scaled by the frame's pixel count. The rate is a starting point, calibrated
/// at the v1 gate.
public enum DiskEstimate {
    public static let bytesPerDisplayHourAt1080p = 1_000_000_000.0
    private static let pixelsAt1080p = Double(FrameSize(width: 1920, height: 1080).pixelCount)

    public static func bytesNeeded(frameSizes: [FrameSize], hours: Double) -> Double {
        frameSizes
            .map { Double($0.pixelCount) / pixelsAt1080p * bytesPerDisplayHourAt1080p * hours }
            .reduce(0, +)
    }

    /// Decimal gigabytes with one digit, as Finder shows them.
    public static func gigabytes(_ bytes: Double) -> String {
        String(format: "%.1f GB", bytes / 1_000_000_000)
    }
}
