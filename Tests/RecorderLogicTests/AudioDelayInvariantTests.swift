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
        /// Near-silence: a pause in the room, above digital zero.
        case pause
        case hum
        case noise
        /// Its file ended on no audio; a new one starts when its sound returns.
        case noAudio
    }

    /// A microphone that hears the speech, or a flat source (a hum, a loopback of noise, an empty line-in).
    struct Input {
        let uid: String
        let number: Int
        let hearsSpeech: Bool
        let lag: Double
        var sounds: [Sound]
    }

    struct Scenario: CustomStringConvertible {
        var inputs: [Input]
        let measurements: Int
        var description: String {
            inputs.map { "\($0.number)\($0.hearsSpeech ? "mic \(Int(($0.lag * 1000).rounded())) ms" : "flat"): "
                + $0.sounds.map { "\($0)" }.joined(separator: " ") }.joined(separator: "\n")
        }

        init(seed: UInt64) {
            var random = SeededRandom(seed: seed)
            measurements = Int.random(in: 10...20, using: &random)
            let count = Int.random(in: 2...5, using: &random)
            inputs = (1...count).map { number in
                let hearsSpeech = number == 2 || Double.random(in: 0..<1, using: &random) < 0.65
                let lag = (Double.random(in: -0.35...0.35, using: &random) * 1000).rounded() / 1000
                return Input(uid: "u\(number)", number: number, hearsSpeech: hearsSpeech, lag: lag, sounds: [])
            }
            for index in inputs.indices {
                let measurements = self.measurements
                inputs[index].sounds = (0..<measurements).map { _ in
                    let roll = Double.random(in: 0..<1, using: &random)
                    if inputs[index].hearsSpeech { return roll < 0.6 ? .speech : roll < 0.88 ? .pause : .noAudio }
                    return roll < 0.45 ? .hum : roll < 0.9 ? .noise : .noAudio
                }
            }
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

    /// Speech-like bursts: loud and quiet stretches of 80 to 400 ms, shared by every microphone.
    static func speech(measurements: Int, seed: UInt64) -> [Float] {
        var random = SeededRandom(seed: seed &+ 1000)
        let total = (measurements + 2) * windowCount
        var envelope = [Float](repeating: 0, count: total)
        var index = 0
        var loud = true
        while index < total {
            let end = min(total, index + Int.random(in: 640...3200, using: &random))
            vDSP.fill(&envelope[index..<end], with: loud ? 0.5 : 0.02)
            index = end
            loud.toggle()
        }
        return vDSP.multiply(envelope, noise[0..<total])
    }

    static func window(_ sound: Sound, input: Input, measurement: Int, speech: [Float], random: inout SeededRandom) -> [Float] {
        let start = (measurement + 1) * windowCount
        switch sound {
        case .speech:
            let shift = Int((input.lag * Double(AudioDelay.sampleRate)).rounded())
            return vDSP.add(speech[(start - shift)..<(start - shift + windowCount)], slice(of: input, random: &random, scale: 0.002))
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
        let delays: [String: Double]
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
        func file(_ uid: String) -> String { "\(uid)-\(fileNumber[uid]!).mov" }
        func candidates() -> [AudioDelays.Candidate] {
            scenario.inputs.filter { writing.contains($0.uid) }.map { .init(file: file($0.uid), uid: $0.uid, number: $0.number) }
        }
        func fileChanged() {
            guard let reference = delays.reference(among: candidates()) else { return }
            _ = delays.update(files: newest, reference: reference.file)
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
                    fileChanged()
                }
            }
            let before = delays.referenceDevice
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
            let step = Step(
                measuredAgainst: reference.uid, reference: delays.referenceDevice, anchor: delays.anchor,
                movedBySound: before == reference.uid && delays.referenceDevice != reference.uid,
                delays: outcome.delays.mapValues(\.delay),
                mixed: Set(outcome.earlierBy.compactMap { $0.value == nil ? nil : $0.key }),
                counted: measured.files.contains { $0.window?.counts == true },
                lines: outcome.lines)
            check(measurement, step, previous)
            previous = step
        }
    }

    static let seeds: [UInt64] = Array(1...200)

    /// Every invariant on every measurement of the seed's scenario, each failure naming its invariant:
    /// (i) a pause of one or two measurements after a counted window never moves the reference nor takes a
    /// synced input out of the mix; (ii) a re-base onto another reference changes no audio delay; (iii) a flat
    /// input never becomes the reference while an input with speech is being written; (iv) an input with speech
    /// in 3 measurements in a row that the unchanged reference also has speech in is synced within a frame of
    /// its true audio delay against the anchor; (v) the reference never moves for sound more than once in 3
    /// measurements.
    @Test(arguments: seeds) func theReferenceRulesHold(seed: UInt64) {
        let scenario = Scenario(seed: seed)
        let byUID = Dictionary(uniqueKeysWithValues: scenario.inputs.map { ($0.uid, $0) })
        var sinceCounted = Int.max
        var lastMove: Int?
        var shared: [String: Int] = [:]
        Self.run(scenario, seed: seed) { measurement, step, previous in
            func context(_ invariant: String) -> Comment {
                "(\(invariant)) measurement \(measurement), seed \(seed):\n\(scenario)\n\(step.lines.joined(separator: "\n"))"
            }
            // (i)
            sinceCounted = step.counted ? 0 : sinceCounted == Int.max ? Int.max : sinceCounted + 1
            if let previous, !step.counted, sinceCounted <= 2, previous.reference == step.measuredAgainst {
                #expect(!step.movedBySound, context("i"))
                let stillMixed = previous.mixed.filter { name in step.delays[name] != nil }
                #expect(stillMixed.isSubset(of: step.mixed), context("i"))
            }
            // (ii)
            if let previous, step.lines.contains(where: { $0.contains(": lags re-based onto the anchor by ") }) {
                for (name, delay) in previous.delays {
                    guard let now = step.delays[name] else { continue }
                    #expect(now == delay, context("ii: \(name)"))
                }
            }
            // (iii): a move for sound picks by this measurement's action scores, one at a file's end by the latest before.
            let forced = step.measuredAgainst != previous?.reference ?? scenario.inputs[0].uid
            if let scored = step.movedBySound ? measurement : forced ? measurement - 1 : nil, scored >= 0,
               let reference = step.movedBySound ? step.reference : step.measuredAgainst, let input = byUID[reference] {
                let speaking = scenario.inputs.contains { $0.sounds[scored] == .speech && $0.sounds[measurement] != .noAudio }
                #expect(input.hearsSpeech || !speaking, context("iii: \(reference) became the reference"))
            }
            // (iv)
            if step.anchor != previous?.anchor || step.measuredAgainst != step.reference
                || step.measuredAgainst != previous?.reference { shared = [:] }
            if let reference = byUID[step.measuredAgainst], reference.sounds[measurement] == .speech,
               let anchorUID = step.anchor, let anchor = byUID[anchorUID], anchor.hearsSpeech {
                for input in scenario.inputs where input.uid != reference.uid && input.uid != anchorUID {
                    guard input.sounds[measurement] == .speech else { shared[input.uid] = 0; continue }
                    shared[input.uid, default: 0] += 1
                    guard shared[input.uid]! >= 3 else { continue }
                    let delay = step.delays.first { $0.key.hasPrefix("\(input.uid)-") }?.value
                    #expect(delay.map { abs($0 - (input.lag - anchor.lag)) <= RecorderValues.audioDelayTolerance } == true,
                            context("iv: \(input.uid) \(String(describing: delay)), true \(input.lag - anchor.lag)"))
                }
            }
            // (v)
            if step.movedBySound {
                if let lastMove { #expect(measurement - lastMove >= RecorderValues.referenceUnsyncedMeasurements, context("v")) }
                lastMove = measurement
            }
        }
    }
}
