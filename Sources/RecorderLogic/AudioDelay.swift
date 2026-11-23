import Accelerate

/// How much later an audio input's sound arrives than the reference
/// microphone's (D77): measured while recording by cross-correlating the
/// two over windows of `windowSeconds` at `sampleRate` mono, searching
/// ±`searchSeconds`; a window counts only when its match is clear, and a
/// file's delay is the median of its counted windows, once it has
/// `windowsNeeded`.
public enum AudioDelay {
    public static let sampleRate = 8000
    /// The input's samples per measured sample: 48 kHz to 8 kHz.
    public static let decimation = RecorderValues.audioSampleRate / sampleRate
    public static let windowSeconds = 10
    public static let searchSeconds = 1
    /// How often a recording measures.
    public static let interval = Duration.seconds(10)
    /// The peak of |correlation| over its median for a window to count: the
    /// owner's Mac on 2026-11-23 gave 13 to 68 for clear windows, 5 to 9 for unclear ones.
    public static let clarityNeeded: Float = 12
    public static let windowsNeeded = 3
    /// The RMS below which a window is silent and not measured.
    static let silence: Float = 1e-5

    /// One window's measurement.
    public struct Window: Equatable, Sendable {
        /// Seconds the input is later than the reference; negative: earlier.
        public var lag: Double
        /// Peak of |correlation| over its median, across the searched lags.
        public var clarity: Float
        public var counts: Bool { clarity >= AudioDelay.clarityNeeded }
    }

    /// `other`'s lag behind `reference`, two windows of the same timeline
    /// span and length at `sampleRate`; nil when either is silent.
    public static func window(reference: [Float], other: [Float], searchSamples: Int = searchSeconds * sampleRate) -> Window? {
        precondition(reference.count == other.count && !reference.isEmpty, "the windows differ in length or are empty")
        guard rms(reference) >= silence, rms(other) >= silence else { return nil }
        let correlation = crossCorrelation(reference, other)
        let n = correlation.count
        let reach = min(searchSamples, reference.count - 1)
        let lags = Array(-reach...reach)
        let magnitudes = lags.map { abs(correlation[($0 + n) % n]) }
        let best = magnitudes.indices.max { magnitudes[$0] < magnitudes[$1] }!
        let median = Self.median(magnitudes.map(Double.init))!
        guard median > 0 else { return nil }
        return Window(lag: Double(lags[best]) / Double(sampleRate), clarity: Float(Double(magnitudes[best]) / median))
    }

    /// The file's delay: the median of its counted windows' lags, nil with fewer than `windowsNeeded`.
    public static func delay(ofCountedLags lags: [Double]) -> Double? {
        lags.count >= windowsNeeded ? median(lags) : nil
    }

    /// The files' delays as written and shown: the medians against the reference
    /// (whose own file, `reference`, counts as 0), less the smallest of them where it is
    /// below 0, so the earliest measured input is 0 and a delayed reference never moves
    /// the others later; the reference's file is listed when that shifts it.
    public static func normalized(_ delays: [String: Double], reference: String?) -> [String: Double] {
        let shift = min(0, delays.values.min() ?? 0)
        var normalized = delays.mapValues { $0 - shift }
        if let reference, shift < 0 { normalized[reference] = -shift }
        return normalized
    }

    /// Each audio file's counted lags, against the reference's file they were measured with.
    public struct Lags: Sendable {
        private var byFile: [String: (reference: String, lags: [Double])] = [:]

        public init() {}

        /// A counted window's lag against the reference's file `reference`; against another than before, the
        /// file starts again: a new reference, or the same one's new file, as after a reconnect at another latency.
        public mutating func add(_ lag: Double, file: String, reference: String) {
            if byFile[file]?.reference != reference { byFile[file] = (reference, []) }
            byFile[file]?.lags.append(lag)
        }

        /// The reference's file `file` was last measured against.
        public func reference(of file: String) -> String? { byFile[file]?.reference }

        /// The delays of every file measured against the reference's file `reference`, ended ones included,
        /// `normalized`; a file without one is not listed.
        public func delays(reference: String) -> [String: Double] {
            normalized(byFile.compactMapValues { $0.reference == reference ? AudioDelay.delay(ofCountedLags: $0.lags) : nil },
                       reference: reference)
        }
    }

    /// "550 ms late", "30 ms early", "0 ms".
    public static func text(_ delay: Double) -> String {
        let milliseconds = Int((delay * 1000).rounded())
        return milliseconds == 0 ? "0 ms" : "\(abs(milliseconds)) ms \(milliseconds > 0 ? "late" : "early")"
    }

    /// Down-mixes an input's channels to mono and averages each `decimation` samples into one,
    /// carrying the samples short of a whole group over to the next call in `carry`.
    public static func downsampled(_ channels: [[Float]], carry: inout [Float]) -> [Float] {
        guard let frames = channels.first?.count, frames > 0 else { return [] }
        var mono = [Float](repeating: 0, count: frames)
        for channel in channels { vDSP.add(mono, channel, result: &mono) }
        vDSP.multiply(1 / Float(channels.count), mono, result: &mono)
        let all = carry + mono
        let groups = all.count / decimation
        carry = Array(all[(groups * decimation)...])
        return (0..<groups).map { group in vDSP.mean(all[(group * decimation)..<((group + 1) * decimation)]) }
    }

    /// The circular cross-correlation c[k] = Σ a[i]·b[i+k], k from 0 and
    /// negative k at the end, of the two zero-padded to twice their length
    /// rounded up to a power of two, so no lag wraps into another.
    static func crossCorrelation(_ a: [Float], _ b: [Float]) -> [Float] {
        let log2n = vDSP_Length(Int.bitWidth - (2 * a.count - 1).leadingZeroBitCount)
        let n = 1 << Int(log2n)
        let half = n / 2
        guard let fft = vDSP.FFT(log2n: log2n, radix: .radix2, ofType: DSPSplitComplex.self) else {
            preconditionFailure("vDSP cannot set up an FFT of \(n) points")
        }
        func spectrum(_ signal: [Float]) -> (real: [Float], imaginary: [Float]) {
            let padded = signal + [Float](repeating: 0, count: n - signal.count)
            var real = [Float](repeating: 0, count: half), imaginary = [Float](repeating: 0, count: half)
            real.withUnsafeMutableBufferPointer { re in
                imaginary.withUnsafeMutableBufferPointer { im in
                    var split = DSPSplitComplex(realp: re.baseAddress!, imagp: im.baseAddress!)
                    padded.withUnsafeBytes { vDSP_ctoz($0.bindMemory(to: DSPComplex.self).baseAddress!, 2, &split, 1, vDSP_Length(half)) }
                    fft.forward(input: split, output: &split)
                }
            }
            return (real, imaginary)
        }
        let (ar, ai) = spectrum(a), (br, bi) = spectrum(b)
        // conj(A)·B; bin 0 packs the DC in its real part and the Nyquist in its imaginary part.
        var real = (0..<half).map { ar[$0] * br[$0] + ai[$0] * bi[$0] }
        var imaginary = (0..<half).map { ar[$0] * bi[$0] - ai[$0] * br[$0] }
        real[0] = ar[0] * br[0]
        imaginary[0] = ai[0] * bi[0]
        var result = [Float](repeating: 0, count: n)
        real.withUnsafeMutableBufferPointer { re in
            imaginary.withUnsafeMutableBufferPointer { im in
                var split = DSPSplitComplex(realp: re.baseAddress!, imagp: im.baseAddress!)
                fft.inverse(input: split, output: &split)
                result.withUnsafeMutableBytes { vDSP_ztoc(&split, 1, $0.bindMemory(to: DSPComplex.self).baseAddress!, 2, vDSP_Length(half)) }
            }
        }
        return result
    }

    static func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        return sorted.count.isMultiple(of: 2) ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle]
    }

    private static func rms(_ samples: [Float]) -> Float { vDSP.rootMeanSquare(samples) }
}
