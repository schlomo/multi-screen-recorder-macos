/// The guide track "Microphones" (D31, D45): one mono mix of every recorded
/// audio input channel, their sum divided by √n for n channels, clamped to
/// ±1. Each audio input is placed by its own timestamps and mixed `delay`
/// behind real time, so its buffers have arrived; an audio input with no
/// samples for a stretch is silence there. Times are nanoseconds from t0
/// on the shared clock; positions are samples from t0.
public struct MicrophonesGuideTrackMix: Sendable {
    public let sampleRate: Int
    public let delay: Int64
    /// Every sample before this position is mixed; the next mix starts here.
    public private(set) var mixedUpTo: Int64

    private struct Input: Sendable {
        let channelCount: Int
        /// The sum of the input's channels from `mixedUpTo` on.
        var queued: [Float] = []
    }

    private var inputs: [String: Input] = [:]

    public init(startingAt start: Int64 = 0, sampleRate: Int = RecorderValues.audioSampleRate, delay: Duration = RecorderValues.guideTrackDelay) {
        precondition(sampleRate > 0, "the guide track needs a positive sample rate")
        mixedUpTo = start
        self.sampleRate = sampleRate
        self.delay = delay.nanoseconds
    }

    /// The channels in the mix: n in the sum's √n.
    public var channelCount: Int { inputs.values.reduce(0) { $0 + $1.channelCount } }

    /// An audio input joins the mix under its unique name.
    public mutating func add(input name: String, channelCount: Int) {
        precondition(inputs[name] == nil, "audio input \(name) is already in the guide track")
        precondition(channelCount > 0, "audio input \(name) has no channels")
        inputs[name] = Input(channelCount: channelCount)
    }

    /// An audio input leaves the mix; its samples not mixed yet are dropped.
    public mutating func remove(input name: String) {
        precondition(inputs.removeValue(forKey: name) != nil, "audio input \(name) is not in the guide track")
    }

    /// A buffer of an audio input, one array per channel, its first sample at `time`.
    /// Samples at positions already mixed are dropped.
    public mutating func receive(_ channels: [[Float]], from name: String, at time: Int64) {
        guard var input = inputs[name] else { preconditionFailure("audio input \(name) is not in the guide track") }
        precondition(channels.count == input.channelCount, "audio input \(name) has \(input.channelCount) channels, not \(channels.count)")
        let frameCount = channels.first?.count ?? 0
        let offset = position(of: time) - mixedUpTo
        let end = offset + Int64(frameCount)
        if end > Int64(input.queued.count) {
            input.queued.append(contentsOf: repeatElement(0, count: Int(end) - input.queued.count))
        }
        for frame in max(0, -offset)..<max(0, Int64(frameCount)) {
            input.queued[Int(offset + frame)] = channels.reduce(0) { $0 + $1[Int(frame)] }
        }
        inputs[name] = input
    }

    /// Mixes every sample up to `delay` before `now`, returning them; they
    /// start at the `mixedUpTo` of before the call.
    public mutating func mix(until now: Int64) -> [Float] {
        let end = position(of: now - delay)
        guard end > mixedUpTo else { return [] }
        let count = Int(end - mixedUpTo)
        let scale = channelCount > 0 ? 1 / Float(channelCount).squareRoot() : 0
        var mixed = [Float](repeating: 0, count: count)
        for name in inputs.keys {
            let queued = inputs[name]!.queued
            for index in 0..<min(count, queued.count) { mixed[index] += queued[index] }
            inputs[name]!.queued.removeFirst(min(count, queued.count))
        }
        mixedUpTo = end
        return mixed.map { min(1, max(-1, $0 * scale)) }
    }

    /// The sample position of a time, rounded to the nearest.
    private func position(of time: Int64) -> Int64 {
        let rate = Int64(sampleRate)
        let (seconds, rest) = time.quotientAndRemainder(dividingBy: 1_000_000_000)
        return seconds * rate + (rest * rate + (rest < 0 ? -500_000_000 : 500_000_000)) / 1_000_000_000
    }
}
