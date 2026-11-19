import Foundation

/// The known sound the driver plays into a loopback device: a steady
/// 1 kHz tone with a click once a second, so a recording of it can be
/// checked for its level, for silent stretches and, by the clicks, for its
/// timing across files.
public struct TestTone: Sendable {
    public static let frequency = 1000.0
    /// The tone's peak: −20 dBFS, so its level is about −23 dBFS.
    public static let amplitude = 0.1
    /// Added to the tone for the click: far above the tone's peak.
    public static let clickAmplitude = 0.8
    public static let clickSeconds = 0.001

    public let sampleRate: Double

    public init(sampleRate: Double) {
        self.sampleRate = sampleRate
    }

    /// The sample at `index`, counted from the tone's first sample: each
    /// second starts with a click.
    public func sample(at index: Int64) -> Float {
        let rate = Int64(sampleRate.rounded())
        let tone = Self.amplitude * sin(2 * .pi * Self.frequency * Double(index % rate) / sampleRate)
        let click = Double(index % rate) < Self.clickSeconds * sampleRate ? Self.clickAmplitude : 0
        return Float(tone + click)
    }

    /// The tone's level without the clicks, in dBFS: a sine's RMS.
    public static var levelDecibels: Double { SignalAnalysis.decibels(amplitude / 2.0.squareRoot()) }
}

/// What the tests measure in decoded sound.
public enum SignalAnalysis {
    public static func decibels(_ rms: Double) -> Double { 20 * log10(max(rms, 1e-12)) }

    public static func rms<Samples: Collection>(_ samples: Samples) -> Double where Samples.Element == Float {
        guard !samples.isEmpty else { return 0 }
        return (samples.reduce(0.0) { $0 + Double($1) * Double($1) } / Double(samples.count)).squareRoot()
    }

    /// The seconds of each click in `samples`: a click is a run of samples
    /// above half the loudest one, its time the loudest sample in it; runs
    /// closer than half a second belong to one click.
    public static func clicks(_ samples: [Float], sampleRate: Double) -> [Double] {
        guard let loudest = samples.lazy.map(abs).max(), loudest > 0 else { return [] }
        let threshold = loudest / 2
        let gap = Int(sampleRate / 2)
        var clicks: [Double] = []
        var peak: (index: Int, value: Float)?
        for (index, sample) in samples.enumerated() where abs(sample) >= threshold {
            if let current = peak, index - current.index > gap {
                clicks.append(Double(current.index) / sampleRate)
                peak = (index, abs(sample))
            } else if peak == nil || abs(sample) > peak!.value {
                peak = (index, abs(sample))
            }
        }
        if let peak { clicks.append(Double(peak.index) / sampleRate) }
        return clicks
    }

    /// The level in dBFS of the samples outside `margin` seconds around
    /// each click, from `skip` seconds after the start to `skip` before the end.
    public static func toneLevel(_ samples: [Float], sampleRate: Double, clicks: [Double], margin: Double = 0.01,
                                 skip: Double = 0.1) -> Double {
        let near = clicks.map { (Int(($0 - margin) * sampleRate), Int(($0 + margin) * sampleRate)) }
        let first = Int(skip * sampleRate), last = samples.count - Int(skip * sampleRate)
        guard first < last else { return decibels(0) }
        let kept = (first..<last).lazy.filter { index in !near.contains { $0.0 <= index && index <= $0.1 } }.map { samples[$0] }
        return decibels(rms(Array(kept)))
    }

    /// The start, in seconds, of every window of `window` seconds whose
    /// level is below `threshold` dBFS, from `skip` seconds after the start
    /// to `skip` before the end.
    public static func quietWindows(_ samples: [Float], sampleRate: Double, window: Double = 0.1, threshold: Double,
                                    skip: Double = 0.1) -> [Double] {
        let size = Int(window * sampleRate)
        let end = samples.count - Int(skip * sampleRate)
        return stride(from: Int(skip * sampleRate), to: end - size + 1, by: size).compactMap { start in
            decibels(rms(samples[start..<(start + size)])) < threshold ? Double(start) / sampleRate : nil
        }
    }

    /// For each click of `first`, how much later the nearest click of
    /// `second` is, both in seconds of the day; clicks without one within
    /// half a second are left out.
    public static func clickOffsets(_ first: [Double], _ second: [Double]) -> [Double] {
        first.compactMap { click in
            second.min { abs($0 - click) < abs($1 - click) }.flatMap { abs($0 - click) < 0.5 ? $0 - click : nil }
        }
    }
}
