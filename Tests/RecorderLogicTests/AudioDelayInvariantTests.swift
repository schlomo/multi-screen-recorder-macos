import Accelerate
import Foundation
import Testing
@testable import RecorderLogic

/// Seeded scenarios of 2 to 5 audio inputs over 10 to 20 measurements, driven through the recorder's own calls
/// (`AudioDelays.reference(among:)`, `AudioDelays.measure`, `AudioDelays.measured`, `AudioDelays.update` at a
/// file's start or end), each run checked against the reference rules' invariants (D90).
@Suite struct AudioDelayInvariantTests {
    /// What an input sends in one 10 s window.
    enum Sound: Equatable {
        /// The shared speech, later by the input's lag.
        case speech
        /// The shared speech behind a noise gate: digital zero between the bursts.
        case gatedSpeech
        /// The shared speech from afar under the room's noise.
        case roomSpeech
        /// Speech-like bursts of its own, unrelated to the shared speech: another room, a loopback.
        case unrelated
        /// The same behind a gate.
        case gatedUnrelated
        /// Near-silence: a pause in the room, above digital zero.
        case pause
        case hum
        case noise
        /// Its file ended on no audio; a new one starts when its sound returns.
        case noAudio

        var sharesSpeech: Bool { self == .speech || self == .gatedSpeech || self == .roomSpeech }
    }

    enum Kind: String { case microphone, unrelated, steady }

    struct Input {
        let uid: String
        let number: Int
        let kind: Kind
        let lag: Double
        var sounds: [Sound]
    }

    struct Scenario: CustomStringConvertible {
        var inputs: [Input]
        let measurements: Int
        var description: String {
            inputs.map { "\($0.number) \($0.kind)\($0.kind == .microphone ? " \(Int(($0.lag * 1000).rounded())) ms" : ""): "
                + $0.sounds.map { "\($0)" }.joined(separator: " ") }.joined(separator: "\n")
        }

        init(seed: UInt64) {
            var random = SeededRandom(seed: seed)
            measurements = Int.random(in: 10...20, using: &random)
            let count = Int.random(in: 2...5, using: &random)
            inputs = (1...count).map { number in
                let roll = Double.random(in: 0..<1, using: &random)
                let kind: Kind = number == 2 || roll < 0.5 ? .microphone : roll < 0.7 ? .unrelated : .steady
                let lag = (Double.random(in: -0.35...0.35, using: &random) * 1000).rounded() / 1000
                return Input(uid: "u\(number)", number: number, kind: kind, lag: lag, sounds: [])
            }
            for index in inputs.indices {
                let gated = Bool.random(using: &random)
                var sounds: [Sound] = []
                // Each sound holds for 1 to 6 measurements, so long stretches of shared speech occur.
                while sounds.count < measurements {
                    let roll = Double.random(in: 0..<1, using: &random)
                    let sound: Sound = switch inputs[index].kind {
                    case .microphone:
                        roll < 0.45 ? .speech : roll < 0.55 ? .roomSpeech : roll < 0.65 ? .gatedSpeech : roll < 0.88 ? .pause : .noAudio
                    case .unrelated: roll < 0.7 ? (gated ? .gatedUnrelated : .unrelated) : roll < 0.9 ? .pause : .noAudio
                    case .steady: roll < 0.45 ? .hum : roll < 0.9 ? .noise : .noAudio
                    }
                    sounds += Array(repeating: sound, count: Int.random(in: 1...6, using: &random))
                }
                inputs[index].sounds = Array(sounds.prefix(measurements))
            }
        }

        init(inputs: [Input]) {
            self.inputs = inputs
            measurements = inputs.map(\.sounds.count).min()!
        }
    }

    static let windowCount = AudioDelay.windowSeconds * AudioDelay.sampleRate

    /// White noise in -1...1, made once: every scenario's signals are slices of it, scaled, so a debug build
    /// generates them fast. The speech takes the first `speechRegion` samples, each input's own noise one
    /// `inputRegion` after it, so no two inputs' noise correlates.
    static let noise: [Float] = {
        var random = SeededRandom(seed: 42)
        return (0..<(speechRegion + 5 * inputRegion)).map { _ in Float.random(in: -1...1, using: &random) }
    }()
    static let speechRegion = 22 * windowCount
    static let inputRegion = 4 * windowCount

    /// A window of the input's own noise, scaled.
    static func slice(of input: Input, random: inout SeededRandom, scale: Float) -> [Float] {
        let start = speechRegion + (input.number - 1) * inputRegion + Int.random(in: 0...(inputRegion - windowCount), using: &random)
        return vDSP.multiply(scale, noise[start..<(start + windowCount)])
    }

    /// Loud and quiet stretches of 80 to 400 ms, the quiet ones at `quiet`.
    static func envelope(count: Int, quiet: Float, random: inout SeededRandom) -> [Float] {
        var envelope = [Float](repeating: 0, count: count)
        var index = 0
        var loud = true
        while index < count {
            let end = min(count, index + Int.random(in: 640...3200, using: &random))
            vDSP.fill(&envelope[index..<end], with: loud ? 0.5 : quiet)
            index = end
            loud.toggle()
        }
        return envelope
    }

    /// The shared speech and its envelope, so a gate can follow it.
    static func speech(measurements: Int, seed: UInt64) -> (samples: [Float], envelope: [Float]) {
        var random = SeededRandom(seed: seed &+ 1000)
        let total = (measurements + 2) * windowCount
        let envelope = envelope(count: total, quiet: 0.02, random: &random)
        return (vDSP.multiply(envelope, noise[0..<total]), envelope)
    }

    static func window(
        _ sound: Sound, input: Input, measurement: Int, speech: (samples: [Float], envelope: [Float]), random: inout SeededRandom
    ) -> [Float] {
        let start = (measurement + 1) * windowCount
        let shift = Int((input.lag * Double(AudioDelay.sampleRate)).rounded())
        let span = (start - shift)..<(start - shift + windowCount)
        switch sound {
        case .speech: return vDSP.add(speech.samples[span], slice(of: input, random: &random, scale: 0.002))
        case .gatedSpeech: return zip(speech.samples[span], speech.envelope[span]).map { $1 > 0.1 ? $0 : 0 }
        case .roomSpeech: return vDSP.add(vDSP.multiply(0.3, speech.samples[span]), slice(of: input, random: &random, scale: 0.02))
        case .unrelated, .gatedUnrelated:
            let envelope = envelope(count: windowCount, quiet: sound == .unrelated ? 0.02 : 0, random: &random)
            return vDSP.multiply(envelope, slice(of: input, random: &random, scale: 1))
        case .pause: return slice(of: input, random: &random, scale: 0.0005)
        case .hum:
            let phase = Float(2 * Double.pi * 50 * Double(start) / Double(AudioDelay.sampleRate))
            let step = Float(2 * Double.pi * 50 / Double(AudioDelay.sampleRate))
            return vDSP.multiply(0.3, vForce.sin(vDSP.ramp(withInitialValue: phase, increment: step, count: windowCount)))
        case .noise: return slice(of: input, random: &random, scale: 0.3)
        case .noAudio: return [Float](repeating: 0, count: windowCount)
        }
    }

    /// One measurement's state, as the invariants see it, with the same measurement without pairs beside it
    /// (`main`: the same calls, the measurement's pairs left out, so the reference never moves for lack of sync).
    struct Step {
        /// The device measured against, and the reference after the measurement.
        let measuredAgainst: String
        let reference: String?
        let anchor: String?
        let movedBySound: Bool
        /// The devices in a pair whose window counted in this measurement.
        let counted: Set<String>
        /// A file started before this measurement.
        let fileStarted: Bool
        /// The anchor's group before this measurement (`AudioDelays.anchorGroup`).
        let anchorGroupBefore: Int
        /// The audio delays before this measurement, after any file change.
        let delaysBefore: [String: Double]
        /// The input the reference moved to for lack of sync and its group, it and the inputs counted against it.
        let movedTo: (uid: String, group: Int)?
        let delays: [String: Double]
        let writing: Set<String>
        let mixed: Set<String>
        /// A window against the reference counted.
        let countedAgainstTheReference: Bool
        /// Each file change's re-base before this measurement: the audio delays before and after it.
        let rebases: [(before: [String: Double], after: [String: Double])]
        /// Each start-over before or in this measurement: the files it cleared and those being written.
        let startOvers: [(cleared: Set<String>, writing: Set<String>)]
        let lines: [String]
        let mainDelays: [String: Double]
        let mainAnchor: String?
    }

    /// One rule set's state through a run.
    private struct Run {
        var delays = AudioDelays()
        var latest: [String: Double] = [:]
        let measuresPairs: Bool
    }

    /// Runs the scenario as the recorder does, under the rules and, beside them, without pairs; `check` sees each
    /// measurement's outcome. `windows` gives an input's window in a measurement, by default its `Sound`.
    static func run(
        _ scenario: Scenario, seed: UInt64, windows custom: ((Int, Input) -> [Float])? = nil, check: (Int, Step, Step?) -> Void
    ) async {
        var random = SeededRandom(seed: seed &+ 2000)
        let speech = speech(measurements: scenario.measurements, seed: seed)
        var runs = [Run(measuresPairs: true), Run(measuresPairs: false)]
        var fileNumber: [String: Int] = [:]
        var newest: [String: String] = [:]
        var writing: Set<String> = []
        var rebases: [(before: [String: Double], after: [String: Double])] = []
        var startOvers: [(cleared: Set<String>, writing: Set<String>)] = []
        func noteStartOver(_ outcome: AudioDelays.Outcome) {
            guard outcome.lines.contains(where: { $0.hasSuffix("every input starts over") }) else { return }
            startOvers.append((outcome.cleared, Set(newest.keys)))
        }
        var fileLines: [String] = []
        func file(_ uid: String) -> String { "\(uid)-\(fileNumber[uid]!).mov" }
        func candidates() -> [AudioDelays.Candidate] {
            scenario.inputs.filter { writing.contains($0.uid) }.map { .init(file: file($0.uid), uid: $0.uid, number: $0.number) }
        }
        func fileChanged() {
            for index in runs.indices {
                guard let reference = runs[index].delays.reference(among: candidates()) else { continue }
                let outcome = runs[index].delays.update(files: newest, reference: reference.file)
                let after = outcome.delays.mapValues(\.delay)
                if index == 0 {
                    noteStartOver(outcome)
                    fileLines += outcome.lines
                    if outcome.lines.contains(where: { $0.contains(": lags re-based onto the anchor by ") }) {
                        rebases.append((runs[index].latest, after))
                    }
                }
                runs[index].latest = after
            }
        }
        // Every file starts at once, the first input's first (the recorder's anchor at first).
        for input in scenario.inputs {
            fileNumber[input.uid] = 1
            newest[file(input.uid)] = input.uid
            writing.insert(input.uid)
            fileChanged()
        }
        var previous: Step?
        for measurement in 0..<scenario.measurements {
            // Each measurement is up to a few hundred milliseconds of CPU: yield, so a run holds a thread of the
            // cooperative pool no longer than that, where the async timing tests in the same process resume
            // (docs/troubleshooting.md).
            await Task.yield()
            var fileStarted = false
            (rebases, fileLines, startOvers) = ([], [], [])
            for input in scenario.inputs {
                let silentNow = input.sounds[measurement] == .noAudio
                if silentNow, writing.contains(input.uid) {
                    writing.remove(input.uid)
                    fileChanged()
                } else if !silentNow, !writing.contains(input.uid) {
                    newest.removeValue(forKey: file(input.uid))
                    fileNumber[input.uid]! += 1
                    newest[file(input.uid)] = input.uid
                    writing.insert(input.uid)
                    fileStarted = true
                    fileChanged()
                }
            }
            let byUID = Dictionary(uniqueKeysWithValues: scenario.inputs.map { ($0.uid, $0) })
            let windows = Dictionary(uniqueKeysWithValues: candidates().map { candidate in
                let input = byUID[candidate.uid]!
                return (candidate.uid, custom?(measurement, input)
                    ?? window(input.sounds[measurement], input: input, measurement: measurement, speech: speech, random: &random))
            })
            let (anchorGroupBefore, delaysBefore) = (runs[0].delays.anchorGroup, runs[0].latest)
            var outcomes: [(reference: String, measurement: AudioDelays.Measurement, outcome: AudioDelays.Outcome)?] = []
            for index in runs.indices {
                guard let reference = runs[index].delays.reference(among: candidates()) else { outcomes.append(nil); continue }
                let others = candidates().filter { $0.uid != reference.uid }
                    .map { (file: $0.file, reference: windows[reference.uid]!, other: windows[$0.uid]!) }
                guard !others.isEmpty else { outcomes.append(nil); continue }
                // Without pairs, the same reference sees the same windows: reuse the first run's per-file results.
                var measured = if !runs[index].measuresPairs, let first = outcomes.first?.map(\.measurement), first.reference == reference.file {
                    first
                } else {
                    AudioDelays.measure(reference: reference.file, others: others)
                }
                if !runs[index].measuresPairs { measured.pairs = [] }
                let outcome = runs[index].delays.measured(measured, files: newest, candidates: candidates(), at: Double(measurement + 1) * 10)
                runs[index].latest = outcome.delays.mapValues(\.delay)
                outcomes.append((reference.uid, measured, outcome))
            }
            guard let (reference, measured, outcome) = outcomes[0] else { continue }
            noteStartOver(outcome)
            let pairsCounted = measured.pairs.filter { $0.window?.counts == true }
            let movedTo = runs[0].delays.referenceDevice.flatMap { uid -> (uid: String, group: Int)? in
                guard uid != reference else { return nil }
                return (uid, 1 + pairsCounted.filter { newest[$0.reference] == uid || newest[$0.other] == uid }.count)
            }
            let step = Step(
                measuredAgainst: reference, reference: runs[0].delays.referenceDevice, anchor: runs[0].delays.anchor,
                movedBySound: runs[0].delays.referenceDevice != reference,
                counted: Set(pairsCounted.flatMap { [newest[$0.reference]!, newest[$0.other]!] }),
                fileStarted: fileStarted, anchorGroupBefore: anchorGroupBefore, delaysBefore: delaysBefore, movedTo: movedTo,
                delays: runs[0].latest, writing: Set(candidates().map(\.file)),
                mixed: Set(outcome.earlierBy.compactMap { $0.value == nil ? nil : $0.key }),
                countedAgainstTheReference: measured.files.contains { $0.window?.counts == true },
                rebases: rebases, startOvers: startOvers, lines: fileLines + outcome.lines,
                mainDelays: runs[1].latest, mainAnchor: runs[1].delays.anchor)
            check(measurement, step, previous)
            previous = step
        }
    }

    static let seeds: [UInt64] = Array(1...200)

    /// Every invariant on every measurement of the seed's scenario, each failure naming its invariant:
    /// (i) a move for lack of sync to an input with an audio delay, a re-base, keeps every file being written that
    /// had an audio delay synced and mixed; (ii) a re-base onto another reference changes no audio delay and drops
    /// none; (iii) the reference moves for lack of sync only to an input with a counted window against it in that
    /// measurement; (iv) an input with speech in 3 measurements in a row that the unchanged reference also has
    /// speech in is synced within a frame of its true audio delay against the anchor; (v) a move for lack of sync
    /// starts over only when no input in a counted pair had an audio delay, and only to a group that outnumbers
    /// the anchor's; (vi) a reference without speech beside two inputs sharing speech, the anchor's group the
    /// anchor alone, is replaced at once; (vii) inputs sharing speech for 2 measurements end with an input other
    /// than the anchor synced; (viii) every input synced without pairs, but that run's anchor, is synced at the
    /// end; (ix) a start-over clears the entries of exactly the files being written.
    @Test(arguments: seeds) func theReferenceRulesHold(seed: UInt64) async {
        let scenario = Scenario(seed: seed)
        let byUID = Dictionary(uniqueKeysWithValues: scenario.inputs.map { ($0.uid, $0) })
        var shared: [String: Int] = [:]
        var sharing = 0
        var last: Step?
        await Self.run(scenario, seed: seed) { measurement, step, previous in
            func context(_ invariant: String) -> Comment {
                "(\(invariant)) measurement \(measurement), seed \(seed):\n\(scenario)\n\(step.lines.joined(separator: "\n"))"
            }
            func sound(_ uid: String) -> Sound { byUID[uid]!.sounds[measurement] }
            func writes(_ uid: String) -> Bool { step.writing.contains { $0.hasPrefix("\(uid)-") } }
            let stayed = previous.map { $0.reference == step.measuredAgainst } ?? true
            let startedOver = !step.startOvers.isEmpty
            // (i)
            if let previous, step.movedBySound, !startedOver {
                let synced = step.delaysBefore.keys.filter { step.writing.contains($0) }
                #expect(synced.allSatisfy { step.delays[$0] != nil }, context("i: synced"))
                let stillMixed = previous.mixed.filter { step.writing.contains($0) }
                #expect(stillMixed.isSubset(of: step.mixed), context("i: mixed"))
            }
            // (ii)
            for rebase in step.rebases {
                for (name, delay) in rebase.before where step.writing.contains(name) {
                    #expect(rebase.after[name] == delay, context("ii: \(name)"))
                }
            }
            // (iii)
            if step.movedBySound, let reference = step.reference {
                #expect(step.counted.contains(reference), context("iii: moved to \(reference)"))
            }
            // (iv)
            if step.anchor != previous?.anchor || step.movedBySound || !stayed { shared = [:] }
            if let reference = byUID[step.measuredAgainst], sound(reference.uid).sharesSpeech,
               let anchorUID = step.anchor, let anchor = byUID[anchorUID], anchor.kind == .microphone {
                for input in scenario.inputs where input.uid != reference.uid && input.uid != anchorUID {
                    guard sound(input.uid).sharesSpeech else { shared[input.uid] = 0; continue }
                    shared[input.uid, default: 0] += 1
                    guard shared[input.uid]! >= 3 else { continue }
                    let delay = step.delays.first { $0.key.hasPrefix("\(input.uid)-") }?.value
                    #expect(delay.map { abs($0 - (input.lag - anchor.lag)) <= RecorderValues.audioDelayTolerance } == true,
                            context("iv: \(input.uid) \(String(describing: delay)), true \(input.lag - anchor.lag)"))
                }
            }
            // (v)
            if step.movedBySound, startedOver, let movedTo = step.movedTo {
                #expect(!step.counted.contains { uid in step.delaysBefore.keys.contains { $0.hasPrefix("\(uid)-") } },
                        context("v: an input with an audio delay was in a counted pair"))
                #expect(movedTo.group > step.anchorGroupBefore, context("v: \(movedTo) against \(step.anchorGroupBefore)"))
            }
            // (vi)
            let speakers = scenario.inputs.filter { $0.uid != step.measuredAgainst && writes($0.uid) && sound($0.uid).sharesSpeech }
            if !sound(step.measuredAgainst).sharesSpeech, sound(step.measuredAgainst) != .unrelated,
               speakers.count >= 2, step.anchorGroupBefore == 1, !step.countedAgainstTheReference {
                #expect(step.movedBySound, context("vi: still on \(step.measuredAgainst)"))
            }
            // (ix)
            for startOver in step.startOvers {
                #expect(startOver.cleared == startOver.writing, context("ix: \(startOver)"))
            }
            // (vii)
            let sharingNow = scenario.inputs.filter { writes($0.uid) && sound($0.uid).sharesSpeech }
            sharing = sharingNow.count >= 2 && !step.fileStarted ? sharing + 1 : 0
            if sharing >= 2 {
                let anchorFile = step.anchor.map { "\($0)-" } ?? "-"
                #expect(step.delays.keys.contains { !$0.hasPrefix(anchorFile) }, context("vii: nothing synced"))
            }
            last = step
        }
        // (viii)
        guard let last else { return }
        let mainAnchor = last.mainAnchor.map { "\($0)-" } ?? "-"
        for name in last.mainDelays.keys where !name.hasPrefix(mainAnchor) && last.writing.contains(name) {
            #expect(last.delays[name] != nil, "(viii) seed \(seed): \(name) synced without pairs only\n\(scenario)")
        }
    }
}
