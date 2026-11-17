import Foundation

/// A deterministic random source for the simulations: SplitMix64.
struct SeededRandom: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// A buffer's lateness jitter, in seconds: exponential with a mean of
    /// 3.5 ms, cut at 10 ms, the shape measured on real devices (the
    /// smallest of an interval varies by about 0.04 ms).
    mutating func jitter() -> Double {
        while true {
            let value = -0.0035 * log(1 - Double.random(in: 0..<1, using: &self))
            if value <= 0.010 { return value }
        }
    }
}

/// A simulated audio device: buffers of `bufferSamples` whose timestamps follow
/// the sample count, while the device's clock runs `offset(t)` seconds
/// behind the shared clock at the timestamp t (positive: the device is slow).
struct SimulatedDevice {
    static let sampleRate = 48_000
    var offset: (Double) -> Double
    /// 512, as an `AVCaptureSession` delivers them; 960 for the system audio.
    var bufferSamples = 512
    /// Whether the device delivers no buffers at a timestamp, in seconds.
    var paused: (Double) -> Bool = { _ in false }
    /// Extra lateness of the buffer captured at a shared clock time, in seconds.
    var extraLateness: (Double, inout SeededRandom) -> Double = { _, _ in 0 }
    /// When a buffer that would arrive at a shared clock time is delivered.
    var delivered: (Double) -> Double = { $0 }
    /// How much earlier than its turn the buffer of an index is told to
    /// have arrived, in seconds, as a glitch.
    var early: (Int) -> Double = { _ in 0 }

    struct Buffer {
        var index: Int
        /// Its timestamp and its arrival, nanoseconds on the shared clock.
        var time: Int64
        var arrival: Int64
        /// Its timestamp in seconds.
        var seconds: Double
    }

    /// The buffers up to `seconds`, arriving in order.
    func buffers(for seconds: Double, seed: UInt64 = 1) -> [Buffer] {
        var random = SeededRandom(seed: seed)
        var buffers: [Buffer] = []
        var previous = -Double.infinity
        var index = 0
        while true {
            let time = Double(index * bufferSamples) / Double(Self.sampleRate)
            if time > seconds { return buffers }
            if paused(time) {
                index += 1
                continue
            }
            let captured = time + offset(time)
            let lateness = Double(bufferSamples) / Double(Self.sampleRate) + random.jitter()
                + extraLateness(captured, &random)
            let arrival = max(previous, delivered(captured + lateness))
            previous = arrival
            buffers.append(Buffer(
                index: index, time: Int64(index * bufferSamples) * 1_000_000_000 / Int64(Self.sampleRate),
                arrival: Int64(((arrival - early(index)) * 1e9).rounded()), seconds: time))
            index += 1
        }
    }

    /// A device whose clock wanders ±`amplitude` seconds in a triangle of `period` seconds.
    static func triangle(amplitude: Double, period: Double) -> SimulatedDevice {
        SimulatedDevice(offset: { seconds in
            let phase = (seconds / period).truncatingRemainder(dividingBy: 1)
            let wave = phase < 0.25 ? 4 * phase : phase < 0.75 ? 2 - 4 * phase : 4 * phase - 4
            return amplitude * wave
        })
    }

    /// A device whose clock runs at `ppm` parts per million (negative: slow).
    static func steady(ppm: Double) -> SimulatedDevice {
        SimulatedDevice(offset: { -ppm * 1e-6 * $0 })
    }
}
