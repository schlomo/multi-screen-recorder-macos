/// Which audio inputs' files the "Audio inputs" guide track mixes (D79, D80), by their audio delays against
/// the reference's file, the reference's own 0. The largest group whose audio delays lie within
/// `RecorderValues.guideTrackSyncLimit` of each other stays; on a tie the group holding the files that stayed
/// before, else the one with the earliest input. A file outside it leaves; a file that left rejoins when its
/// audio delay lies within the group, or when it no longer has one (it is then not in the guide track yet).
public struct GuideTrackMembership: Sendable {
    public struct Change: Equatable, Sendable {
        /// The files that leave, each with its offset from the staying group's earliest input.
        public var leaving: [String: Double] = [:]
        public var rejoining: Set<String> = []

        public init(leaving: [String: Double] = [:], rejoining: Set<String> = []) {
            self.leaving = leaving
            self.rejoining = rejoining
        }
    }

    private var out: Set<String> = []
    private var staying: Set<String> = []
    /// A quarter of a sample at 8 kHz, below the half-sample step of a median: values at the limit stay
    /// together wherever they lie, and a half sample beyond it is apart.
    private static let tolerance = 0.25 / Double(AudioDelay.sampleRate)

    public init() {}

    public func isOut(_ file: String) -> Bool { out.contains(file) }

    /// The files that leave and rejoin now; `delays` are the audio delays of the files being written that
    /// have one, `writing` all files being written: every other file is forgotten.
    public mutating func update(
        delays: [String: Double], writing: Set<String>, limit: Double = RecorderValues.guideTrackSyncLimit
    ) -> Change {
        out.formIntersection(writing)
        let staying = Self.largestGroup(delays, limit: limit, holding: self.staying.subtracting(out).intersection(delays.keys))
        self.staying = staying
        let earliest = staying.compactMap { delays[$0] }.min() ?? 0
        var change = Change()
        for (file, delay) in delays where !staying.contains(file) && !out.contains(file) {
            change.leaving[file] = delay - earliest
        }
        change.rejoining = out.filter { staying.contains($0) || delays[$0] == nil }
        out.formUnion(change.leaving.keys)
        out.subtract(change.rejoining)
        return change
    }

    /// The most values within `limit` of each other; on a tie, the group holding all of `holding`, else the
    /// one that starts earliest.
    static func largestGroup(_ values: [String: Double], limit: Double, holding: Set<String> = []) -> Set<String> {
        let sorted = values.sorted { ($0.value, $0.key) < ($1.value, $1.key) }
        var groups: [Set<String>] = []
        var end = 0
        for start in sorted.indices {
            end = max(end, start)
            while end + 1 < sorted.count, sorted[end + 1].value - sorted[start].value <= limit + tolerance { end += 1 }
            groups.append(Set(sorted[start...end].map(\.key)))
        }
        let largest = groups.filter { $0.count == groups.map(\.count).max() }
        return largest.first { holding.isSubset(of: $0) } ?? largest.first ?? []
    }
}
