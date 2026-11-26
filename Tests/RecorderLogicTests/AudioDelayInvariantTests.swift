import Accelerate
import Foundation
import Testing
@testable import RecorderLogic

/// Seeded scenarios of 2 to 5 audio inputs over 10 to 20 measurements, driven through the recorder's own calls
/// (`AudioDelays.reference(among:)`, `AudioDelays.measure`, `AudioDelays.measured`, `AudioDelays.update` at a
/// file's start or end), each run checked against the reference rules' invariants (D89).
@Suite struct AudioDelayInvariantTests {
    /// What an input sends in one 10 s window.
    enum Sound: Equatable {
        /// The shared speech, later by the input's lag.
        case speech
        /// The shared speech behind a noise gate: digital zero between the bursts.
        case gatedSpeech
        /// The shared speech from afar under the room's noise: less action.
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
        var isFlat: Bool { self == .pause || self == .hum || self == .noise }
    }

    enum Kind: String { case microphone, unrelated, flat }

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
                let kind: Kind = number == 2 || roll < 0.5 ? .microphone : roll < 0.7 ? .unrelated : .flat
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
                    case .flat: roll < 0.45 ? .hum : roll < 0.9 ? .noise : .noAudio
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

    /// One measurement's state, as the invariants see it.
    struct Step {
        /// The device measured against, and the reference after the measurement.
        let measuredAgainst: String
        let reference: String?
        let anchor: String?
        let movedBySound: Bool
        /// The device the reference was tried on, from the log line.
        let triedOn: String?
        /// A file started before this measurement.
        let fileStarted: Bool
        /// An input other than the anchor had an audio delay before this measurement.
        let wasSynced: Bool
        let delays: [String: Double]
        let writing: Set<String>
        let mixed: Set<String>
        let counted: Bool
        let lines: [String]
    }

    /// Runs the scenario as the recorder does; `check` sees each measurement's outcome.
    static func run(_ scenario: Scenario, seed: UInt64, check: (Int, Step, Step?) -> Void) {
        var random = SeededRandom(seed: seed &+ 2000)
        let speech = speech(measurements: scenario.measurements, seed: seed)
        var delays = AudioDelays()
        var fileNumber: [String: Int] = [:]
        var newest: [String: String] = [:]
        var writing: Set<String> = []
        var synced = false
        func file(_ uid: String) -> String { "\(uid)-\(fileNumber[uid]!).mov" }
        func candidates() -> [AudioDelays.Candidate] {
            scenario.inputs.filter { writing.contains($0.uid) }.map { .init(file: file($0.uid), uid: $0.uid, number: $0.number) }
        }
        func took(_ outcome: AudioDelays.Outcome) {
            synced = synced || outcome.delays.contains { newest[$0.key] != delays.anchor }
        }
        func fileChanged() {
            guard let reference = delays.reference(among: candidates()) else { return }
            took(delays.update(files: newest, reference: reference.file))
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
            var fileStarted = false
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
            let wasSynced = synced
            guard let reference = delays.reference(among: candidates()) else { continue }
            let byUID = Dictionary(uniqueKeysWithValues: scenario.inputs.map { ($0.uid, $0) })
            let windows = Dictionary(uniqueKeysWithValues: candidates().map { candidate in
                (candidate.uid, window(byUID[candidate.uid]!.sounds[measurement], input: byUID[candidate.uid]!,
                                       measurement: measurement, speech: speech, random: &random))
            })
            let others = candidates().filter { $0.uid != reference.uid }
                .map { (file: $0.file, uid: $0.uid, reference: windows[reference.uid]!, other: windows[$0.uid]!) }
            guard !others.isEmpty else { continue }
            let measured = AudioDelays.measure(reference: (reference.file, reference.uid), others: others)
            let outcome = delays.measured(measured, files: newest, candidates: candidates(), at: Double(measurement + 1) * 10)
            took(outcome)
            let tried = outcome.lines.lazy.compactMap { $0.firstMatch(of: /; tries (u\d+)-\d+\.mov/)?.1 }.first.map(String.init)
            let step = Step(
                measuredAgainst: reference.uid, reference: delays.referenceDevice, anchor: delays.anchor,
                movedBySound: delays.referenceDevice != reference.uid, triedOn: tried, fileStarted: fileStarted,
                wasSynced: wasSynced, delays: outcome.delays.mapValues(\.delay), writing: Set(candidates().map(\.file)),
                mixed: Set(outcome.earlierBy.compactMap { $0.value == nil ? nil : $0.key }),
                counted: measured.files.contains { $0.window?.counts == true },
                lines: outcome.lines)
            check(measurement, step, previous)
            previous = step
        }
    }

    static let seeds: [UInt64] = Array(1...200)

    /// Every invariant on every measurement of the seed's scenario, each failure naming its invariant:
    /// (i) a pause of one or two measurements after a counted window, something synced, never moves the
    /// reference nor takes a synced input out of the mix; (ii) a re-base onto another reference changes no audio
    /// delay and drops none; (iii) the reference is never tried on an input without action; (iv) an input with
    /// speech in 3 measurements in a row that the unchanged reference also has speech in is synced within a frame
    /// of its true audio delay against the anchor; (v) the reference is never tried elsewhere once an input other
    /// than the anchor has had an audio delay, so nothing starts over then; (vi) a reference without action beside
    /// two inputs sharing speech, nothing synced, is replaced within one measurement; (vii) inputs sharing speech,
    /// from a time nothing was synced, long enough for every try, end with an input other than the anchor synced; (viii) a try episode, from a
    /// counted window to the next, moves the reference at most once per input plus once per file started in it,
    /// plus the move back.
    @Test(arguments: seeds) func theReferenceRulesHold(seed: UInt64) {
        let scenario = Scenario(seed: seed)
        let byUID = Dictionary(uniqueKeysWithValues: scenario.inputs.map { ($0.uid, $0) })
        var sinceCounted = Int.max
        var shared: [String: Int] = [:]
        var flatReference = 0
        var sharing = 0
        var sharingFromUnsynced = false
        var filesInEpisode = 0
        var movesInEpisode = 0
        Self.run(scenario, seed: seed) { measurement, step, previous in
            func context(_ invariant: String) -> Comment {
                "(\(invariant)) measurement \(measurement), seed \(seed):\n\(scenario)\n\(step.lines.joined(separator: "\n"))"
            }
            func sound(_ uid: String) -> Sound { byUID[uid]!.sounds[measurement] }
            func writes(_ uid: String) -> Bool { step.writing.contains { $0.hasPrefix("\(uid)-") } }
            let stayed = previous.map { $0.reference == step.measuredAgainst } ?? true
            // (i)
            sinceCounted = step.counted ? 0 : sinceCounted == Int.max ? Int.max : sinceCounted + 1
            if let previous, step.wasSynced, !step.counted, sinceCounted <= 2, stayed, !step.fileStarted {
                #expect(!step.movedBySound, context("i"))
                let stillMixed = previous.mixed.filter { step.writing.contains($0) }
                #expect(stillMixed.isSubset(of: step.mixed), context("i"))
            }
            // (ii)
            if let previous, step.lines.contains(where: { $0.contains(": lags re-based onto the anchor by ") }) {
                for (name, delay) in previous.delays where step.writing.contains(name) {
                    #expect(step.delays[name] == delay, context("ii: \(name)"))
                }
            }
            // (iii)
            if let tried = step.triedOn { #expect(!sound(tried).isFlat && sound(tried) != .noAudio, context("iii: tried \(tried)")) }
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
            if step.triedOn != nil {
                #expect(!step.wasSynced, context("v"))
                if let previous {
                    let anchorFile = previous.anchor.map { "\($0)-" }
                    let synced = previous.delays.keys.filter { name in
                        step.writing.contains(name) && !(anchorFile.map(name.hasPrefix) ?? false)
                    }
                    #expect(synced.isEmpty, context("v: \(synced) had an audio delay"))
                }
            }
            // (vi): the count restarts at a file's start, which starts a new episode.
            let speakers = scenario.inputs.filter { $0.uid != step.measuredAgainst && writes($0.uid) && sound($0.uid).sharesSpeech }
            if sound(step.measuredAgainst).isFlat, speakers.count >= 2, stayed, !step.fileStarted, !step.wasSynced {
                flatReference += 1
                #expect(step.movedBySound || flatReference < 1, context("vi: still on \(step.measuredAgainst) after \(flatReference)"))
            } else {
                flatReference = 0
            }
            // (vii): two speakers or more, from a time nothing was synced, for as long as every input could be tried,
            // the reference one of them or not, end with an input other than the anchor synced; once one is, (iv)
            // holds for the rest, and a reference that pauses then is not tried elsewhere (v).
            let sharingNow = scenario.inputs.filter { writes($0.uid) && sound($0.uid).sharesSpeech }
            sharing = sharingNow.count >= 2 && !step.fileStarted ? sharing + 1 : 0
            if sharing == 1 { sharingFromUnsynced = !step.wasSynced }
            if sharingFromUnsynced, sharing == scenario.inputs.count + 1 {
                let anchorFile = step.anchor.map { "\($0)-" } ?? "-"
                #expect(step.wasSynced || step.delays.keys.contains { !$0.hasPrefix(anchorFile) }, context("vii: nothing synced"))
            }
            // (viii)
            if step.counted { (movesInEpisode, filesInEpisode) = (0, 0) }
            filesInEpisode += step.writing.subtracting(previous?.writing ?? step.writing).count
            if step.movedBySound {
                movesInEpisode += 1
                #expect(movesInEpisode <= scenario.inputs.count + filesInEpisode, context("viii: \(movesInEpisode) moves"))
            }
        }
    }
}
