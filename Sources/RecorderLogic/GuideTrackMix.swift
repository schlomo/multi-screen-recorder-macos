import Foundation

/// A guide track's samples (D31, D49, D52), mixed `delay` behind real time
/// so every source's buffers have arrived; each source is placed by its own
/// timestamps, and a source with no samples for a stretch is silence there.
/// "Audio inputs" is one mono mix: each recorded audio input averaged to
/// mono, the inputs summed at unity gain, through a soft limiter
/// (`limit`) with its ceiling at −1 dBFS. "System audio" carries the system audio's two channels as
/// they are, clamped to ±1. Times are nanoseconds from t0 on the shared
/// clock; positions are samples from t0. A sample that is not finite is
/// silence.
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

    /// Up to this level, the "Audio inputs" mix passes unchanged: −6 dBFS.
    public static let limiterKnee: Float = 0.5

    /// The level the "Audio inputs" mix never exceeds: −1 dBFS, as AAC
    /// decoded a mix limited to 1.0 to 1.14–1.19 at a loud thump (the owner's
    /// Mac, 2026-11-23).
    public static let limiterCeiling = Float(pow(10, -1.0 / 20))

    /// The soft limiter of "Audio inputs": unchanged up to the knee, above it
    /// `knee + (ceiling − knee) · tanh((|x| − knee) / (ceiling − knee))`,
    /// which starts with slope 1 and approaches ±ceiling without reaching
    /// beyond it. A sample that is not finite (NaN, ±infinity) becomes 0.
    public static func limit(_ sample: Float) -> Float {
        guard sample.isFinite else { return 0 }
        let level = abs(sample)
        guard level > limiterKnee else { return sample }
        let headroom = limiterCeiling - limiterKnee
        let limited = min(limiterCeiling, limiterKnee + headroom * tanh((level - limiterKnee) / headroom))
        return sample < 0 ? -limited : limited
    }

    /// A source joins the mix under a name unique in the recording: an audio input's label.
    public mutating func add(source name: String, channelCount: Int) {
        precondition(sources[name] == nil, "\(name) is already in the guide track \(track.name)")
        precondition(channelCount > 0, "\(name) has no channels")
        precondition(track == .audioInputs || channelCount == track.channelCount,
                     "the guide track \(track.name) takes \(track.channelCount) channels, not \(channelCount)")
        sources[name] = Source(channelCount: channelCount, queued: Array(repeating: [], count: track.channelCount))
    }

    /// A source leaves the mix; its samples not mixed yet are dropped.
    public mutating func remove(source name: String) {
        precondition(sources.removeValue(forKey: name) != nil, "\(name) is not in the guide track \(track.name)")
    }

    public func contains(source name: String) -> Bool { sources[name] != nil }

    /// Whether every source has delivered its samples up to the sample
    /// position `end`; true without sources.
    public func hasReceived(upTo end: Int64) -> Bool {
        sources.values.allSatisfy { mixedUpTo + Int64($0.queued.first?.count ?? 0) >= end }
    }

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
            if track == .audioInputs {
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
        mixedUpTo = end
        return mixed
    }

    /// The samples waiting from `mixedUpTo` up to the sample position `end`,
    /// mixed as `mix(upTo:)` would, without taking them: a screen file's
    /// last mix, while other screen files go on with the same mix.
    public func peek(upTo end: Int64) -> (start: Int64, channels: [[Float]]) {
        (mixedUpTo, end > mixedUpTo ? mixed(count: Int(end - mixedUpTo)) : Array(repeating: [], count: track.channelCount))
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
        case .audioInputs: mixed.map { $0.map(Self.limit) }
        case .systemAudio: mixed.map { $0.map { $0.isFinite ? min(1, max(-1, $0)) : 0 } }
        }
    }

    /// The sample position of a time, rounded to the nearest.
    public func position(of time: Int64) -> Int64 {
        let rate = Int64(sampleRate)
        let (seconds, rest) = time.quotientAndRemainder(dividingBy: 1_000_000_000)
        return seconds * rate + (rest * rate + (rest < 0 ? -500_000_000 : 500_000_000)) / 1_000_000_000
    }
}
