import Foundation

/// How a clock drift and a correction read in the status window and in
/// `--debug`: signed, and zero as `0`, never `+0` or `-0.0`.
enum ClockDriftText {
    /// "-116 ppm", "+34.9 ms", "0 ms".
    static func signed(_ value: Double, decimals: Int, unit: String) -> String {
        let text = String(format: "%+.\(decimals)f", value)
        return Double(text) == 0 ? "0 \(unit)" : "\(text) \(unit)"
    }

    /// "0.04 ms", "0 ms": a size without its sign.
    static func size(_ value: Double, decimals: Int, unit: String) -> String {
        let text = String(format: "%.\(decimals)f", abs(value))
        return Double(text) == 0 ? "0 \(unit)" : "\(text) \(unit)"
    }
}
