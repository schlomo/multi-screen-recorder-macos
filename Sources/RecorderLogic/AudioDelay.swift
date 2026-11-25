import Accelerate

/// How much later an audio input's sound arrives than the reference's
/// (D77, D80): measured while recording by cross-correlating the
/// two over windows of `windowSeconds` at `sampleRate` mono, searching
/// ±`searchSeconds`; a window counts only when its match is clear, and a
/// file's audio delay follows its counted windows by D80's rules (`Applied`).
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
    /// The counted windows at which an audio delay is set once more, to their median (D80).
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
        // From lag -reach to +reach: the negative lags are at the end.
        let magnitudes = vDSP.absolute(Array(correlation[(n - reach)...]) + correlation[...reach])
        let (best, peak) = vDSP.indexOfMaximum(magnitudes)
        var sorted = magnitudes
        vDSP.sort(&sorted, sortOrder: .ascending)
        let median = Double(sorted[sorted.count / 2])
        guard median > 0 else { return nil }
        return Window(lag: Double(Int(best) - reach) / Double(sampleRate), clarity: Float(Double(peak) / median))
    }

    /// An audio input file's audio delay against the recording's anchor (D80): set by its first counted
    /// window, once more at `windowsNeeded` to their median if that lies more than `audioDelayTolerance`
    /// away, then only when the median of the counted windows of the latest `audioDelayChangeWindowSeconds`,
    /// at least `audioDelayChangeWindows`, does. One carried over from the input's earlier file holds until
    /// the first own counted window confirms it (within the tolerance) or replaces it.
    /// One measured against another reference than before still counts, but Stop's hindsight never merges the
    /// windows of the two (D85).
    public struct Applied: Sendable {
        public private(set) var delay: Double?
        /// Carried over from the input's earlier file and not yet confirmed or replaced by an own window.
        public private(set) var isCarriedOver = false
        /// The own counted windows: when each ended, in seconds of the recording, and its lag. About 58 KB a
        /// file for 10 hours, one every 10 s.
        private var windows: [(at: Double, lag: Double)] = []
        /// When the 60 s rule changed the audio delay, and the value before: places hindsight splits a file.
        private var ruleChanges: [(at: Double, before: Double)] = []
        /// When its windows began to be measured against another reference, and the value before: hindsight's
        /// other places to split a file, never merged across (D85).
        private var referenceChanges: [(at: Double, before: Double)] = []
        /// The device its latest window was measured against.
        private var latestReferenceDevice: String?

        public init() {}

        public init(carriedOver delay: Double) {
            self.delay = delay
            isCarriedOver = true
        }

        /// The rule the latest window's lag was evaluated by and its outcome, or why no rule was, for the
        /// recording log.
        public private(set) var decision: String?

        /// A counted window's lag, the window ending at `at`, measured against the device `reference`; whether
        /// the audio delay changed.
        @discardableResult
        public mutating func add(_ lag: Double, at: Double, against reference: String? = nil) -> Bool {
            if let delay, let before = latestReferenceDevice, let reference, before != reference { referenceChanges.append((at, delay)) }
            if let reference { latestReferenceDevice = reference }
            windows.append((at, lag))
            let wasCarriedOver = isCarriedOver
            isCarriedOver = false
            let latest = windows.filter { $0.at > at - RecorderValues.audioDelayChangeWindowSeconds }.map(\.lag)
            let (candidate, rule): (Double?, String) = switch windows.count {
            case 1: (lag, wasCarriedOver ? "its first counted window on the carried-over" : "set by its first counted window")
            case windowsNeeded: (AudioDelay.median(windows.map(\.lag)), "the median of its first \(windowsNeeded) counted windows")
            case (windowsNeeded + 1)...:
                latest.count >= RecorderValues.audioDelayChangeWindows
                    ? (AudioDelay.median(latest), "the median of its \(latest.count) counted windows of the latest \(Int(RecorderValues.audioDelayChangeWindowSeconds)) s")
                    : (nil, "")
            default: (nil, "")
            }
            guard let candidate else {
                decision = windows.count < windowsNeeded
                    ? "no rule: \(windows.count) of \(windowsNeeded) counted windows for the median"
                    : "no rule: \(latest.count) of \(RecorderValues.audioDelayChangeWindows) counted windows in the latest \(Int(RecorderValues.audioDelayChangeWindowSeconds)) s"
                return false
            }
            if let delay, abs(candidate - delay) <= RecorderValues.audioDelayTolerance {
                decision = "\(rule): kept at \(AudioDelay.text(delay)), \(Self.milliseconds(candidate - delay)) off, within a frame"
                    + (wasCarriedOver ? ", confirmed" : "")
                return false
            }
            decision = delay.map { "\(rule): \(AudioDelay.text($0)) → \(AudioDelay.text(candidate))" + (wasCarriedOver ? ", replaced" : "") }
                ?? "\(rule): \(AudioDelay.text(candidate))"
            if windows.count > windowsNeeded, let delay, referenceChanges.last?.at != at { ruleChanges.append((at, delay)) }
            delay = candidate
            return true
        }

        /// The file's audio delays with hindsight, as `recording.json` lists them at Stop (D80); nil without
        /// own counted windows, when the live entries stay.
        public func hindsight(fileStart: Double) -> [RecordingManifest.AudioFile.Delay]? {
            guard let delay, !windows.isEmpty else { return nil }
            return Self.stretches(
                windows: windows, ruleChanges: ruleChanges, referenceChanges: referenceChanges, current: delay, fileStart: fileStart)
        }

        /// The stretches split at each change of the 60 s rule and of the reference, each with the median of the
        /// windows ending within it, one with fewer than 2 with its live value (the value before the next change,
        /// or `current`); neighbours within a frame merge, but across a change of the reference one within a frame of
        /// the entry before only adds no entry, its windows kept apart (D85); the first at 0.
        static func stretches(
            windows: [(at: Double, lag: Double)], ruleChanges: [(at: Double, before: Double)],
            referenceChanges: [(at: Double, before: Double)] = [], current: Double, fileStart: Double = 0
        ) -> [RecordingManifest.AudioFile.Delay] {
            let splits = (ruleChanges.map { (at: $0.at, before: $0.before, ofReference: false) }
                + referenceChanges.map { (at: $0.at, before: $0.before, ofReference: true) }).sorted { $0.at < $1.at }
            let bounds = splits.map(\.at)
            var lags: [[Double]] = Array(repeating: [], count: bounds.count + 1)
            for window in windows { lags[bounds.firstIndex { window.at < $0 } ?? bounds.count].append(window.lag) }
            let live = splits.map(\.before) + [current]
            // `sealed`: a stretch after a change of reference was dropped into it, so it takes no more windows.
            var merged: [(start: Double, lags: [Double], delay: Double, sealed: Bool)] = []
            for index in lags.indices {
                let delay = lags[index].count >= 2 ? median(lags[index])! : live[index]
                if let last = merged.last, abs(delay - last.delay) <= RecorderValues.audioDelayTolerance {
                    if last.sealed || splits[index - 1].ofReference {
                        merged[merged.count - 1].sealed = true
                    } else {
                        let both = last.lags + lags[index]
                        merged[merged.count - 1] = (last.start, both, both.count >= 2 ? median(both)! : last.delay, false)
                    }
                } else {
                    merged.append((index == 0 ? 0 : max(0, bounds[index - 1] - fileStart), lags[index], delay, false))
                }
            }
            return merged.map { .init(at: ($0.start * 1000).rounded() / 1000, delay: ($0.delay * 10_000).rounded() / 10_000) }
        }

        private static func milliseconds(_ seconds: Double) -> String { String(format: "%.1f ms", abs(seconds) * 1000) }
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
            var padded = [Float](repeating: 0, count: n)
            padded.replaceSubrange(0..<signal.count, with: signal)
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
        var real = vDSP.add(vDSP.multiply(ar, br), vDSP.multiply(ai, bi))
        var imaginary = vDSP.subtract(vDSP.multiply(ar, bi), vDSP.multiply(ai, br))
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

    /// Whether a window is silent, not measured.
    public static func isSilent(_ samples: [Float]) -> Bool { rms(samples) < silence }

    /// How much a window's level moves (D89), at `sampleRate`, over its slices with sound: speech scores high, a
    /// steady hum or noise near 0, however loud; digital silence between sounds does not count.
    public static func actionScore(_ samples: [Float]) -> Double {
        let length = Int(RecorderValues.actionScoreSlice.nanoseconds * Int64(sampleRate) / 1_000_000_000)
        var levels = stride(from: 0, to: samples.count - length + 1, by: length).compactMap { start in
            let rms = vDSP.rootMeanSquare(samples[start..<(start + length)])
            return rms < silence ? nil : 20 * log10(Double(rms))
        }
        guard levels.count >= RecorderValues.actionScoreMinimumSlices else { return 0 }
        levels.sort()
        func level(at percentile: Double) -> Double { levels[Int((Double(levels.count - 1) * percentile).rounded())] }
        return level(at: RecorderValues.actionScoreHighPercentile) - level(at: RecorderValues.actionScoreLowPercentile)
    }
}
