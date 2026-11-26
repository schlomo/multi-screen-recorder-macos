/// A recording's audio delays (D77, D80): each audio input file's against the recording's anchor, the first
/// reference device (`AudioDelay.Applied`, the anchor's files 0), which input is the reference (D85, D90), which
/// inputs the "Audio inputs" guide track mixes (`GuideTrackMembership`) and how much earlier it places each, what
/// `recording.json` lists, and what the status window shows. A new file of an input whose earlier file had an
/// audio delay starts with it, carried over. Another reference device with an audio delay re-bases every lag onto
/// the anchor through its own audio delay; one without becomes the anchor, and every input starts over. The
/// anchor's files are those of its device while it is the reference; once the reference is another input, the
/// anchor's file is measured like any other, carrying over its 0 (D90).
public struct AudioDelays: Sendable {
    public enum Shown: Equatable, Sendable {
        case notInTheGuideTrackYet
        /// Synced, but its audio delay lies beyond `guideTrackSyncLimit` of the inputs mixed: the seconds from the
        /// furthest of them (D90).
        case notInTheGuideTrack(apart: Double)
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
        /// Each device's newest file: the seconds the guide track places it earlier, its audio delay less the
        /// smallest of those mixed; nil while it is not mixed.
        public var earlierBy: [String: Double?] = [:]
        /// Each file with an audio delay against the anchor, the anchor's own files at 0.
        public var delays: [String: Entry] = [:]
        /// A file mixed before is placed elsewhere now: the mix crossfades.
        public var isMoved = false
        /// Every decision taken, one line each, for the recording log.
        public var lines: [String] = []
        /// Files whose `recording.json` entries so far are void: every input started over, so they were against an
        /// anchor that no longer is one (D90); the recorder leaves a file that ended its list.
        public var cleared: Set<String> = []
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
    /// window, and, on a reference miss, each pair of other files with sound against each other over the same
    /// windows (D90).
    public struct Measurement: Sendable {
        public struct Measured: Sendable {
            public var file: String
            /// Nil when either side is silent.
            public var window: AudioDelay.Window?
        }

        /// `other`'s window against `reference`'s, two files other than the reference's.
        public struct Pair: Sendable {
            public var reference: String
            public var other: String
            public var window: AudioDelay.Window?
        }

        public var reference: String
        public var files: [Measured]
        public var pairs: [Pair] = []
    }

    private var files: [String: File] = [:]
    /// Each device's newest file, by the device's UID, while its capture runs.
    private var newest: [String: String] = [:]
    /// The device every audio delay is against: the first input whose file is written, or the new one after a
    /// start-over (D80, D90): the reference moved to an input without an audio delay.
    public private(set) var anchor: String?
    /// The anchor's files, its audio delay 0 by definition, while the anchor is the reference: those of its device
    /// that became known while it was, as its first file or after another of them (D85, D90).
    private var anchorFiles: Set<String> = []
    private var earlierBy: [String: Double?] = [:]
    /// Each synced file not mixed: the seconds from the furthest input mixed.
    private var apart: [String: Double] = [:]
    /// How much earlier each device's file was placed, by the device's UID, so a new file is no new join.
    private var placed: [String: Double] = [:]
    /// The reference's file, by name.
    private var referenceFile: String?
    private var known = 0
    /// Each device's counted windows since the anchor became the anchor (D90).
    private var countedWindows: [String: Int] = [:]
    /// The anchor's group, which a reference miss's start-over must outnumber (D90): the anchor and each other
    /// input being written with `audioDelayGroupWindows` counted windows since it became the anchor.
    var anchorGroup: Int {
        1 + newest.keys.filter { $0 != anchor && countedWindows[$0, default: 0] >= RecorderValues.audioDelayGroupWindows }.count
    }

    public init() {}

    /// `files` maps each audio input's newest file, while its capture runs, to its device's UID, `reference`
    /// among them; `lags` are counted windows' lags against it, `unclear` the files whose window had sound but
    /// did not count, the windows ending at `at` seconds of the recording; `isMiss`: a reference miss moved the
    /// reference to `reference`, a start-over whatever its audio delay (D90).
    public mutating func update(
        files newest: [String: String], reference: String, lags: [String: Double] = [:], unclear: Set<String> = [],
        at: Double = 0, isMiss: Bool = false
    ) -> Outcome {
        guard let referenceUID = newest[reference] else { preconditionFailure("the reference \(reference) is not recorded") }
        var lines: [String] = []
        var carriedOver: [String] = []
        var cleared: Set<String> = []
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
            // A miss move starts every input over, so nothing carries over into it.
            let carried = isMiss ? nil : earlier.flatMap { file in delay(of: file.key).map { (file.key, $0) } }
            if let carried {
                lines.append("\(name): carries over \(AudioDelay.text(carried.1)) from \(carried.0)")
                carriedOver.append(name)
            }
            files[name] = File(
                uid: uid, order: known, applied: carried.map { AudioDelay.Applied(carriedOver: $0.1) } ?? AudioDelay.Applied())
        }
        self.newest = Dictionary(newest.map { ($0.value, $0.key) }) { $1 }
        let previous = referenceFile.flatMap { files[$0] }
        if isMiss || delay(of: reference) == nil {
            let why = isMiss ? "moved on a reference miss" : "it has no audio delay"
            lines.append("reference \(referenceFile ?? "none") → \(reference): \(why), so it is the new anchor and every input starts over")
            // shortcut: the new anchor's audio delay against the old one is unknown and taken as 0, so every input
            // starts over and the entries written so far are cleared (D90); keep the old anchor's last known delays
            // if a lost anchor proves common.
            anchor = referenceUID
            anchorFiles = [reference]
            for name in files.keys { (files[name]!.applied, files[name]!.unclear) = (AudioDelay.Applied(), 0) }
            cleared = Set(self.newest.values)
            countedWindows = [:]
        }
        // Once the reference is another input, the anchor's file is measured like any other, carrying over its 0,
        // so a drifting anchor is followed (D90).
        if referenceUID != anchor {
            for name in anchorFiles.sorted() {
                files[name]!.applied = AudioDelay.Applied(carriedOver: 0)
                guard self.newest[files[name]!.uid] == name else { continue }
                lines.append("\(name): the anchor's file, measured against \(reference) from now on, carrying over 0 ms")
            }
            anchorFiles = []
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
            countedWindows[files[name]!.uid, default: 0] += 1
            if let decision = files[name]!.applied.decision { lines.append("\(name): audio delay \(decision)") }
        }

        let delays = Dictionary(uniqueKeysWithValues: self.newest.compactMap { uid, name in delay(of: name).map { (uid, $0) } })
        let mixed = GuideTrackMembership.mixed(delays, reference: referenceUID)
        let mixedDelays = delays.filter { mixed.contains($0.key) }
        let zero = mixedDelays.values.min() ?? 0
        var outcome = Outcome()
        apart = [:]
        for (uid, name) in self.newest {
            outcome.earlierBy[name] = .some(mixed.contains(uid) ? delays[uid].map { $0 - zero } : nil)
            guard let delay = delays[uid], !mixed.contains(uid) else { continue }
            apart[name] = mixedDelays.values.map { abs(delay - $0) }.max()
        }
        earlierBy = outcome.earlierBy
        let zeroName = mixedDelays.min { $0.value < $1.value }.map { self.newest[$0.key]! }
        for name in carriedOver {
            lines.append("\(name): \(apart[name] == nil ? "in the guide track" : "not in the guide track") with the carried-over audio delay")
        }
        for (name, seconds) in apart.sorted(by: { $0.key < $1.key }) {
            lines.append("\(name): not in the guide track, \(Self.milliseconds(seconds)) from the others")
        }
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
        outcome.cleared = cleared
        return outcome
    }

    /// Measures each other file's window against the reference's (`others`: each file with its own window and
    /// the reference's, all over the same span); when no window counts against the reference, also each pair of
    /// the other files with sound against each other (D90). Pure, so the recorder runs it off the main thread.
    public static func measure(reference: String, others: [(file: String, reference: [Float], other: [Float])]) -> Measurement {
        var measurement = Measurement(
            reference: reference,
            files: others.map {
                .init(file: $0.file, window: AudioDelay.window(reference: $0.reference, other: $0.other))
            })
        guard !measurement.files.contains(where: { $0.window?.counts == true }) else { return measurement }
        let sounding = others.filter { !AudioDelay.isSilent($0.other) }
        for (index, first) in sounding.enumerated() {
            for second in sounding[(index + 1)...] {
                measurement.pairs.append(.init(
                    reference: first.file, other: second.file, window: AudioDelay.window(reference: first.other, other: second.other)))
            }
        }
        return measurement
    }

    /// The reference among `candidates` (D80, D85): the reference in use while it is one of them, else the
    /// lowest-numbered one that has an audio delay, its own audio delay turning the lags into ones against the
    /// anchor; with none such, the lowest-numbered one, which becomes the new anchor.
    public func reference(among candidates: [Candidate]) -> Candidate? {
        let byNumber = candidates.sorted { $0.number < $1.number }
        return referenceDevice.flatMap { uid in candidates.first { $0.uid == uid } }
            ?? byNumber.first { hasAudioDelay($0.file, device: $0.uid) } ?? byNumber.first
    }

    /// The audio delays after `measurement`: its counted windows' lags and unclear files, each window's line,
    /// the reference among `candidates` (`files` as for `update`); a measurement against another reference
    /// than the one in use now counts nothing (D80, D85). A reference miss (no counted window against the
    /// reference while another input had sound) moves the reference by the measurement's counted pairs, applying
    /// their lags against it at once (D90): to the input with an audio delay the most others count against, a
    /// re-base that keeps every audio delay; with none such, to the input the most others count against, a
    /// start-over, but only when its group, it and those, outnumbers the anchor's (`anchorGroup`). A tie goes
    /// to the lowest number.
    public mutating func measured(
        _ measurement: Measurement, files newest: [String: String], candidates: [Candidate], at: Double
    ) -> Outcome {
        var lines: [String] = []
        var lags: [String: Double] = [:]
        var unclear: Set<String> = []
        /// The update's outcome, this measurement's lines first.
        func updated(
            reference: String, lags: [String: Double] = [:], unclear: Set<String> = [], isMiss: Bool = false
        ) -> Outcome {
            var outcome = update(files: newest, reference: reference, lags: lags, unclear: unclear, at: at, isMiss: isMiss)
            outcome.lines = lines + outcome.lines
            return outcome
        }
        for measured in measurement.files {
            guard let window = measured.window else {
                lines.append("\(measured.file): not measured, it or the reference \(measurement.reference) is silent")
                continue
            }
            lines.append(Self.line(measured.file, window, against: measurement.reference))
            if window.counts { lags[measured.file] = window.lag } else { unclear.insert(measured.file) }
        }
        guard let reference = reference(among: candidates) else { return Outcome(lines: lines) }
        guard measurement.reference == reference.file else {
            if !lags.isEmpty {
                lines.append("counted lags of \(lags.keys.sorted().joined(separator: ", ")) dropped: measured against "
                    + "\(measurement.reference), the reference is now \(reference.file)")
            }
            return updated(reference: reference.file)
        }
        guard lags.isEmpty else {
            return updated(reference: reference.file, lags: lags, unclear: unclear)
        }
        // Pairs are only of inputs with sound: with none, nothing moves.
        var against: [String: [String: Double]] = [:]
        for pair in measurement.pairs {
            guard let window = pair.window else { continue }
            lines.append(Self.line(pair.other, window, against: pair.reference))
            guard window.counts else { continue }
            against[pair.reference, default: [:]][pair.other] = window.lag
            against[pair.other, default: [:]][pair.reference] = -window.lag
        }
        let proven = candidates.filter { against[$0.file] != nil }
        let synced = proven.filter { hasAudioDelay($0.file, device: $0.uid) }
        let mostCounted = (synced.isEmpty ? proven : synced)
            .max { (against[$0.file]!.count, $1.number) < (against[$1.file]!.count, $0.number) }
        guard let mostCounted, let provenLags = against[mostCounted.file] else {
            return updated(reference: reference.file, unclear: unclear)
        }
        let isStartOver = synced.isEmpty
        guard !isStartOver || provenLags.count + 1 > anchorGroup else {
            lines.append("reference \(reference.file): \(mostCounted.file)'s group of \(provenLags.count + 1) does not outnumber the "
                + "anchor's group of \(anchorGroup): nothing moves")
            return updated(reference: reference.file, unclear: unclear)
        }
        lines.append("reference \(reference.file): no counted window against it while another input had sound; \(mostCounted.file) has "
            + "counted windows of \(provenLags.count) other input\(provenLags.count == 1 ? "" : "s") against it: "
            + provenLags.keys.sorted().joined(separator: ", "))
        return updated(reference: mostCounted.file, lags: provenLags, isMiss: isStartOver)
    }

    private static func line(_ file: String, _ window: AudioDelay.Window, against reference: String) -> String {
        "\(file): lag \(AudioDelay.text(window.lag)) against \(reference), clarity \(Int(window.clarity.rounded())), "
            + (window.counts ? "counted" : "not counted")
    }

    /// What the status window shows for a device's newest file: one the mix places shows it, 0 ms included (D86);
    /// one synced but not mixed how far it lies from the inputs mixed (D90).
    public func shown(_ name: String) -> Shown? {
        guard let file = files[name], newest[file.uid] == name, let placed = earlierBy[name] else { return nil }
        if let apart = apart[name] { return .notInTheGuideTrack(apart: apart) }
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
