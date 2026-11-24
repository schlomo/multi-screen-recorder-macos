/// A recording's audio delays (D77, D80): each audio input file's against the recording's anchor, the first
/// reference device (`AudioDelay.Applied`, the anchor's own 0), which inputs the "Audio inputs" guide track
/// mixes (`GuideTrackMembership`, D79) and how much earlier it places each, what `recording.json` lists, and
/// what the status window shows. A new file of an input whose earlier file had an audio delay starts with it,
/// carried over. Another reference device re-bases every lag onto the anchor through its own audio delay; one
/// without an audio delay becomes the anchor, and every input starts over.
public struct AudioDelays: Sendable {
    public enum Shown: Equatable, Sendable {
        case notInTheGuideTrackYet
        /// Not in the guide track yet, its file had sound in `audioDelayUnclearMeasurements` measurements
        /// without a counted window.
        case noClearSoundToSync
        /// How much earlier the mix places the file; carried over from the input's earlier file until its own
        /// windows set or confirm its audio delay.
        case synced(Double, carriedOver: Bool)
    }

    /// An audio file's audio delay as `recording.json` lists it: the value alone, how it came about is for
    /// the detail lines.
    public struct Entry: Equatable, Sendable {
        public var delay: Double

        public init(delay: Double) {
            self.delay = delay
        }
    }

    public struct Outcome: Equatable, Sendable {
        /// The files that leave the guide track, each with its offset from the staying group's earliest input.
        public var leaving: [String: Double] = [:]
        public var rejoining: Set<String> = []
        /// Each file that is not out of the guide track: the seconds it is placed earlier, its audio delay less
        /// the smallest of those mixed; nil while it is not in the guide track yet.
        public var earlierBy: [String: Double?] = [:]
        /// Each file with an audio delay against the anchor, the anchor's own files at 0.
        public var delays: [String: Entry] = [:]
        /// A file mixed before is placed elsewhere now: the mix crossfades.
        public var isMoved = false
        /// Every decision taken, one line each, for the recording log.
        public var lines: [String] = []
    }

    private struct File: Sendable {
        let uid: String
        /// The order the files became known in.
        let order: Int
        var applied: AudioDelay.Applied
        /// Measurements whose window had sound but did not count.
        var unclear = 0
    }

    private var files: [String: File] = [:]
    /// Each device's newest file, by the device's UID, while its capture runs.
    private var newest: [String: String] = [:]
    /// The device every audio delay is against: the first input whose file is written, or the new one after a
    /// start-over (D80).
    public private(set) var anchor: String?
    /// By device UID, so an input out of the guide track stays out with its next file.
    private var membership = GuideTrackMembership()
    private var earlierBy: [String: Double?] = [:]
    /// How much earlier each device's file was placed, by the device's UID, so a new file is no new join.
    private var placed: [String: Double] = [:]
    private var reference: String?
    private var known = 0

    public init() {}

    /// `files` maps each audio input's newest file, while its capture runs, to its device's UID, `reference`
    /// among them; `lags` are counted windows' lags against it, `unclear` the files whose window had sound but
    /// did not count, the windows ending at `at` seconds of the recording.
    public mutating func update(
        files newest: [String: String], reference: String, lags: [String: Double] = [:], unclear: Set<String> = [],
        at: Double = 0
    ) -> Outcome {
        guard let referenceUID = newest[reference] else { preconditionFailure("the reference \(reference) is not recorded") }
        var lines: [String] = []
        var carriedOver: [String] = []
        for (name, uid) in newest.sorted(by: { $0.key < $1.key }) where files[name] == nil {
            let earlier = files.filter { $0.value.uid == uid }.max { $0.value.order < $1.value.order }
            let carried = earlier.flatMap { file in file.value.applied.delay.map { (file.key, $0) } }
            if let carried {
                lines.append("\(name): carries over \(AudioDelay.text(carried.1)) from \(carried.0)")
                carriedOver.append(name)
            }
            known += 1
            files[name] = File(
                uid: uid, order: known, applied: carried.map { AudioDelay.Applied(carriedOver: $0.1) } ?? AudioDelay.Applied())
        }
        self.newest = Dictionary(newest.map { ($0.value, $0.key) }) { $1 }
        let previous = self.reference.flatMap { files[$0] }
        if anchor == nil { anchor = referenceUID }
        if delay(of: reference) == nil {
            lines.append("reference \(self.reference ?? "none") → \(reference): it has no audio delay, so it is the new anchor and every input starts over")
            // shortcut: only when no input being written has an audio delay (the recorder picks such a reference
            // first), the new anchor's audio delay against the old one is unknown and taken as 0, so every input
            // starts over and the entries written so far stay against the old anchor; keep the old anchor's last
            // known delays if a lost anchor proves common.
            anchor = referenceUID
            for name in files.keys { (files[name]!.applied, files[name]!.unclear) = (AudioDelay.Applied(), 0) }
        }
        // shortcut: a fallback reference, while the anchor is silent, is not measured, so its audio delay against
        // the anchor, the base, stays as it was when it became the reference; the anchor is the reference again
        // as soon as its file is written, so this only matters for a long silent anchor.
        let base = delay(of: reference)!
        if let previous, previous.uid != referenceUID, !lines.contains(where: { $0.hasPrefix("reference ") }) {
            lines.append("reference \(self.reference!) → \(reference): lags re-based onto the anchor by \(AudioDelay.text(base))")
        }
        self.reference = reference
        for name in unclear.sorted() where files[name] != nil {
            files[name]!.unclear += 1
            if files[name]!.unclear == RecorderValues.audioDelayUnclearMeasurements, delay(of: name) == nil {
                lines.append("\(name): no clear sound to sync, \(files[name]!.unclear) measurements with sound and no counted window")
            }
        }
        for (name, lag) in lags.sorted(by: { $0.key < $1.key }) {
            guard name != reference, newest[name] != nil, files[name]?.uid != anchor else {
                let why = name == reference ? "the reference's own" : newest[name] == nil ? "not a device's newest file" : "the anchor's, always 0"
                lines.append("\(name): lag \(AudioDelay.text(lag)) dropped, \(why)")
                continue
            }
            files[name]!.applied.add(lag + base, at: at)
            if let decision = files[name]!.applied.decision { lines.append("\(name): audio delay \(decision)") }
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
        let zeroName = delays.filter { !membership.isOut($0.key) }.min { $0.value < $1.value }.map { self.newest[$0.key]! }
        for name in carriedOver {
            lines.append("\(name): \(membership.isOut(newest[name]!) ? "out of the guide track" : "in the guide track") with the carried-over audio delay")
        }
        for (name, offset) in outcome.leaving.sorted(by: { $0.key < $1.key }) {
            lines.append("\(name): leaves the guide track, \(AudioDelay.text(offset)) from the staying group's earliest")
        }
        for name in outcome.rejoining.sorted() { lines.append("\(name): rejoins the guide track") }
        var placed: [String: Double] = [:]
        for (uid, name) in self.newest.sorted(by: { $0.value < $1.value }) {
            guard let now = outcome.earlierBy[name] ?? nil else { continue }
            placed[uid] = now
            let zero = "the mix's zero: \(zeroName ?? name)"
            switch self.placed[uid] {
            case nil: lines.append("\(name): joins the guide track placed earlier by \(Self.milliseconds(now)) (\(zero))")
            case let before? where (before * 10_000).rounded() != (now * 10_000).rounded():
                lines.append("\(name): placed earlier by \(Self.milliseconds(before)) → \(Self.milliseconds(now)) (\(zero))")
                outcome.isMoved = true
            default: break
            }
        }
        self.placed = placed
        for (uid, name) in self.newest {
            guard let delay = delays[uid] else { continue }
            outcome.delays[name] = Entry(delay: delay)
        }
        outcome.lines = lines
        return outcome
    }

    /// What the status window shows for a device's newest file: nothing for one out of the guide track (its
    /// problem line says so) nor for one the mix places at 0 ms, rounded.
    public func shown(_ name: String) -> Shown? {
        guard let file = files[name], newest[file.uid] == name, !membership.isOut(file.uid), let placed = earlierBy[name] else { return nil }
        guard let placed else {
            return file.unclear >= RecorderValues.audioDelayUnclearMeasurements ? .noClearSoundToSync : .notInTheGuideTrackYet
        }
        return (placed * 1000).rounded() == 0 ? nil : .synced(placed, carriedOver: file.applied.isCarriedOver)
    }

    /// Whether the file has an audio delay, or will carry one over once known, so the recorder can pick a
    /// fallback reference while the anchor has no file being written (D80). The anchor's files have one, 0.
    public func hasAudioDelay(_ name: String, device uid: String) -> Bool {
        guard uid != anchor else { return true }
        if let file = files[name] { return file.applied.delay != nil }
        return files.values.filter { $0.uid == uid }.max { $0.order < $1.order }?.applied.delay != nil
    }

    /// The file's audio delays with hindsight, for Stop (D80): nil for the anchor's files and a file without own
    /// counted windows, whose live entries stay.
    public func hindsight(of name: String, fileStart: Double) -> [RecordingManifest.AudioFile.Delay]? {
        guard let file = files[name], file.uid != anchor else { return nil }
        return file.applied.hindsight(fileStart: fileStart)
    }

    private static func milliseconds(_ seconds: Double) -> String { "\(Int((seconds * 1000).rounded())) ms" }

    /// The audio delay against the anchor: 0 for a file of the anchor device.
    private func delay(of name: String) -> Double? {
        guard let file = files[name] else { return nil }
        return file.uid == anchor ? 0 : file.applied.delay
    }
}
