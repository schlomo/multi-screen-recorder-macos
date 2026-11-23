import RecorderLogic
import Synchronization

/// Each recorded audio input's latest sound at `AudioDelay.sampleRate`
/// mono, placed on the recording's timeline, for measuring its delay
/// (D77): the audio captures hand their corrected audio in on their own
/// queues, the measurement takes windows out; at most `keptSeconds` per input.
final class AudioDelayFeed: Sendable {
    static let keptSeconds = 12
    private static let kept = keptSeconds * AudioDelay.sampleRate

    private struct Ring {
        /// At `AudioDelay.sampleRate`, from `firstIndex` on.
        var samples: [Float] = []
        /// The timeline index of `samples[0]`, in samples at `AudioDelay.sampleRate` from the recording's start.
        var firstIndex: Int64 = 0
        /// The input samples short of a whole group, at the end.
        var carry: [Float] = []
        /// The input's timeline position, at the audio sample rate, where its next sample is expected.
        var next: Int64 = 0
        var endIndex: Int64 { firstIndex + Int64(samples.count) }
    }

    private let rings = Mutex<[String: Ring]>([:])

    /// An audio input's corrected audio, by its Core Audio UID, `time` nanoseconds from the recording's start.
    func receive(_ channels: [[Float]], from uid: String, at time: Int64) {
        guard let frames = channels.first?.count, frames > 0 else { return }
        let rate = Int64(RecorderValues.audioSampleRate)
        let position = time * rate / 1_000_000_000
        rings.withLock { rings in
            var ring = rings[uid] ?? Ring()
            var channels = channels
            // Not where it was expected, by more than a millisecond: start the group grid over at a whole group.
            if ring.samples.isEmpty || abs(position - ring.next) > rate / 1000 {
                let decimation = Int64(AudioDelay.decimation)
                let index = (position + decimation - 1) / decimation
                let skip = Int(index * decimation - position)
                guard skip < frames else { return }
                channels = channels.map { Array($0[skip...]) }
                ring.carry = []
                if ring.samples.isEmpty || index < ring.firstIndex || index - ring.endIndex > Int64(Self.kept) {
                    ring.samples = []
                    ring.firstIndex = index
                } else if index < ring.endIndex {
                    ring.samples.removeLast(Int(ring.endIndex - index))
                } else {
                    ring.samples += [Float](repeating: 0, count: Int(index - ring.endIndex))
                }
            }
            ring.samples += AudioDelay.downsampled(channels, carry: &ring.carry)
            ring.next = position + Int64(frames)
            // Trims rarely, so most buffers only append.
            if ring.samples.count > 2 * Self.kept {
                let drop = ring.samples.count - Self.kept
                ring.samples.removeFirst(drop)
                ring.firstIndex += Int64(drop)
            }
            rings[uid] = ring
        }
    }

    /// The timeline index right after an input's latest sample; nil before its first.
    func endIndex(of uid: String) -> Int64? {
        rings.withLock { rings in rings[uid].map(\.endIndex) }
    }

    /// An input's `count` samples ending at the timeline index `end`; nil when it does not hold them all.
    func window(of uid: String, endingAt end: Int64, count: Int) -> [Float]? {
        rings.withLock { rings in
            guard let ring = rings[uid], end - Int64(count) >= ring.firstIndex, end <= ring.endIndex else { return nil }
            let from = Int(end - Int64(count) - ring.firstIndex)
            return Array(ring.samples[from..<(from + count)])
        }
    }

    func remove(_ uid: String) {
        _ = rings.withLock { $0.removeValue(forKey: uid) }
    }
}
