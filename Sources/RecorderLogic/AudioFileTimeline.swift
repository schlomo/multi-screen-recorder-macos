/// A gap in an audio source: a buffer's timestamp ran ahead of the position
/// its sample count gives. Every gap becomes the event `audio input gap`
/// with its length (D46).
public struct AudioGap: Equatable, Sendable {
    /// How far the buffer's timestamp ran ahead, in nanoseconds.
    public let length: Int64
    /// Exactly the gap's length in samples: the silence that fills it.
    public let samples: Int64
    /// Filled with silence; otherwise the gap ends the audio file.
    public let isFilled: Bool
}

/// Where one buffer of an audio source goes in its audio file.
public struct AudioBufferPlacement: Equatable, Sendable {
    public enum Action: Equatable, Sendable {
        /// Wholly before the file's first tick: nothing is written.
        case trim
        /// `silence` samples of silence, then the buffer's samples from
        /// `firstSample` on, the first of them at `position`: samples from
        /// the file's first tick. The silence ends at `position`.
        case write(silence: Int64, firstSample: Int, position: Int64)
        /// The gap before the buffer is too long to fill: the file ends
        /// before it, and the buffer is the first of a new file.
        case endFile
    }

    public let action: Action
    public let gap: AudioGap?
}

/// One audio file's place on the tick grid: the file starts at the first
/// tick after its first buffer, the samples before that tick are trimmed,
/// and every sample after it is placed by sample count (D45). A gap up to
/// `longestFilledGap` is filled with silence of exactly its length; a
/// longer one ends the file. In a recording its buffers are the corrected
/// audio of `ClockDriftCorrection`, so the sample count follows the shared
/// clock. Times are nanoseconds from t0 on the shared clock.
public struct AudioFileTimeline: Sendable {
    public let grid: TickGrid
    public let sampleRate: Int
    public let gapTolerance: Int64
    public let longestFilledGap: Int64

    /// The file's first tick, set by its first buffer.
    public private(set) var firstTick: Int64?
    /// The first buffer's timestamp: the sample count counts from it.
    private var origin: Int64 = 0
    /// Samples from the first buffer's start, the filled gaps included.
    private var received: Int64 = 0
    /// Samples from the first buffer's start to the first tick.
    private var trimmed: Int64 = 0

    public init(
        grid: TickGrid = .recording, sampleRate: Int = RecorderValues.audioSampleRate,
        gapTolerance: Duration = RecorderValues.audioGapTolerance,
        longestFilledGap: Duration = RecorderValues.longestFilledAudioGap
    ) {
        precondition(sampleRate > 0, "an audio file needs a positive sample rate")
        self.grid = grid
        self.sampleRate = sampleRate
        self.gapTolerance = gapTolerance.nanoseconds
        self.longestFilledGap = longestFilledGap.nanoseconds
    }

    /// Places a buffer of `sampleCount` samples whose first sample has the
    /// timestamp `time`.
    public mutating func place(bufferAt time: Int64, sampleCount: Int) -> AudioBufferPlacement {
        precondition(sampleCount >= 0, "a buffer holds no negative sample count")
        guard firstTick != nil else {
            let tick = grid.firstTick(atOrAfter: time)
            firstTick = tick
            origin = time
            trimmed = samples(in: grid.time(ofTick: tick) - time)
            return write(sampleCount: sampleCount, silence: 0, gap: nil)
        }
        let ahead = time - (origin + nanoseconds(in: received))
        guard ahead > gapTolerance else {
            return write(sampleCount: sampleCount, silence: 0, gap: nil)
        }
        let isFilled = ahead <= longestFilledGap
        let gap = AudioGap(length: ahead, samples: samples(in: ahead), isFilled: isFilled)
        guard isFilled else { return AudioBufferPlacement(action: .endFile, gap: gap) }
        received += gap.samples
        return write(sampleCount: sampleCount, silence: gap.samples, gap: gap)
    }

    private mutating func write(sampleCount: Int, silence: Int64, gap: AudioGap?) -> AudioBufferPlacement {
        let start = received
        received += Int64(sampleCount)
        guard received > trimmed else { return AudioBufferPlacement(action: .trim, gap: gap) }
        let position = max(start, trimmed) - trimmed
        return AudioBufferPlacement(
            action: .write(silence: min(silence, max(0, start - trimmed)), firstSample: Int(max(0, trimmed - start)), position: position),
            gap: gap)
    }

    /// A sample count as nanoseconds, rounded down, without overflowing on long files.
    private func nanoseconds(in samples: Int64) -> Int64 {
        let rate = Int64(sampleRate)
        return samples / rate * 1_000_000_000 + samples % rate * 1_000_000_000 / rate
    }

    /// A length in nanoseconds as samples, rounded to the nearest.
    private func samples(in nanoseconds: Int64) -> Int64 {
        (nanoseconds * Int64(sampleRate) + 500_000_000) / 1_000_000_000
    }
}
