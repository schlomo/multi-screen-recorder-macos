/// Our process's CPU use over a recording, from the CPU time it used,
/// sampled every second: each sample's percent of one core, as Activity
/// Monitor shows it, the newest, the average and the peak. Encoding and
/// capture that run in macOS's own processes (`VTEncoderXPCService`,
/// `replayd`, `WindowServer`) are not in it.
public struct CPUUsage: Sendable {
    private var first: (cpu: Double, wall: Double)?
    private var last: (cpu: Double, wall: Double)?
    /// The newest sample's percent; nil before the second sample.
    public private(set) var currentPercent: Double?
    public private(set) var peakPercent: Double?

    public init() {}

    /// The CPU seconds the process has used so far, read at `wall` seconds.
    public mutating func sample(cpuSeconds: Double, at wall: Double) {
        if first == nil { first = (cpuSeconds, wall) }
        if let last, wall > last.wall {
            let percent = (cpuSeconds - last.cpu) / (wall - last.wall) * 100
            currentPercent = percent
            peakPercent = max(peakPercent ?? percent, percent)
        }
        last = (cpuSeconds, wall)
    }

    /// Over every sample: the CPU time used against the time passed.
    public var averagePercent: Double? {
        guard let first, let last, last.wall > first.wall else { return nil }
        return (last.cpu - first.cpu) / (last.wall - first.wall) * 100
    }

    /// For the recording manifest, to one decimal; nil before two samples.
    public var manifestEntry: RecordingManifest.CPU? {
        guard let averagePercent, let peakPercent else { return nil }
        return RecordingManifest.CPU(
            averagePercent: (averagePercent * 10).rounded() / 10, peakPercent: (peakPercent * 10).rounded() / 10)
    }

    /// "CPU 23 %", as the status window shows it; nil before two samples.
    public var text: String? {
        currentPercent.map { "CPU \(Int($0.rounded())) %" }
    }

    /// The line beside it in the status window and the docs.
    public static let notCounted = "Encoding and capture also run in macOS's own processes (VTEncoderXPCService, replayd, WindowServer), which this number does not include."
}
