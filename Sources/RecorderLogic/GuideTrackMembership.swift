/// Which audio inputs the "Audio inputs" guide track mixes (D80, D90), from their audio delays alone: every input
/// with one, unless their audio delays lie further apart than `RecorderValues.guideTrackSyncLimit`, the most the
/// mix can shift an input; then the largest set within the limit of each other, on a tie the one holding the
/// reference, else the one with the earliest input. Nothing is remembered from one measurement to the next.
public enum GuideTrackMembership {
    /// A quarter of a sample at 8 kHz, below the half-sample step of a median: values at the limit stay
    /// together wherever they lie, and a half sample beyond it is apart.
    private static let tolerance = 0.25 / Double(AudioDelay.sampleRate)

    /// The inputs mixed among `delays`, the audio delays of the inputs that have one, by input.
    public static func mixed(
        _ delays: [String: Double], reference: String?, limit: Double = RecorderValues.guideTrackSyncLimit
    ) -> Set<String> {
        let sorted = delays.sorted { ($0.value, $0.key) < ($1.value, $1.key) }
        var sets: [Set<String>] = []
        var end = 0
        for start in sorted.indices {
            end = max(end, start)
            while end + 1 < sorted.count, sorted[end + 1].value - sorted[start].value <= limit + tolerance { end += 1 }
            sets.append(Set(sorted[start...end].map(\.key)))
        }
        let largest = sets.filter { $0.count == sets.map(\.count).max() }
        return largest.first { set in reference.map(set.contains) ?? false } ?? largest.first ?? []
    }
}
