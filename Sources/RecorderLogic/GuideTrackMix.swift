/// A guide track's samples (D31, D49), mixed `delay` behind real time so
/// every source's buffers have arrived; each source is placed by its own
/// timestamps, and a source with no samples for a stretch is silence there.
/// "Microphones" is one mono mix of every recorded audio input channel:
/// their sum divided by √n for n channels, clamped to ±1. "System audio"
/// carries the system audio's two channels as they are, clamped. Times are
/// nanoseconds from t0 on the shared clock; positions are samples from t0.
public struct GuideTrackMix: Sendable {
    public let track: GuideTrack
    public let sampleRate: Int
    public let delay: Int64
    /// Every sample before this position is mixed; the next mix starts here.
    public private(set) var mixedUpTo: Int64

    private struct Source: Sendable {
        let channelCount: Int
        /// From `mixedUpTo` on, per output channel.
        var queued: [[Float]]
    }

    private var sources: [String: Source] = [:]

    public init(
        _ track: GuideTrack, startingAt start: Int64 = 0, sampleRate: Int = RecorderValues.audioSampleRate,
        delay: Duration = RecorderValues.guideTrackDelay
    ) {
        precondition(sampleRate > 0, "a guide track needs a positive sample rate")
        self.track = track
        mixedUpTo = start
        self.sampleRate = sampleRate
        self.delay = delay.nanoseconds
    }

    /// The channels in the mix: n in the sum's √n.
    public var channelCount: Int { sources.values.reduce(0) { $0 + $1.channelCount } }

    /// A source joins the mix under its unique name.
    public mutating func add(source name: String, channelCount: Int) {
        precondition(sources[name] == nil, "\(name) is already in the guide track \(track.name)")
        precondition(channelCount > 0, "\(name) has no channels")
        precondition(track == .microphones || channelCount == track.channelCount,
                     "the guide track \(track.name) takes \(track.channelCount) channels, not \(channelCount)")
        sources[name] = Source(channelCount: channelCount, queued: Array(repeating: [], count: track.channelCount))
    }

    /// A source leaves the mix; its samples not mixed yet are dropped.
    public mutating func remove(source name: String) {
        precondition(sources.removeValue(forKey: name) != nil, "\(name) is not in the guide track \(track.name)")
    }

    public func contains(source name: String) -> Bool { sources[name] != nil }

    /// A buffer of a source, one array per channel, its first sample at
    /// `time`. Samples at positions already mixed are dropped.
    public mutating func receive(_ channels: [[Float]], from name: String, at time: Int64) {
        guard var source = sources[name] else { preconditionFailure("\(name) is not in the guide track \(track.name)") }
        precondition(channels.count == source.channelCount, "\(name) has \(source.channelCount) channels, not \(channels.count)")
        let frameCount = channels.first?.count ?? 0
        let offset = position(of: time) - mixedUpTo
        let end = offset + Int64(frameCount)
        guard end > 0 else { return }
        for output in source.queued.indices where end > Int64(source.queued[output].count) {
            source.queued[output].append(contentsOf: repeatElement(0, count: Int(end) - source.queued[output].count))
        }
        for frame in max(0, -offset)..<max(0, Int64(frameCount)) {
            let index = Int(offset + frame)
            if track == .microphones {
                source.queued[0][index] = channels.reduce(0) { $0 + $1[Int(frame)] }
            } else {
                for output in source.queued.indices { source.queued[output][index] = channels[output][Int(frame)] }
            }
        }
        sources[name] = source
    }

    /// Mixes every sample up to `delay` before `now`, one array per output
    /// channel; they start at the `mixedUpTo` of before the call.
    public mutating func mix(until now: Int64) -> [[Float]] {
        mix(upTo: position(of: now - delay))
    }

    /// Mixes every sample before the sample position `end`, as `mix(until:)`
    /// does; at a display file's end, its last mix up to the video's end.
    public mutating func mix(upTo end: Int64) -> [[Float]] {
        guard end > mixedUpTo else { return Array(repeating: [], count: track.channelCount) }
        let count = Int(end - mixedUpTo)
        let scale: Float = switch track {
        case .microphones: channelCount > 0 ? 1 / Float(channelCount).squareRoot() : 0
        case .systemAudio: 1
        }
        var mixed = Array(repeating: [Float](repeating: 0, count: count), count: track.channelCount)
        for name in sources.keys {
            for output in mixed.indices {
                let queued = sources[name]!.queued[output]
                let taken = min(count, queued.count)
                for index in 0..<taken { mixed[output][index] += queued[index] }
                sources[name]!.queued[output].removeFirst(taken)
            }
        }
        mixedUpTo = end
        return mixed.map { $0.map { min(1, max(-1, $0 * scale)) } }
    }

    /// The sample position of a time, rounded to the nearest.
    public func position(of time: Int64) -> Int64 {
        let rate = Int64(sampleRate)
        let (seconds, rest) = time.quotientAndRemainder(dividingBy: 1_000_000_000)
        return seconds * rate + (rest * rate + (rest < 0 ? -500_000_000 : 500_000_000)) / 1_000_000_000
    }
}
