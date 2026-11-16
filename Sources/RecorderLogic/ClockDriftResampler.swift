import Accelerate
import Foundation

/// Resamples n channels that share one phase by a ratio near 1 that may
/// change between calls: a polyphase Kaiser-windowed sinc, its phases
/// interpolated linearly. Output sample j sits at the input position x_j;
/// x advances by 1 / (1 + rate) per output sample, from x_0 = 0, so the
/// output has no latency against the input's timestamps (the samples before
/// the first are zeros). The samples the filter needs ahead are held back
/// until they arrive or `flush` pads them with zeros.
public struct ClockDriftResampler: Sendable {
    public let channelCount: Int
    public let sampleRate: Int
    /// Input samples taken so far.
    public private(set) var inputCount: Int64 = 0
    /// Output samples given so far.
    public private(set) var outputCount: Int64 = 0

    private let filter: Filter
    /// Per channel, the input from the absolute index `bufferStart` on.
    private var buffers: [[Float]]
    private var bufferStart: Int64
    /// The next output sample's input position: `whole` + `fraction`.
    private var whole: Int64 = 0
    private var fraction: Double = 0
    private var isFlushed = false

    public init(
        channelCount: Int, sampleRate: Int = RecorderValues.audioSampleRate,
        taps: Int = RecorderValues.clockDriftResamplerTaps, phases: Int = RecorderValues.clockDriftResamplerPhases,
        cutoff: Double = RecorderValues.clockDriftResamplerCutoff, kaiserBeta: Double = RecorderValues.clockDriftResamplerKaiserBeta
    ) {
        precondition(channelCount > 0, "the resampler needs a channel")
        precondition(taps > 0 && taps % 2 == 0, "the resampler needs an even number of taps")
        self.channelCount = channelCount
        self.sampleRate = sampleRate
        filter = Filter(taps: taps, phases: phases, cutoff: cutoff, kaiserBeta: kaiserBeta)
        let before = filter.taps / 2 - 1
        buffers = Array(repeating: [Float](repeating: 0, count: before), count: channelCount)
        bufferStart = -Int64(before)
    }

    /// The correction applied so far, in seconds: the output given against
    /// the next output sample's input position.
    public var applied: Double {
        (Double(outputCount - whole) - fraction) / Double(sampleRate)
    }

    /// Takes `channels` (one array per channel, of equal length) and gives
    /// every output sample whose filter has its input, at `rate`.
    public mutating func process(_ channels: [[Float]], rate: Double) -> [[Float]] {
        precondition(!isFlushed, "a flushed resampler takes no more samples")
        precondition(channels.count == channelCount, "the resampler has \(channelCount) channels, not \(channels.count)")
        let count = channels.first?.count ?? 0
        for channel in 0..<channelCount {
            precondition(channels[channel].count == count, "every channel of a buffer has the same length")
            buffers[channel].append(contentsOf: channels[channel])
        }
        inputCount += Int64(count)
        // The filter reaches `taps / 2` samples ahead of an output's position.
        let output = run(rate: rate, upTo: inputCount - 1 - Int64(filter.taps / 2))
        dropConsumed()
        return output
    }

    /// The end of the input: gives the output samples up to the last input
    /// sample's position, the filter's look-ahead padded with zeros.
    public mutating func flush(rate: Double) -> [[Float]] {
        precondition(!isFlushed, "a resampler is flushed once")
        isFlushed = true
        let pad = [Float](repeating: 0, count: filter.taps / 2)
        for channel in 0..<channelCount { buffers[channel].append(contentsOf: pad) }
        return run(rate: rate, upTo: inputCount - 1)
    }

    /// Output samples while their position's whole part is at most `last`.
    private mutating func run(rate: Double, upTo last: Int64) -> [[Float]] {
        let step = 1 / (1 + rate)
        let half = filter.taps / 2
        // Each output's first tap in the buffers, and its position's fraction.
        var firstTaps: [Int] = []
        var fractions: [Double] = []
        while whole <= last {
            firstTaps.append(Int(whole - bufferStart) - (half - 1))
            fractions.append(fraction)
            fraction += step
            let carry = fraction.rounded(.down)
            whole += Int64(carry)
            fraction -= carry
        }
        outputCount += Int64(firstTaps.count)
        let coefficients = filter.coefficients(at: fractions)
        return buffers.map { Self.convolve($0, coefficients: coefficients, firstTaps: firstTaps, taps: filter.taps) }
    }

    /// Each output sample: the taps from its first tap on, weighted by its coefficients.
    private static func convolve(_ input: [Float], coefficients: [Float], firstTaps: [Int], taps: Int) -> [Float] {
        guard !firstTaps.isEmpty else { return [] }
        return input.withUnsafeBufferPointer { input in
            coefficients.withUnsafeBufferPointer { coefficients in
                [Float](unsafeUninitializedCapacity: firstTaps.count) { output, initialized in
                    let samples = input.baseAddress!
                    let weights = coefficients.baseAddress!
                    for (index, first) in firstTaps.enumerated() {
                        precondition(first >= 0 && first + taps <= input.count, "the resampler reads only the input it holds")
                        vDSP_dotpr(samples + first, 1, weights + index * taps, 1, output.baseAddress! + index, vDSP_Length(taps))
                    }
                    initialized = firstTaps.count
                }
            }
        }
    }

    /// Forgets the input no output sample needs any more.
    private mutating func dropConsumed() {
        let keepFrom = whole - Int64(filter.taps / 2 - 1)
        let drop = Int(keepFrom - bufferStart)
        guard drop > 0 else { return }
        for channel in 0..<channelCount { buffers[channel].removeFirst(drop) }
        bufferStart = keepFrom
    }

    /// The windowed sinc in `phases` steps per sample, as a table.
    private struct Filter: Sendable {
        let taps: Int
        let phases: Int
        /// Row p holds the taps for the fraction p / phases; one row more for interpolating.
        private let table: [Float]

        init(taps: Int, phases: Int, cutoff: Double, kaiserBeta: Double) {
            self.taps = taps
            self.phases = phases
            let half = Double(taps / 2)
            let besselOfBeta = Self.bessel0(kaiserBeta)
            var table = [Float](repeating: 0, count: (phases + 1) * taps)
            for phase in 0...phases {
                let fraction = Double(phase) / Double(phases)
                for tap in 0..<taps {
                    // The distance from the output's position to the tap's input sample.
                    let distance = fraction + (half - 1) - Double(tap)
                    let ratio = distance / half
                    let window = abs(ratio) <= 1 ? Self.bessel0(kaiserBeta * (1 - ratio * ratio).squareRoot()) / besselOfBeta : 0
                    let argument = 2 * cutoff * distance
                    let sinc = argument == 0 ? 1 : sin(Double.pi * argument) / (Double.pi * argument)
                    table[phase * taps + tap] = Float(2 * cutoff * sinc * window)
                }
            }
            self.table = table
        }

        /// The taps for each position `fraction` (0 ≤ fraction < 1) past a
        /// sample, one row of `taps` after the other.
        func coefficients(at fractions: [Double]) -> [Float] {
            table.withUnsafeBufferPointer { table in
                [Float](unsafeUninitializedCapacity: fractions.count * taps) { coefficients, initialized in
                    let rows = table.baseAddress!
                    for (index, fraction) in fractions.enumerated() {
                        let scaled = fraction * Double(phases)
                        let phase = min(phases - 1, max(0, Int(scaled)))
                        var between = Float(scaled - Double(phase))
                        let low = rows + phase * taps
                        // low + (high − low) · between, high the next phase's row.
                        vDSP_vintb(low, 1, low + taps, 1, &between, coefficients.baseAddress! + index * taps, 1, vDSP_Length(taps))
                    }
                    initialized = fractions.count * taps
                }
            }
        }

        /// The modified Bessel function of the first kind, order 0.
        private static func bessel0(_ x: Double) -> Double {
            var sum = 1.0
            var term = 1.0
            var k = 1.0
            while term > sum * 1e-17 {
                term *= (x / (2 * k)) * (x / (2 * k))
                sum += term
                k += 1
            }
            return sum
        }
    }
}
