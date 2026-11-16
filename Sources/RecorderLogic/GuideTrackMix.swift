import Foundation

/// A guide track's samples (D31, D49, D52), mixed `delay` behind real time
/// so every source's buffers have arrived; each source is placed by its own
/// timestamps, and a source with no samples for a stretch is silence there.
/// "Microphones" is one mono mix: each recorded audio input averaged to
/// mono, the inputs summed at unity gain, through a soft limiter
/// (`limit`). "System audio" carries the system audio's two channels as
/// they are, clamped to ±1. Times are nanoseconds from t0 on the shared
/// clock; positions are samples from t0. The mix keeps its recent output
/// (`historySeconds`) so a display file's last mix can read it again.
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
    /// The latest mixed output, per output channel, ending at `mixedUpTo`.
    private var recent: [[Float]]
    private let historyLength: Int

    public init(
        _ track: GuideTrack, startingAt start: Int64 = 0, sampleRate: Int = RecorderValues.audioSampleRate,
        delay: Duration = RecorderValues.guideTrackDelay, historySeconds: Int = RecorderValues.guideTrackHistorySeconds
    ) {
        precondition(sampleRate > 0, "a guide track needs a positive sample rate")
        self.track = track
        mixedUpTo = start
        self.sampleRate = sampleRate
        self.delay = delay.nanoseconds
        historyLength = historySeconds * sampleRate
        recent = Array(repeating: [], count: track.channelCount)
    }

    /// Up to this level, the "Microphones" mix passes unchanged: −6 dBFS.
    public static let limiterKnee: Float = 0.5

    /// The soft limiter of "Microphones": unchanged up to the knee, above it
    /// `knee + (1 − knee) · tanh((|x| − knee) / (1 − knee))`, which starts
    /// with slope 1 and approaches ±1 without reaching beyond it.
    public static func limit(_ sample: Float) -> Float {
        let level = abs(sample)
        guard level > limiterKnee else { return sample }
        let headroom = 1 - limiterKnee
        let limited = min(1, limiterKnee + headroom * tanh((level - limiterKnee) / headroom))
        return sample < 0 ? -limited : limited
    }

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
        let average = 1 / Float(channels.count)
        for frame in max(0, -offset)..<max(0, Int64(frameCount)) {
            let index = Int(offset + frame)
            if track == .microphones {
                source.queued[0][index] = channels.reduce(0) { $0 + $1[Int(frame)] } * average
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

    /// Mixes every sample before the sample position `end`, as `mix(until:)` does.
    public mutating func mix(upTo end: Int64) -> [[Float]] {
        guard end > mixedUpTo else { return Array(repeating: [], count: track.channelCount) }
        let count = Int(end - mixedUpTo)
        let mixed = mixed(count: count)
        for name in sources.keys {
            for output in mixed.indices {
                sources[name]!.queued[output].removeFirst(min(count, sources[name]!.queued[output].count))
            }
        }
        for output in mixed.indices {
            recent[output] += mixed[output]
            recent[output].removeFirst(max(0, recent[output].count - historyLength))
        }
        mixedUpTo = end
        return mixed
    }

    /// The mix from sample position `start` up to `end`, without taking
    /// anything: the recent output before `mixedUpTo`, then what the
    /// sources delivered so far; silence where neither reaches.
    public func read(from start: Int64, upTo end: Int64) -> [[Float]] {
        guard end > start else { return Array(repeating: [], count: track.channelCount) }
        let recentStart = mixedUpTo - Int64(recent[0].count)
        let waiting = end > mixedUpTo ? mixed(count: Int(end - mixedUpTo)) : Array(repeating: [], count: track.channelCount)
        return (0..<track.channelCount).map { output in
            (start..<end).map { position -> Float in
                if position >= mixedUpTo { return waiting[output][Int(position - mixedUpTo)] }
                if position >= recentStart { return recent[output][Int(position - recentStart)] }
                return 0
            }
        }
    }

    /// The first `count` samples waiting, mixed, per output channel.
    private func mixed(count: Int) -> [[Float]] {
        var mixed = Array(repeating: [Float](repeating: 0, count: count), count: track.channelCount)
        for source in sources.values {
            for output in mixed.indices {
                let queued = source.queued[output]
                for index in 0..<min(count, queued.count) { mixed[output][index] += queued[index] }
            }
        }
        return switch track {
        case .microphones: mixed.map { $0.map(Self.limit) }
        case .systemAudio: mixed.map { $0.map { min(1, max(-1, $0)) } }
        }
    }

    /// The sample position of a time, rounded to the nearest.
    public func position(of time: Int64) -> Int64 {
        let rate = Int64(sampleRate)
        let (seconds, rest) = time.quotientAndRemainder(dividingBy: 1_000_000_000)
        return seconds * rate + (rest * rate + (rest < 0 ? -500_000_000 : 500_000_000)) / 1_000_000_000
    }
}
