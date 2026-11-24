/// A recording's audio delays (D77, D80): each audio input file's against the recording's anchor, the first
/// reference device (`AudioDelay.Applied`, the anchor's own 0), which inputs the "Audio inputs" guide track
/// mixes (`GuideTrackMembership`, D79) and how much earlier it places each, what `recording.json` lists, and
/// what the status window shows. A new file of an input whose earlier file had an audio delay starts with it,
/// carried over. Another reference device re-bases every lag onto the anchor through its own audio delay; one
/// without an audio delay becomes the anchor, and every input starts over.
public struct AudioDelays: Sendable {
    public enum Shown: Equatable, Sendable {
        case notInTheGuideTrackYet
        /// How much earlier the mix places the file; carried over from the input's earlier file until its own
        /// windows set or confirm its audio delay.
        case synced(Double, carriedOver: Bool)
    }

    /// An audio file's audio delay as `recording.json` lists it.
    public struct Entry: Equatable, Sendable {
        public var delay: Double
        public var carriedOverFrom: String?

        public init(delay: Double, carriedOverFrom: String? = nil) {
            self.delay = delay
            self.carriedOverFrom = carriedOverFrom
        }
    }

    public struct Outcome: Equatable, Sendable {
        /// The files that leave the guide track, each with its offset from the staying group's earliest input.
        public var leaving: [String: Double] = [:]
        public var rejoining: Set<String> = []
        /// Each file that is not out of the guide track: the seconds it is placed earlier, its audio delay less
        /// the smallest of those mixed; nil while it is not in the guide track yet.
        public var earlierBy: [String: Double?] = [:]
        /// Each file with an audio delay against the anchor, the anchor's own files left out.
        public var delays: [String: Entry] = [:]
    }

    private struct File: Sendable {
        let uid: String
        /// The order the files became known in.
        let order: Int
        var applied: AudioDelay.Applied
        var carriedOverFrom: String?
    }

    private var files: [String: File] = [:]
    /// Each device's newest file, by the device's UID, while its capture runs.
    private var newest: [String: String] = [:]
    private var anchor: String?
    /// By device UID, so an input out of the guide track stays out with its next file.
    private var membership = GuideTrackMembership()
    private var earlierBy: [String: Double?] = [:]
    private var known = 0

    public init() {}

    /// `files` maps each audio input's newest file, while its capture runs, to its device's UID, `reference`
    /// among them; `lags` are counted windows' lags against it, the windows ending at `at` seconds of the
    /// recording.
    public mutating func update(
        files newest: [String: String], reference: String, lags: [String: Double] = [:], at: Double = 0
    ) -> Outcome {
        guard let referenceUID = newest[reference] else { preconditionFailure("the reference \(reference) is not recorded") }
        for (name, uid) in newest.sorted(by: { $0.key < $1.key }) where files[name] == nil {
            let earlier = files.filter { $0.value.uid == uid }.max { $0.value.order < $1.value.order }
            let carried = earlier.flatMap { file in file.value.applied.delay.map { (file.key, $0) } }
            known += 1
            files[name] = File(
                uid: uid, order: known, applied: carried.map { AudioDelay.Applied(carriedOver: $0.1) } ?? AudioDelay.Applied(),
                carriedOverFrom: carried?.0)
        }
        self.newest = Dictionary(newest.map { ($0.value, $0.key) }) { $1 }
        if anchor == nil { anchor = referenceUID }
        if delay(of: reference) == nil {
            // shortcut: its delay against the old anchor is taken as 0, so every input starts over; measure it
            // against the old anchor first if starting over loses too much.
            anchor = referenceUID
            for name in files.keys {
                files[name]!.applied = AudioDelay.Applied()
                files[name]!.carriedOverFrom = nil
            }
        }
        let base = delay(of: reference)!
        for (name, lag) in lags where name != reference && newest[name] != nil && files[name]?.uid != anchor {
            files[name]!.applied.add(lag + base, at: at)
        }

        let delays = Dictionary(uniqueKeysWithValues: self.newest.compactMap { uid, name in delay(of: name).map { (uid, $0) } })
        let change = membership.update(delays: delays, writing: Set(self.newest.keys))
        let zero = delays.filter { !membership.isOut($0.key) }.values.min() ?? 0
        var outcome = Outcome(
            leaving: Dictionary(uniqueKeysWithValues: change.leaving.map { (self.newest[$0.key]!, $0.value) }),
            rejoining: Set(change.rejoining.map { self.newest[$0]! }))
        for (uid, name) in self.newest where !membership.isOut(uid) {
            outcome.earlierBy[name] = .some(delays[uid].map { $0 - zero })
        }
        earlierBy = outcome.earlierBy
        for (uid, name) in self.newest where uid != anchor {
            guard let delay = delays[uid] else { continue }
            let file = files[name]!
            outcome.delays[name] = Entry(delay: delay, carriedOverFrom: file.applied.isCarriedOver ? file.carriedOverFrom : nil)
        }
        return outcome
    }

    /// What the status window shows for a device's newest file: nothing for one out of the guide track (its
    /// problem line says so) nor for one the mix places at 0.
    public func shown(_ name: String) -> Shown? {
        guard let file = files[name], newest[file.uid] == name, !membership.isOut(file.uid), let placed = earlierBy[name] else { return nil }
        guard let placed else { return .notInTheGuideTrackYet }
        return placed == 0 ? nil : .synced(placed, carriedOver: file.applied.isCarriedOver)
    }

    /// The audio delay against the anchor: 0 for a file of the anchor device.
    private func delay(of name: String) -> Double? {
        guard let file = files[name] else { return nil }
        return file.uid == anchor ? 0 : file.applied.delay
    }
}
