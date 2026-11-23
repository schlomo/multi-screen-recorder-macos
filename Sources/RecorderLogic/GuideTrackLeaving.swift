/// The audio files whose audio input leaves the "Audio inputs" guide track (D79): a file whose first
/// counted lag, normalized as the audio delays are (D77), is later than `RecorderValues.guideDelayLimit`.
/// The reference's file and the earliest never leave; a file that left stays out.
public struct GuideTrackLeaving: Sendable {
    private var firstLags: [String: (reference: String, lag: Double)] = [:]
    private var left: Set<String> = []

    public init() {}

    /// A counted window's lag of `file` against the reference's file `reference`: only a file's first
    /// counts, against another reference's file it starts again.
    public mutating func add(_ lag: Double, file: String, reference: String) {
        guard firstLags[file]?.reference != reference else { return }
        firstLags[file] = (reference, lag)
    }

    public func hasLeft(_ file: String) -> Bool { left.contains(file) }

    /// The files that leave now, with their audio delay.
    public mutating func leaving(reference: String, limit: Double = RecorderValues.guideDelayLimit) -> [String: Double] {
        let delays = AudioDelay.normalized(firstLags.compactMapValues { $0.reference == reference ? $0.lag : nil }, reference: reference)
        let leaving = delays.filter { $0.key != reference && $0.value > limit && !left.contains($0.key) }
        left.formUnion(leaving.keys)
        return leaving
    }
}
