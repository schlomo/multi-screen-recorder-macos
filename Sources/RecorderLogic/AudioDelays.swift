/// A recording's audio delays (D77, D80): each audio input file's against the reference's file
/// (`AudioDelay.Applied`, the reference's own 0), which files the "Audio inputs" guide track mixes
/// (`GuideTrackMembership`, D79) and how much earlier it places each, what `recording.json` lists, and what
/// the status window shows. A new file of an input whose earlier file had an audio delay starts with it,
/// carried over; another reference device starts everything over, the same one's new file keeps it all.
public struct AudioDelays: Sendable {
    public enum Shown: Equatable, Sendable {
        case notInTheGuideTrackYet
        /// Its audio delay, normalized as listed; carried over from the input's earlier file until its own
        /// windows set or confirm it.
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
        /// Each file being written that is not out of the guide track: the seconds it is placed earlier,
        /// its audio delay less the smallest of those mixed; nil while it is not in the guide track yet.
        public var placements: [String: Double?] = [:]
        /// Each file being written with an audio delay, normalized so the earliest of the recording's
        /// files measured against the reference is 0; the reference's own file once that moves it.
        public var delays: [String: Entry] = [:]
    }

    private struct File: Sendable {
        let uid: String
        /// The order the files became known in.
        let order: Int
        var applied: AudioDelay.Applied
        let carriedOverFrom: String?
        var isWriting = true
    }

    private var files: [String: File] = [:]
    private var referenceUID: String?
    private var reference: String?
    private var membership = GuideTrackMembership()
    private var known = 0
    /// What the listed delays are less than the raw ones against the reference: min(0, the smallest).
    private var shift = 0.0

    public init() {}

    /// `writing` maps the audio input files being written to their devices' UIDs, `reference` among them;
    /// `lags` are counted windows' lags against it, the windows ending at `at` seconds of the recording.
    public mutating func update(
        writing: [String: String], reference: String, lags: [String: Double] = [:], at: Double = 0
    ) -> Outcome {
        guard let referenceUID = writing[reference] else { preconditionFailure("the reference \(reference) is not being written") }
        if referenceUID != self.referenceUID {
            files = [:]
            self.referenceUID = referenceUID
        }
        self.reference = reference
        for name in files.keys where writing[name] == nil { files[name]!.isWriting = false }
        for (name, uid) in writing.sorted(by: { $0.key < $1.key }) where files[name] == nil {
            let earlier = files.filter { $0.value.uid == uid && !$0.value.isWriting }.max { $0.value.order < $1.value.order }
            let carried = earlier.flatMap { file in file.value.applied.delay.map { (file.key, $0) } }
            known += 1
            files[name] = File(
                uid: uid, order: known, applied: carried.map { AudioDelay.Applied(carriedOver: $0.1) } ?? AudioDelay.Applied(),
                carriedOverFrom: carried?.0)
        }
        for (name, lag) in lags where name != reference && files[name]?.isWriting == true { files[name]!.applied.add(lag, at: at) }

        let raw = Dictionary(uniqueKeysWithValues: writing.keys.compactMap { name in delay(of: name).map { (name, $0) } })
        let change = membership.update(delays: raw, writing: Set(writing.keys))
        let mixed = raw.filter { !membership.isOut($0.key) }
        let earliestMixed = mixed.values.min() ?? 0
        shift = min(0, files.keys.compactMap(delay(of:)).min() ?? 0)
        var outcome = Outcome(leaving: change.leaving, rejoining: change.rejoining)
        for name in writing.keys where !membership.isOut(name) {
            outcome.placements[name] = .some(raw[name].map { $0 - earliestMixed })
        }
        for (name, delay) in raw where name != reference || shift < 0 {
            let file = files[name]!
            outcome.delays[name] = Entry(delay: delay - shift, carriedOverFrom: file.applied.isCarriedOver ? file.carriedOverFrom : nil)
        }
        return outcome
    }

    /// What the status window shows for a file being written: nothing for one out of the guide track, nor for
    /// the reference's while it is the earliest.
    public func shown(_ name: String) -> Shown? {
        guard let file = files[name], file.isWriting, !membership.isOut(name) else { return nil }
        guard let delay = delay(of: name) else { return .notInTheGuideTrackYet }
        if name == reference, shift == 0 { return nil }
        return .synced(delay - shift, carriedOver: file.applied.isCarriedOver)
    }

    /// The raw audio delay against the reference's file: 0 for a file of the reference device.
    private func delay(of name: String) -> Double? {
        guard let file = files[name] else { return nil }
        return file.uid == referenceUID ? 0 : file.applied.delay
    }
}
