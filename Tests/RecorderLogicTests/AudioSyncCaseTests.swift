import Accelerate
import Testing
@testable import RecorderLogic

/// The recordings the one reference rule is built for (D90), each a hand-made scenario of 12 measurements whose
/// inputs hear independent talkers, driven through the recorder's own calls (`AudioDelayInvariantTests.run`).
@Suite struct AudioSyncCaseTests {
    typealias Invariants = AudioDelayInvariantTests
    typealias Step = AudioDelayInvariantTests.Step

    static let measurements = 12
    static let windowCount = Invariants.windowCount

    /// A talker of its own: speech-like loud and quiet stretches over its own noise.
    static func talker(_ seed: UInt64, measurements: Int = measurements) -> [Float] {
        var random = SeededRandom(seed: seed)
        let total = (measurements + 2) * windowCount
        let carrier = (0..<total).map { _ in Float.random(in: -1...1, using: &random) }
        return vDSP.multiply(Invariants.envelope(count: total, quiet: 0.02, random: &random), carrier)
    }

    static let (room, call, other) = (talker(11), talker(12), talker(13))

    /// What input `number` records in measurement `m`.
    typealias Sound = (_ m: Int, _ number: Int, _ random: inout SeededRandom) -> [Float]

    static func own(_ number: Int, _ scale: Float, _ random: inout SeededRandom) -> [Float] {
        let start = Invariants.speechRegion + (number - 1) * Invariants.inputRegion
            + Int.random(in: 0...(Invariants.inputRegion - windowCount), using: &random)
        return vDSP.multiply(scale, Invariants.noise[start..<(start + windowCount)])
    }

    /// `signal` later by `lag`, under the input's own faint noise.
    static func hears(_ signal: [Float], _ lag: Double, _ m: Int, _ number: Int, gain: Float = 1, _ random: inout SeededRandom) -> [Float] {
        let start = (m + 1) * windowCount - Int((lag * Double(AudioDelay.sampleRate)).rounded())
        return vDSP.add(vDSP.multiply(gain, signal[start..<(start + windowCount)]), own(number, 0.002, &random))
    }

    static func hum(_ m: Int) -> [Float] {
        let rate = Double(AudioDelay.sampleRate)
        let phase = Float(2 * Double.pi * 50 * Double((m + 1) * windowCount) / rate)
        return vDSP.multiply(0.3, vForce.sin(vDSP.ramp(withInitialValue: phase, increment: Float(2 * Double.pi * 50 / rate), count: windowCount)))
    }

    static func pause(_ m: Int, _ number: Int, _ random: inout SeededRandom) -> [Float] { own(number, 0.0005, &random) }

    /// `signal` at `lag` from measurement `from` until before `until`, `otherwise` a pause.
    static func on(_ signal: [Float], _ lag: Double, from: Int = 0, until: Int = .max, otherwise: @escaping Sound = pause) -> Sound {
        { m, number, random in m >= from && m < until ? hears(signal, lag, m, number, &random) : otherwise(m, number, &random) }
    }

    /// Each measurement's step of the inputs `sounds`, input n the n-th.
    static func steps(_ sounds: [Sound], measurements: Int = measurements) async -> [Step] {
        var random = SeededRandom(seed: 99)
        let windows = (0..<measurements).map { m in sounds.enumerated().map { $0.element(m, $0.offset + 1, &random) } }
        let inputs = sounds.indices.map {
            Invariants.Input(uid: "u\($0 + 1)", number: $0 + 1, kind: .microphone, lag: 0, sounds: Array(repeating: .speech, count: measurements))
        }
        var steps: [Step] = []
        await Invariants.run(.init(inputs: inputs), seed: 1, windows: { m, input in windows[m][input.number - 1] }) { _, step, _ in
            steps.append(step)
        }
        return steps
    }

    static func delay(of uid: String, in step: Step) -> Double? { step.delays.first { $0.key.hasPrefix("\(uid)-") }?.value }
    static func isSynced(_ uid: String, in step: Step?) -> Bool { step.flatMap { delay(of: uid, in: $0) } != nil }
    static func startOvers(_ steps: [Step]) -> Int { steps.map(\.startOvers.count).reduce(0, +) }
    static func lines(_ steps: [Step]) -> String { steps.flatMap(\.lines).joined(separator: "\n") }

    /// A: two junk inputs, input 1 the reference, share one burst, then two room microphones talk. The burst syncs
    /// input 2 by one window, which proves nothing: the anchor's group is input 1 alone, the room's pair
    /// outnumbers it, the reference starts over at the room, and the room syncs.
    @Test func aStrayBurstOnTwoJunkInputsDoesNotKeepTheRoomFromSyncing() async {
        let steps = await Self.steps([
            { m, x, r in m == 0 ? Self.hears(Self.other, 0, m, x, &r) : Self.hum(m) },
            { m, x, r in m == 0 ? Self.hears(Self.other, 0.01, m, x, &r) : Self.own(x, 0.3, &r) },
            Self.on(Self.room, 0.1, from: 1), Self.on(Self.room, 0.2, from: 1),
        ])
        #expect(Self.isSynced("u3", in: steps.last) && Self.isSynced("u4", in: steps.last), "\(Self.lines(steps))")
        let (u3, u4) = (steps.last.flatMap { Self.delay(of: "u3", in: $0) } ?? 0, steps.last.flatMap { Self.delay(of: "u4", in: $0) } ?? 0)
        #expect(abs(u4 - u3 - 0.1) <= RecorderValues.audioDelayTolerance, "\(Self.lines(steps))")
    }

    /// B: the same with three room microphones.
    @Test func aStrayBurstOnTwoJunkInputsBesideThreeRoomMicrophones() async {
        let steps = await Self.steps([
            { m, x, r in m == 0 ? Self.hears(Self.other, 0, m, x, &r) : Self.hum(m) },
            { m, x, r in m == 0 ? Self.hears(Self.other, 0.01, m, x, &r) : Self.own(x, 0.3, &r) },
            Self.on(Self.room, 0.1, from: 1), Self.on(Self.room, 0.2, from: 1), Self.on(Self.room, 0.05, from: 1),
        ])
        #expect(["u3", "u4", "u5"].allSatisfy { Self.isSynced($0, in: steps.last) }, "\(Self.lines(steps))")
    }

    /// C: two loopbacks of a call take the reference while the room is quiet for 20 s; the room's two
    /// microphones never outnumber them, a known cost (D89, D90).
    @Test func twoLoopbacksOfACallKeepTheReferenceBeforeTwoRoomMicrophones() async {
        let steps = await Self.steps([
            Self.on(Self.room, 0, from: 2), Self.on(Self.room, 0.1, from: 2), Self.on(Self.call, 0), Self.on(Self.call, 0.01),
        ])
        #expect(steps.last?.reference == "u3" && steps.last?.anchor == "u3", "\(Self.lines(steps))")
        #expect(!Self.isSynced("u1", in: steps.last) && !Self.isSynced("u2", in: steps.last), "\(Self.lines(steps))")
        #expect(Self.startOvers(steps) == 1, "\(Self.lines(steps))")
    }

    /// D: the same with three room microphones: the call's partner always matches, so there is no miss at all.
    @Test func twoLoopbacksOfACallKeepTheReferenceBeforeThreeRoomMicrophones() async {
        let steps = await Self.steps([
            Self.on(Self.room, 0, from: 2), Self.on(Self.room, 0.1, from: 2), Self.on(Self.room, 0.2, from: 2),
            Self.on(Self.call, 0), Self.on(Self.call, 0.01),
        ])
        #expect(steps.last?.reference == "u4", "\(Self.lines(steps))")
        #expect(["u1", "u2", "u3"].allSatisfy { !Self.isSynced($0, in: steps.last) }, "\(Self.lines(steps))")
    }

    /// E: two rooms taking turns every 10 s, two microphones each: the quiet room's reference misses and the
    /// talking room's pair, unsynced, outnumbers the anchor's group, so every turn starts over, as before.
    @Test func twoRoomsTakingTurnsStartOverEveryTurn() async {
        let steps = await Self.steps([
            { m, x, r in m % 2 == 1 ? Self.hears(Self.room, 0, m, x, &r) : Self.pause(m, x, &r) },
            { m, x, r in m % 2 == 1 ? Self.hears(Self.room, 0.1, m, x, &r) : Self.pause(m, x, &r) },
            { m, x, r in m % 2 == 0 ? Self.hears(Self.other, 0, m, x, &r) : Self.pause(m, x, &r) },
            { m, x, r in m % 2 == 0 ? Self.hears(Self.other, 0.2, m, x, &r) : Self.pause(m, x, &r) },
        ])
        #expect(Self.startOvers(steps) == Self.measurements, "\(Self.lines(steps))")
    }

    /// F: the owner's Mac, 2026-11-26: a healthy reference unclear once while two synced inputs match: the
    /// reference moves to one of them, re-based, and every input stays synced and mixed throughout.
    @Test func aHealthyReferenceUnclearOnceKeepsEverySync() async {
        let steps = await Self.steps([
            { m, x, r in m == 1 ? Self.own(x, 0.3, &r) : Self.hears(Self.room, 0.4, m, x, &r) },
            Self.on(Self.room, 0), Self.on(Self.room, 0.014),
        ])
        #expect(Self.startOvers(steps) == 0, "\(Self.lines(steps))")
        #expect(steps.allSatisfy { step in ["u1", "u2", "u3"].allSatisfy { Self.isSynced($0, in: step) } }, "\(Self.lines(steps))")
        #expect(steps.allSatisfy { $0.mixed.count == 3 }, "\(Self.lines(steps))")
        #expect(steps.allSatisfy { $0.anchor == "u1" } && steps[1].reference == "u2", "\(Self.lines(steps))")
    }

    /// G: the reference pauses 20 s after the sync is made while the two others talk: it moves to a synced
    /// input, and no audio delay changes.
    @Test func aReferencePausingAfterTheSyncMovesKeepingTheAudioDelays() async {
        let steps = await Self.steps([
            { m, x, r in m == 2 || m == 3 ? Self.pause(m, x, &r) : Self.hears(Self.room, 0, m, x, &r) },
            Self.on(Self.room, 0.3), Self.on(Self.room, 0.1),
        ])
        #expect(Self.startOvers(steps) == 0 && steps[2].movedBySound, "\(Self.lines(steps))")
        for step in steps.dropFirst() {
            #expect(abs((Self.delay(of: "u2", in: step) ?? 0) - 0.3) <= RecorderValues.audioDelayTolerance, "\(step.lines)")
            #expect(abs((Self.delay(of: "u3", in: step) ?? 0) - 0.1) <= RecorderValues.audioDelayTolerance, "\(step.lines)")
        }
    }

    /// H: a far microphone hears only a second talker the reference does not hear: it never syncs, and nothing
    /// moves for it.
    @Test func aMicrophoneHearingOnlyAnotherTalkerNeverSyncs() async {
        let steps = await Self.steps([
            Self.on(Self.room, 0),
            { m, x, r in vDSP.add(Self.hears(Self.room, 0.1, m, x, &r), Self.hears(Self.other, 0.1, m, x, gain: 0.7, &r)) },
            Self.on(Self.other, 0.25),
        ])
        #expect(!Self.isSynced("u3", in: steps.last) && steps.allSatisfy { $0.reference == "u1" }, "\(Self.lines(steps))")
        #expect(Self.isSynced("u2", in: steps.last), "\(Self.lines(steps))")
    }

    /// I: the dock's empty line-in as input 1 beside three microphones hands the reference on at the first
    /// measurement, every microphone synced in it.
    @Test func theDocksEmptyLineInHandsTheReferenceOnAtOnce() async {
        let steps = await Self.steps([
            { _, x, r in Self.own(x, 0.001, &r) }, Self.on(Self.room, 0.5), Self.on(Self.room, 0), Self.on(Self.room, 0.1),
        ])
        #expect(steps[0].reference == "u2" && steps[0].anchor == "u2", "\(steps[0].lines)")
        #expect(abs((Self.delay(of: "u3", in: steps[0]) ?? 0) + 0.5) <= RecorderValues.audioDelayTolerance, "\(steps[0].lines)")
        #expect(abs((Self.delay(of: "u4", in: steps[0]) ?? 0) + 0.4) <= RecorderValues.audioDelayTolerance, "\(steps[0].lines)")
        #expect(Self.startOvers(steps) == 1, "\(Self.lines(steps))")
    }

    /// J: a lone microphone beside a loopback: nothing moves.
    @Test func aLoneMicrophoneBesideALoopbackKeepsTheReference() async {
        let steps = await Self.steps([Self.on(Self.room, 0), Self.on(Self.call, 0)])
        #expect(steps.allSatisfy { $0.reference == "u1" && !$0.movedBySound } && Self.startOvers(steps) == 0, "\(Self.lines(steps))")
    }

    /// Long drift: input 1, the anchor, drifts 3 ms later or earlier per measurement for 40 measurements and is
    /// unclear once at the fifth while inputs 2 and 3 match. Once the reference moved, input 1 is measured like
    /// any other input, so its placement against input 2 stays within 41 ms of true, the 60 s rule's sawtooth,
    /// as before D90; unmeasured, it grew past 117 ms.
    @Test(arguments: [0.003, -0.003]) func aDriftingAnchorIsFollowedAfterTheReferenceMoves(drift: Double) async {
        let count = 40
        let talker = Self.talker(21, measurements: count)
        let lags = [0.0, 0.2, 0.1]
        let lag = { (index: Int, m: Int) in lags[index] + (index == 0 ? drift * Double(m) : 0) }
        let steps = await Self.steps((0..<3).map { index in
            { m, x, r in index == 0 && m == 4 ? Self.pause(m, x, &r) : Self.hears(talker, lag(index, m), m, x, &r) }
        }, measurements: count)
        #expect(steps.contains { $0.reference != "u1" }, "\(Self.lines(steps))")
        var worst = 0.0
        for (m, step) in steps.enumerated() {
            guard let first = Self.delay(of: "u1", in: step), let second = Self.delay(of: "u2", in: step) else { continue }
            worst = max(worst, abs((first - second) - (lag(0, m) - lag(1, m))))
        }
        #expect(worst <= 0.0415, "worst \(worst)\n\(Self.lines(steps))")
    }
}
