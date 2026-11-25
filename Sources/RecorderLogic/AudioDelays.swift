/// A recording's audio delays (D77, D80): each audio input file's against the recording's anchor, the first
/// reference device (`AudioDelay.Applied`, the anchor's files 0), which input is the reference (D85, D89), which
/// inputs the "Audio inputs" guide track
/// mixes (`GuideTrackMembership`, D79) and how much earlier it places each, what `recording.json` lists, and
/// what the status window shows. A new file of an input whose earlier file had an audio delay starts with it,
/// carried over. Another reference device re-bases every lag onto the anchor through its own audio delay; one
/// without an audio delay becomes the anchor, and every input starts over. The anchor's files are those of its
/// device while it is the reference; once the reference moved away, a new file of it is measured like any
/// other (D85).
public struct AudioDelays: Sendable {
    public enum Shown: Equatable, Sendable {
        case notInTheGuideTrackYet
        /// Not in the guide track yet, its file had sound in `audioDelayUnclearMeasurements` measurements
        /// without a counted window.
        case noClearSoundToSync
        /// How much earlier the mix places the file; carried over from the input's earlier file until its own
        /// windows set or confirm its audio delay.
        case synced(Double, carriedOver: Bool)
        /// How much earlier the mix places the anchor's own file, its audio delay 0 by definition.
        case anchor(Double)
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

    /// An audio input's newest file that may be the reference: being written, or the reference's own while
    /// its next file follows (the recorder decides which, D80, D85); `number` is the input's in the window.
    public struct Candidate: Equatable, Sendable {
        public var file: String
        public var uid: String
        public var number: Int

        public init(file: String, uid: String, number: Int) {
            (self.file, self.uid, self.number) = (file, uid, number)
        }
    }

    /// One measurement (D77): each other file's window against the reference's file over their latest common
    /// window.
    public struct Measurement: Sendable {
        public struct Measured: Sendable {
            public var file: String
            public var uid: String
            /// Nil when either side is silent.
            public var window: AudioDelay.Window?
            /// Its own window is not silent.
            public var hasSound: Bool
            public var actionScore: Double
        }

        public var reference: String
        public var referenceUID: String
        public var referenceHasSound: Bool
        public var referenceActionScore: Double
        public var files: [Measured]
    }

    private var files: [String: File] = [:]
    /// Each device's newest file, by the device's UID, while its capture runs.
    private var newest: [String: String] = [:]
    /// The device every audio delay is against: the first input whose file is written, or the new one after a
    /// start-over (D80), as when another input has more action at the first measurement with sound (D89).
    public private(set) var anchor: String?
    /// The anchor's files, its audio delay 0 by definition: those of its device that became known while it was
    /// the reference, as its first file or after another of them (D85).
    private var anchorFiles: Set<String> = []
    /// By device UID, so an input out of the guide track stays out with its next file.
    private var membership = GuideTrackMembership()
    private var earlierBy: [String: Double?] = [:]
    /// How much earlier each device's file was placed, by the device's UID, so a new file is no new join.
    private var placed: [String: Double] = [:]
    /// The reference's file, by name.
    private var referenceFile: String?
    private var known = 0
    /// Each device's action score in the latest measurement (D89).
    private var actionScores: [String: Double] = [:]
    /// The reference was chosen by action score, at the first measurement with sound (D89).
    private var isReferenceChosen = false
    /// The measurements in a row without a counted window against `unsyncedReference` while another input had
    /// sound (D89).
    private var unsynced = 0
    private var unsyncedReference: String?

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
        if anchor == nil { anchor = referenceUID }
        for (name, uid) in newest.sorted(by: { $0.key < $1.key }) where files[name] == nil {
            let earlier = files.filter { $0.value.uid == uid }.max { $0.value.order < $1.value.order }
            known += 1
            // Only after an anchor file, or as the device's first: a file after a measured one carries that over.
            if uid == anchor, referenceUID == anchor, earlier.map({ anchorFiles.contains($0.key) }) ?? true {
                anchorFiles.insert(name)
                files[name] = File(uid: uid, order: known, applied: AudioDelay.Applied())
                continue
            }
            let carried = earlier.flatMap { file in delay(of: file.key).map { (file.key, $0) } }
            if let carried {
                lines.append("\(name): carries over \(AudioDelay.text(carried.1)) from \(carried.0)")
                carriedOver.append(name)
            }
            files[name] = File(
                uid: uid, order: known, applied: carried.map { AudioDelay.Applied(carriedOver: $0.1) } ?? AudioDelay.Applied())
        }
        self.newest = Dictionary(newest.map { ($0.value, $0.key) }) { $1 }
        let previous = referenceFile.flatMap { files[$0] }
        if delay(of: reference) == nil {
            lines.append("reference \(referenceFile ?? "none") → \(reference): it has no audio delay, so it is the new anchor and every input starts over")
            // shortcut: only when no input being written has an audio delay (`reference(among:)` picks such a
            // reference first), the new anchor's audio delay against the old one is unknown and taken as 0, so every input
            // starts over and the entries written so far stay against the old anchor; keep the old anchor's last
            // known delays if a lost anchor proves common.
            anchor = referenceUID
            anchorFiles = [reference]
            for name in files.keys { (files[name]!.applied, files[name]!.unclear) = (AudioDelay.Applied(), 0) }
        }
        // shortcut: a reference other than the anchor is not measured, so its audio delay against the anchor, the
        // base, stays as it was when it became the reference, for as long as its file is written (D85); measure
        // the reference against another input with an audio delay if a drifting reference proves common.
        let base = delay(of: reference)!
        if let previous, previous.uid != referenceUID, !lines.contains(where: { $0.hasPrefix("reference ") }) {
            lines.append("reference \(referenceFile!) → \(reference): lags re-based onto the anchor by \(AudioDelay.text(base))")
        }
        referenceFile = reference
        for name in unclear.sorted() where files[name] != nil {
            files[name]!.unclear += 1
            if files[name]!.unclear == RecorderValues.audioDelayUnclearMeasurements, delay(of: name) == nil {
                lines.append("\(name): no clear sound to sync, \(files[name]!.unclear) measurements with sound and no counted window")
            }
        }
        for (name, lag) in lags.sorted(by: { $0.key < $1.key }) {
            guard name != reference, newest[name] != nil, !anchorFiles.contains(name) else {
                let why = name == reference ? "the reference's own" : newest[name] == nil ? "not a device's newest file" : "the anchor's, always 0"
                lines.append("\(name): lag \(AudioDelay.text(lag)) dropped, \(why)")
                continue
            }
            files[name]!.applied.add(lag + base, at: at, against: referenceUID)
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

    /// Measures each other file's window against the reference's (`others`: each file with its own window and
    /// the reference's over the same span); pure, so the recorder runs it off the main thread.
    public static func measure(
        reference: (file: String, uid: String), others: [(file: String, uid: String, reference: [Float], other: [Float])]
    ) -> Measurement {
        let referenceWindow = others.first?.reference ?? []
        return Measurement(
            reference: reference.file, referenceUID: reference.uid,
            referenceHasSound: !referenceWindow.isEmpty && !AudioDelay.isSilent(referenceWindow),
            referenceActionScore: AudioDelay.actionScore(referenceWindow),
            files: others.map {
                .init(file: $0.file, uid: $0.uid, window: AudioDelay.window(reference: $0.reference, other: $0.other),
                      hasSound: !AudioDelay.isSilent($0.other), actionScore: AudioDelay.actionScore($0.other))
            })
    }

    /// The reference among `candidates` (D80, D85, D89): the reference in use while it is one of them and not
    /// `movingAway`, else among the others the one with the most action in the latest measurement that has an
    /// audio delay; with none such, the one with the most action, which becomes the new anchor. A tie goes to the
    /// lowest number.
    public func reference(among candidates: [Candidate], movingAway: Bool = false) -> Candidate? {
        let current = referenceDevice.flatMap { uid in candidates.first { $0.uid == uid } }
        if !movingAway, let current { return current }
        let others = candidates.filter { $0.uid != referenceDevice }
        return mostAction(others.filter { hasAudioDelay($0.file, device: $0.uid) }) ?? mostAction(others) ?? current
    }

    /// The candidate with the highest action score, unscored ones at 0; within `actionScoreTie` of it, `keeping`
    /// if among them, else the lowest number.
    private func mostAction(_ candidates: [Candidate], keeping: String? = nil) -> Candidate? {
        func score(_ candidate: Candidate) -> Double { actionScores[candidate.uid] ?? 0 }
        guard let top = candidates.map(score).max() else { return nil }
        let tied = candidates.filter { score($0) >= top - RecorderValues.actionScoreTie }.sorted { $0.number < $1.number }
        return tied.first { $0.uid == keeping } ?? tied.first
    }

    /// The audio delays after `measurement`: its counted windows' lags and unclear files, each window's line,
    /// the reference among `candidates` (`files` as for `update`); a measurement against another reference
    /// than the one in use now counts nothing (D80, D85). At the first measurement with sound the input with the
    /// most action becomes the reference, and after `referenceUnsyncedMeasurements` in a row without a counted
    /// window while another input had sound the reference moves, if another has more action (D89); either drops
    /// the measurement's lags.
    public mutating func measured(
        _ measurement: Measurement, files newest: [String: String], candidates: [Candidate], at: Double
    ) -> Outcome {
        var lines: [String] = []
        var lags: [String: Double] = [:]
        var unclear: Set<String> = []
        for measured in measurement.files {
            guard let window = measured.window else {
                lines.append("\(measured.file): not measured, it or the reference \(measurement.reference) is silent")
                continue
            }
            lines.append("\(measured.file): lag \(AudioDelay.text(window.lag)) against \(measurement.reference), "
                + "clarity \(Int(window.clarity.rounded())), " + (window.counts ? "counted" : "not counted"))
            if window.counts { lags[measured.file] = window.lag } else { unclear.insert(measured.file) }
        }
        actionScores = Dictionary(
            measurement.files.map { ($0.uid, $0.actionScore) } + [(measurement.referenceUID, measurement.referenceActionScore)]) { $1 }
        guard var reference = reference(among: candidates) else { return Outcome(lines: lines) }
        let isCurrent = measurement.reference == reference.file
        if !lags.isEmpty, !isCurrent {
            lines.append("counted lags of \(lags.keys.sorted().joined(separator: ", ")) dropped: measured against "
                + "\(measurement.reference), the reference is now \(reference.file)")
        }
        var movesAway = false
        if isCurrent {
            if unsyncedReference != reference.uid { (unsynced, unsyncedReference) = (0, reference.uid) }
            let scores = candidates.filter { actionScores[$0.uid] != nil }.sorted { $0.number < $1.number }
                .map { "\($0.file) \(String(format: "%.1f", actionScores[$0.uid]!)) dB" }.joined(separator: ", ")
            if !isReferenceChosen, measurement.referenceHasSound || measurement.files.contains(where: \.hasSound) {
                isReferenceChosen = true
                if mostAction(candidates.filter { actionScores[$0.uid] != nil }, keeping: reference.uid)?.uid != reference.uid {
                    lines.append("reference \(reference.file) moves: another input has more action at the first measurement with sound; action scores: \(scores)")
                    movesAway = true
                }
            }
            if !movesAway, !lags.isEmpty {
                unsynced = 0
            } else if !movesAway, measurement.files.contains(where: \.hasSound) {
                unsynced += 1
                // Only to more action: a reference with speech that a hum or a loopback cannot sync to stays.
                let hasMoreAction = candidates.contains {
                    $0.uid != reference.uid && (actionScores[$0.uid] ?? 0) > (actionScores[reference.uid] ?? 0) + RecorderValues.actionScoreTie
                }
                if unsynced >= RecorderValues.referenceUnsyncedMeasurements, hasMoreAction {
                    lines.append("reference \(reference.file) moves: no counted window against it in \(unsynced) measurements while "
                        + "another input had sound; action scores: \(scores)")
                    movesAway = true
                }
            }
            if movesAway, let moved = self.reference(among: candidates, movingAway: true) {
                (reference, unsynced, unsyncedReference) = (moved, 0, nil)
            }
        }
        let counts = isCurrent && !movesAway
        var outcome = update(files: newest, reference: reference.file, lags: counts ? lags : [:], unclear: counts ? unclear : [], at: at)
        outcome.lines = lines + outcome.lines
        return outcome
    }

    /// What the status window shows for a device's newest file: nothing for one out of the guide track (its
    /// problem line says so); one the mix places shows it, 0 ms included (D86).
    public func shown(_ name: String) -> Shown? {
        guard let file = files[name], newest[file.uid] == name, !membership.isOut(file.uid), let placed = earlierBy[name] else { return nil }
        guard let placed else {
            return file.unclear >= RecorderValues.audioDelayUnclearMeasurements ? .noClearSoundToSync : .notInTheGuideTrackYet
        }
        return anchorFiles.contains(name) ? .anchor(placed) : .synced(placed, carriedOver: file.applied.isCarriedOver)
    }

    /// The device of the reference in use: it stays the reference while its file is written (D85).
    public var referenceDevice: String? { referenceFile.flatMap { files[$0]?.uid } }

    /// Whether the file has an audio delay, or will carry one over once known, so the recorder can pick another
    /// reference when the reference's file ends (D80, D85). The anchor's files have one, 0.
    public func hasAudioDelay(_ name: String, device uid: String) -> Bool {
        if files[name] != nil { return delay(of: name) != nil }
        if uid == anchor, referenceDevice == anchor { return true }
        return files.filter { $0.value.uid == uid }.max { $0.value.order < $1.value.order }.map { delay(of: $0.key) != nil } ?? false
    }

    /// The file's audio delays with hindsight, for Stop (D80): nil for the anchor's files and a file without own
    /// counted windows, whose live entries stay.
    public func hindsight(of name: String, fileStart: Double) -> [RecordingManifest.AudioFile.Delay]? {
        guard let file = files[name], !anchorFiles.contains(name) else { return nil }
        return file.applied.hindsight(fileStart: fileStart)
    }

    private static func milliseconds(_ seconds: Double) -> String { "\(Int((seconds * 1000).rounded())) ms" }

    /// The audio delay against the anchor: 0 for the anchor's files.
    private func delay(of name: String) -> Double? {
        guard let file = files[name] else { return nil }
        return anchorFiles.contains(name) ? 0 : file.applied.delay
    }
}
