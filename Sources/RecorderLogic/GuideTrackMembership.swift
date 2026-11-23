/// Which audio inputs' files the "Audio inputs" guide track mixes (D79). Each file being written has a
/// value against the reference's file: the median of its counted windows once it has 3 (D77), its first
/// counted window's lag before; the reference's own file is 0. The largest group whose values lie within
/// `RecorderValues.guideTrackSyncLimit` of each other stays; on a tie the group holding the files that
/// stayed before, else the one with the earliest input. A file outside it leaves; a file that left rejoins
/// when its median lies within the group.
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

    private var lags: [String: (reference: String, lags: [Double])] = [:]
    private var out: Set<String> = []
    private var staying: Set<String> = []
    /// A quarter of a sample at 8 kHz, below the half-sample step of a median: values at the limit stay
    /// together wherever they lie, and a half sample beyond it is apart.
    private static let tolerance = 0.25 / Double(AudioDelay.sampleRate)

    public init() {}

    /// A counted window's lag of `file` against the reference's file `reference`: against another than
    /// before, its lags start again.
    public mutating func add(_ lag: Double, file: String, reference: String) {
        if lags[file]?.reference != reference { lags[file] = (reference, []) }
        lags[file]?.lags.append(lag)
    }

    public func isOut(_ file: String) -> Bool { out.contains(file) }

    /// The files that leave and rejoin now; `writing` are the files being written, `reference` among them:
    /// every other file is forgotten.
    public mutating func update(
        writing: Set<String>, reference: String, limit: Double = RecorderValues.guideTrackSyncLimit
    ) -> Change {
        lags = lags.filter { writing.contains($0.key) }
        out.formIntersection(writing)
        var values = [reference: 0.0]
        var medians: Set<String> = [reference]
        for (file, measured) in lags where measured.reference == reference && file != reference {
            if let median = AudioDelay.delay(ofCountedLags: measured.lags) {
                values[file] = median
                medians.insert(file)
            } else if let first = measured.lags.first {
                values[file] = first
            }
        }
        let staying = Self.largestGroup(values, limit: limit, holding: self.staying.subtracting(out).intersection(values.keys))
        self.staying = staying
        let earliest = staying.compactMap { values[$0] }.min() ?? 0
        var change = Change()
        for (file, value) in values where !staying.contains(file) && !out.contains(file) {
            change.leaving[file] = value - earliest
        }
        change.rejoining = Set(values.keys.filter { staying.contains($0) && out.contains($0) && medians.contains($0) })
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
