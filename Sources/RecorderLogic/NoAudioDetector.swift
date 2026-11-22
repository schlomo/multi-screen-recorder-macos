/// Where an audio input has no audio (D69): after `threshold` samples of
/// exact zeros its audio file ends, and a new one starts with the first
/// sample that is not zero, so nothing of the sound is cut. A file starts
/// only with sound, so an input with no audio from the start gets no file;
/// zeros shorter than the threshold within a file stay in it. A frame
/// counts as zero when every channel is exactly zero.
public struct NoAudioDetector: Sendable {
    /// What to do with a chunk of corrected audio, in order.
    public enum Step: Equatable, Sendable {
        /// Place these frames of the chunk, after `leadingZeros` zeros: the
        /// zeros let the file's first tick, the first one at or after its
        /// first sample, fall before the sound.
        case place(frames: Range<Int>, leadingZeros: Int)
        /// The zeros reached the threshold at this frame: the file ends there.
        case noAudioStarted(atFrame: Int)
        /// The first frame that is not zero after no audio.
        case noAudioStopped(atFrame: Int)
    }

    public let threshold: Int64
    public let leadingZeros: Int
    public private(set) var isNoAudio = false
    /// The zeros since the last frame that was not zero, or since the start.
    private var zeroRun: Int64 = 0

    public init(threshold: Int64, leadingZeros: Int) {
        precondition(threshold > 0 && leadingZeros >= 0, "no audio needs a positive threshold")
        self.threshold = threshold
        self.leadingZeros = leadingZeros
    }

    /// The recording's: `noAudioTime` at the audio sample rate, and two ticks of leading zeros.
    public static func recording() -> NoAudioDetector {
        let rate = Int64(RecorderValues.audioSampleRate)
        return NoAudioDetector(
            threshold: RecorderValues.noAudioTime.nanoseconds * rate / 1_000_000_000,
            leadingZeros: 2 * RecorderValues.audioSampleRate / RecorderValues.framesPerSecond)
    }

    /// The steps for the next chunk, one array of samples per channel;
    /// `isPlacing` when the capture's current file takes samples.
    public mutating func steps(for channels: [[Float]], isPlacing: Bool) -> [Step] {
        var placing = isPlacing
        var steps: [Step] = []
        let count = channels.first?.count ?? 0
        var start = 0
        while start < count {
            let isZero = Self.isZero(channels, at: start)
            var end = start + 1
            while end < count, Self.isZero(channels, at: end) == isZero { end += 1 }
            if isZero {
                let run = Int64(end - start)
                if !isNoAudio, zeroRun + run >= threshold {
                    let reached = start + Int(threshold - zeroRun)
                    if placing { place(start..<reached, leadingZeros: 0, into: &steps) }
                    steps.append(.noAudioStarted(atFrame: reached))
                    isNoAudio = true
                    placing = false
                } else if placing {
                    place(start..<end, leadingZeros: 0, into: &steps)
                }
                zeroRun += run
            } else {
                if isNoAudio {
                    steps.append(.noAudioStopped(atFrame: start))
                    isNoAudio = false
                }
                place(start..<end, leadingZeros: placing ? 0 : Int(min(Int64(leadingZeros), zeroRun)), into: &steps)
                placing = true
                zeroRun = 0
            }
            start = end
        }
        return steps
    }

    /// Frames that follow the ones placed before them join that step.
    private func place(_ frames: Range<Int>, leadingZeros: Int, into steps: inout [Step]) {
        guard !frames.isEmpty else { return }
        if leadingZeros == 0, case .place(let before, let zeros)? = steps.last, before.upperBound == frames.lowerBound {
            steps[steps.count - 1] = .place(frames: before.lowerBound..<frames.upperBound, leadingZeros: zeros)
        } else {
            steps.append(.place(frames: frames, leadingZeros: leadingZeros))
        }
    }

    private static func isZero(_ channels: [[Float]], at frame: Int) -> Bool {
        channels.allSatisfy { $0[frame] == 0 }
    }
}
