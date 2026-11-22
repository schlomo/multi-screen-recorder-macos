import Accelerate
import Foundation

/// What an audio source's level meter shows (D69): the sample peak since
/// the last reading and the peak hold, as linear sample values, 1 at full scale.
public struct AudioLevel: Equatable, Sendable {
    public var peak: Float
    public var hold: Float

    public init(peak: Float, hold: Float) {
        self.peak = peak
        self.hold = hold
    }

    public static let silent = AudioLevel(peak: 0, hold: 0)

    public var peakDBFS: Double? { Self.decibels(peak) }
    public var holdDBFS: Double? { Self.decibels(hold) }

    /// How much of the bar is filled, from the floor (0) to 0 dBFS (1).
    public var peakFraction: Double { Self.fraction(ofDBFS: peakDBFS) }
    public var holdFraction: Double { Self.fraction(ofDBFS: holdDBFS) }

    public var peakIsRed: Bool { Self.isRed(peakDBFS) }
    public var holdIsRed: Bool { Self.isRed(holdDBFS) }

    /// A sample value in dBFS; nil for an exact zero, which has none.
    public static func decibels(_ value: Float) -> Double? {
        value > 0 ? 20 * log10(Double(value)) : nil
    }

    /// Where a level in dBFS sits on the scale from the floor to 0 dBFS, as a fraction.
    public static func fraction(ofDBFS decibels: Double?) -> Double {
        guard let decibels else { return 0 }
        let floor = RecorderValues.levelMeterFloorDBFS
        return min(1, max(0, (decibels - floor) / -floor))
    }

    private static func isRed(_ decibels: Double?) -> Bool {
        decibels.map { $0 >= RecorderValues.levelMeterRedDBFS } ?? false
    }
}

/// An audio source's level meter (D69): each incoming buffer's sample peak,
/// the largest absolute sample of any channel; a reading gives the highest
/// since the last one, but no older than `peakHold`, and the peak hold, the
/// highest peak, kept for `peakHold` unless a higher one comes. Times are
/// nanoseconds on the shared clock.
public struct AudioLevelMeter: Sendable {
    public let peakHold: Int64
    private var highest: Float = 0
    /// Since when `highest` counts: the last reading, or later while nobody reads.
    private var highestSince: Int64 = 0
    private var hold: Float = 0
    private var holdSince: Int64 = 0

    public init(peakHold: Duration = RecorderValues.levelMeterPeakHold) {
        self.peakHold = peakHold.nanoseconds
    }

    /// One incoming buffer, one array of samples per channel.
    public mutating func measure(_ channels: [[Float]], at now: Int64) {
        let peak = channels.reduce(Float(0)) { max($0, $1.isEmpty ? 0 : vDSP.maximumMagnitude($1)) }
        if now - highestSince >= peakHold {
            highest = 0
            highestSince = now
        }
        highest = max(highest, peak)
        holdPeak(peak, at: now)
    }

    /// The level since the last reading and the peak hold; the next reading starts over.
    public mutating func read(at now: Int64) -> AudioLevel {
        holdPeak(highest, at: now)
        defer {
            highest = 0
            highestSince = now
        }
        return AudioLevel(peak: highest, hold: hold)
    }

    private mutating func holdPeak(_ peak: Float, at now: Int64) {
        guard peak >= hold || now - holdSince >= peakHold else { return }
        hold = peak
        holdSince = now
    }
}
