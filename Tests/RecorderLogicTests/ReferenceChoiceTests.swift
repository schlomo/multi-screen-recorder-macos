import Testing
@testable import RecorderLogic

/// The reference rules (D89) in hand-written scenarios, through the recorder's own calls
/// (`AudioDelayInvariantTests.run`): the reference moves for lack of sync only to an input the measurement proves.
@Suite struct ReferenceChoiceTests {
    typealias Input = AudioDelayInvariantTests.Input
    typealias Sound = AudioDelayInvariantTests.Sound

    static func input(_ number: Int, _ kind: AudioDelayInvariantTests.Kind, lag: Double = 0, _ sounds: [Sound]) -> Input {
        Input(uid: "u\(number)", number: number, kind: kind, lag: lag, sounds: sounds)
    }

    static func repeated(_ sound: Sound, _ count: Int) -> [Sound] { Array(repeating: sound, count: count) }

    /// Each measurement's step, in order.
    static func steps(_ inputs: [Input], seed: UInt64 = 1) -> [AudioDelayInvariantTests.Step] {
        var steps: [AudioDelayInvariantTests.Step] = []
        AudioDelayInvariantTests.run(.init(inputs: inputs), seed: seed) { _, step, _ in steps.append(step) }
        return steps
    }

    static func delay(of uid: String, in step: AudioDelayInvariantTests.Step) -> Double? {
        step.delays.first { $0.key.hasPrefix("\(uid)-") }?.value
    }

    static func isNear(_ value: Double?, _ expected: Double) -> Bool { value.map { abs($0 - expected) < 0.002 } == true }

    static func moves(_ steps: [AudioDelayInvariantTests.Step]) -> Int { steps.filter(\.movedBySound).count }

    /// The owner's recordings: input 1 a dock's line-in with nothing connected, near-silence; three microphones
    /// hear the talker. The first measurement counts nothing against input 1, but the microphones count against
    /// each other: the reference moves to input 2 (all tie, the lowest number), and the others sync against it in
    /// that same measurement.
    @Test func aNearSilentInput1HandsTheReferenceOnAtTheFirstMeasurement() {
        let steps = Self.steps([
            Self.input(1, .steady, Self.repeated(.pause, 3)),
            Self.input(2, .microphone, lag: 0.5, Self.repeated(.speech, 3)),
            Self.input(3, .microphone, lag: 0, Self.repeated(.speech, 3)),
            Self.input(4, .microphone, lag: 0.1, Self.repeated(.speech, 3)),
        ])
        #expect(steps[0].reference == "u2" && steps[0].anchor == "u2", "\(steps[0].lines)")
        #expect(Self.isNear(Self.delay(of: "u3", in: steps[0]), -0.5), "\(steps[0].lines)")
        #expect(Self.isNear(Self.delay(of: "u4", in: steps[0]), -0.4), "\(steps[0].lines)")
        #expect(Self.moves(steps) == 1)
    }

    /// A loud steady hum as input 1 hands the reference on and never gets it back; beside a lone microphone it
    /// moves nothing.
    @Test func aHumIsNeverTheReferenceBesideMicrophones() {
        let beside = Self.steps([
            Self.input(1, .steady, Self.repeated(.hum, 6)),
            Self.input(2, .microphone, lag: 0, Self.repeated(.speech, 2) + Self.repeated(.pause, 2) + Self.repeated(.speech, 2)),
            Self.input(3, .microphone, lag: 0.2, Self.repeated(.speech, 2) + Self.repeated(.pause, 2) + Self.repeated(.speech, 2)),
        ])
        #expect(beside.allSatisfy { $0.reference == "u2" }, "\(beside.map(\.lines))")
        let lone = Self.steps([
            Self.input(1, .microphone, lag: 0, Self.repeated(.speech, 4)),
            Self.input(2, .steady, Self.repeated(.hum, 4)),
        ])
        #expect(lone.allSatisfy { $0.reference == "u1" }, "\(lone.map(\.lines))")
    }

    /// B-1 of the second review: an input with unrelated sound, gated or not, never takes the reference from
    /// microphones that sync: as input 1 it hands it on to them, as input 3 it never gets it.
    @Test(arguments: [Sound.unrelated, .gatedUnrelated])
    func anUnrelatedInputNeverKeepsTheReference(unrelated: Sound) {
        let first = Self.steps([
            Self.input(1, .unrelated, Self.repeated(unrelated, 4)),
            Self.input(2, .microphone, lag: 0, Self.repeated(.roomSpeech, 4)),
            Self.input(3, .microphone, lag: 0.1, Self.repeated(.roomSpeech, 4)),
        ])
        #expect(first.allSatisfy { $0.reference == "u2" }, "\(first.map(\.lines))")
        #expect(Self.isNear(Self.delay(of: "u3", in: first[0]), 0.1), "\(first[0].lines)")
        let third = Self.steps([
            Self.input(1, .microphone, lag: 0, Self.repeated(.roomSpeech, 4)),
            Self.input(2, .microphone, lag: 0.1, Self.repeated(.roomSpeech, 4)),
            Self.input(3, .unrelated, Self.repeated(unrelated, 4)),
        ])
        #expect(third.allSatisfy { $0.reference == "u1" }, "\(third.map(\.lines))")
        #expect(Self.isNear(third.last.flatMap { Self.delay(of: "u2", in: $0) }, 0.1))
    }

    /// B1 of the third review (H13): input 1's talker starts after 30 s, input 2 has room speech all along, input 3
    /// unrelated sound: nothing proves another reference, so nothing moves, and input 2 syncs once input 1 speaks,
    /// as under main's rules.
    @Test func aTalkerStartingLateOnInput1SyncsAsBefore() {
        let steps = Self.steps([
            Self.input(1, .microphone, lag: 0, Self.repeated(.pause, 3) + Self.repeated(.speech, 4)),
            Self.input(2, .microphone, lag: 0.1, Self.repeated(.roomSpeech, 7)),
            Self.input(3, .unrelated, Self.repeated(.unrelated, 7)),
        ])
        #expect(steps.allSatisfy { $0.reference == "u1" }, "\(steps.map(\.lines))")
        #expect(Self.isNear(steps.last.flatMap { Self.delay(of: "u2", in: $0) }, 0.1), "\(steps.map(\.lines))")
    }

    /// M-1 of the second review and M1 of the third (DZN): a lone microphone beside an unrelated input whose file
    /// ends and starts again, the microphone pausing: nothing moves, the microphone stays the anchor and in the mix.
    @Test func aLoneMicrophoneBesideAnUnrelatedInputKeepsTheReference() {
        let steps = Self.steps([
            Self.input(1, .microphone, lag: 0, Self.repeated(.speech, 3) + Self.repeated(.pause, 4) + Self.repeated(.speech, 3)),
            Self.input(2, .unrelated, Self.repeated(.unrelated, 4) + [.noAudio] + Self.repeated(.unrelated, 5)),
        ])
        #expect(steps.allSatisfy { $0.reference == "u1" && $0.anchor == "u1" && $0.mixed.contains { $0.hasPrefix("u1-") } },
                "\(steps.map(\.lines))")
    }

    /// M2 of the third review (DZH): one counted window, as a burst on the dock gives, does not confirm the
    /// sync: input 1 then hums, the microphones prove one of them, and every microphone ends synced.
    @Test func aSingleCountedWindowDoesNotConfirmTheSync() {
        let steps = Self.steps([
            Self.input(1, .steady, [.speech] + Self.repeated(.hum, 4)),
            Self.input(2, .microphone, lag: 0.3, Self.repeated(.speech, 5)),
            Self.input(3, .microphone, lag: 0.1, [.pause] + Self.repeated(.speech, 4)),
            Self.input(4, .microphone, lag: 0.2, [.pause] + Self.repeated(.speech, 4)),
        ])
        #expect(Self.delay(of: "u2", in: steps[0]) != nil && !steps[0].wasConfirmed, "\(steps[0].lines)")
        #expect(steps[1].movedBySound && steps[1].reference == "u2", "\(steps[1].lines)")
        #expect(Self.isNear(steps.last.flatMap { Self.delay(of: "u3", in: $0) }, -0.2), "\(steps.map(\.lines))")
        #expect(Self.isNear(steps.last.flatMap { Self.delay(of: "u4", in: $0) }, -0.1), "\(steps.map(\.lines))")
    }

    /// Two counted windows confirm the sync: input 1 then hums beside the microphones, and the reference stays.
    @Test func twoCountedWindowsConfirmTheSync() {
        let steps = Self.steps([
            Self.input(1, .steady, [.speech, .speech] + Self.repeated(.hum, 3)),
            Self.input(2, .microphone, lag: 0.3, Self.repeated(.speech, 5)),
            Self.input(3, .microphone, lag: 0.1, [.pause, .pause] + Self.repeated(.speech, 3)),
        ])
        #expect(steps[2].wasConfirmed, "\(steps.map(\.lines))")
        #expect(steps.allSatisfy { $0.reference == "u1" && !$0.movedBySound }, "\(steps.map(\.lines))")
    }

    /// A healthy recording whose input 1, a room microphone, syncs everything at the first measurement: nothing
    /// moves, as before D89 (M-2 of the second review).
    @Test func aHealthyFirstMeasurementKeepsItsCountedLags() {
        let steps = Self.steps([
            Self.input(1, .microphone, lag: 0.05, Self.repeated(.roomSpeech, 3)),
            Self.input(2, .microphone, lag: 0, Self.repeated(.speech, 3)),
            Self.input(3, .microphone, lag: 0.1, Self.repeated(.speech, 3)),
        ])
        #expect(steps.allSatisfy { $0.reference == "u1" && !$0.movedBySound })
        #expect(Self.isNear(Self.delay(of: "u2", in: steps[0]), -0.05), "\(steps[0].lines)")
        #expect(Self.isNear(Self.delay(of: "u3", in: steps[0]), 0.05), "\(steps[0].lines)")
    }

    /// E2 of the second review: two talkers taking turns of 60 s, each on a microphone that hears only its own:
    /// nothing proves another reference, so nothing moves.
    @Test func twoTalkersThatNeverCorrelateMoveNothing() {
        let turns = (0..<12).map { ($0 / 6) % 2 == 0 }
        let steps = Self.steps([
            Self.input(1, .unrelated, turns.map { $0 ? .unrelated : .pause }),
            Self.input(2, .unrelated, turns.map { $0 ? .pause : .unrelated }),
            Self.input(3, .unrelated, Self.repeated(.unrelated, 12)),
        ])
        #expect(Self.moves(steps) == 0, "\(steps.map(\.lines))")
    }

    /// A 40 s pause of the reference and a synced microphone beside an unrelated input moves nothing and keeps
    /// both in the mix (BLOCKER 1 of the third version's review).
    @Test func aPauseBesideAnUnrelatedInputMovesNothing() {
        let speaks = Self.repeated(Sound.speech, 2) + Self.repeated(.pause, 4) + Self.repeated(.speech, 2)
        let steps = Self.steps([
            Self.input(1, .microphone, lag: 0, speaks),
            Self.input(2, .microphone, lag: 0.5, speaks),
            Self.input(3, .unrelated, Self.repeated(.unrelated, 8)),
        ])
        #expect(!steps.contains { $0.movedBySound }, "\(steps.map(\.lines))")
        #expect(steps.allSatisfy { $0.mixed.contains { $0.hasPrefix("u2-") } && Self.isNear(Self.delay(of: "u2", in: $0), 0.5) })
    }

    /// The reference moves to the input the most others count against, not the lowest-numbered one with a
    /// counted window (D89).
    @Test func aMoveGoesToTheInputTheMostOthersCountAgainst() {
        let window = { (lag: Double, counts: Bool) in AudioDelay.Window(lag: lag, clarity: counts ? 30 : 5) }
        let names = ["u1", "u2", "u3", "u4"]
        let candidates = names.enumerated().map { AudioDelays.Candidate(file: "\($1).mov", uid: $1, number: $0 + 1) }
        let files = Dictionary(uniqueKeysWithValues: candidates.map { ($0.file, $0.uid) })
        var delays = AudioDelays()
        _ = delays.update(files: files, reference: "u1.mov")
        let measurement = AudioDelays.Measurement(
            reference: "u1.mov", referenceUID: "u1",
            files: names.dropFirst().map { .init(file: "\($0).mov", uid: $0, window: window(0, false), hasSound: true) },
            pairs: [
                .init(reference: "u2.mov", other: "u3.mov", window: window(0.1, true)),
                .init(reference: "u2.mov", other: "u4.mov", window: window(0.2, false)),
                .init(reference: "u3.mov", other: "u4.mov", window: window(0.3, true)),
            ])
        let outcome = delays.measured(measurement, files: files, candidates: candidates, at: 10)
        #expect(delays.referenceDevice == "u3", "\(outcome.lines)")
        #expect(outcome.delays["u2.mov"]?.delay == -0.1 && outcome.delays["u4.mov"]?.delay == 0.3, "\(outcome.lines)")
    }

    /// The reference's capture ends: the lowest-numbered input with an audio delay takes it (D80, D85).
    @Test func aReferenceWhoseCaptureEndsGoesToTheLowestNumberWithAnAudioDelay() {
        let steps = Self.steps([
            Self.input(1, .microphone, lag: 0, [.speech, .noAudio, .noAudio]),
            Self.input(2, .microphone, lag: 0.3, Self.repeated(.roomSpeech, 3)),
            Self.input(3, .microphone, lag: 0.1, Self.repeated(.speech, 3)),
        ])
        #expect(Self.delay(of: "u2", in: steps[0]) != nil && Self.delay(of: "u3", in: steps[0]) != nil, "\(steps[0].lines)")
        #expect(steps[1].measuredAgainst == "u2", "\(steps.map(\.lines))")
    }

    /// The reference's capture ends: an input with an audio delay takes it before a lower-numbered one without,
    /// re-based, nothing started over (D80, D85).
    @Test func aReferenceWhoseCaptureEndsPrefersAnInputWithAnAudioDelay() {
        let steps = Self.steps([
            Self.input(1, .microphone, lag: 0, [.speech, .noAudio, .noAudio]),
            Self.input(2, .microphone, lag: 0.3, [.pause, .speech, .speech]),
            Self.input(3, .microphone, lag: 0.1, Self.repeated(.speech, 3)),
        ])
        #expect(Self.delay(of: "u2", in: steps[0]) == nil && Self.delay(of: "u3", in: steps[0]) != nil, "\(steps[0].lines)")
        #expect(steps[1].measuredAgainst == "u3", "\(steps.map(\.lines))")
        #expect(!steps.flatMap(\.lines).contains { $0.hasSuffix("every input starts over") }, "\(steps.map(\.lines))")
    }

    /// A measurement against a reference that moved while it ran counts no lag, though its windows counted: the
    /// input whose first window counted in it stays without an audio delay. The reference moves as its capture
    /// ends, to the lowest-numbered input with an audio delay (D80, D85).
    @Test func aMeasurementAgainstAReferenceThatMovedCountsNoLag() throws {
        let inputs = [
            Self.input(1, .microphone, lag: 0, Self.repeated(.speech, 3)),
            Self.input(2, .microphone, lag: 0.5, Self.repeated(.speech, 3)),
            Self.input(3, .microphone, lag: 0.2, [.pause, .speech, .pause]),
        ]
        let speech = AudioDelayInvariantTests.speech(measurements: 3, seed: 1)
        var random = SeededRandom(seed: 3)
        func window(_ input: Input, _ measurement: Int) -> [Float] {
            AudioDelayInvariantTests.window(input.sounds[measurement], input: input, measurement: measurement, speech: speech, random: &random)
        }
        let candidates = inputs.map { AudioDelays.Candidate(file: "\($0.uid).mov", uid: $0.uid, number: $0.number) }
        let files = Dictionary(uniqueKeysWithValues: candidates.map { ($0.file, $0.uid) })
        func measure(_ measurement: Int) -> AudioDelays.Measurement {
            let reference = window(inputs[0], measurement)
            return AudioDelays.measure(reference: ("u1.mov", "u1"), others: inputs.dropFirst().map {
                (file: "\($0.uid).mov", uid: $0.uid, reference: reference, other: window($0, measurement))
            }, measuresPairs: true)
        }
        var delays = AudioDelays()
        _ = delays.update(files: files, reference: "u1.mov")
        _ = delays.measured(measure(0), files: files, candidates: candidates, at: 10)
        let stale = measure(1)
        let (remaining, remainingFiles) = (Array(candidates.dropFirst()), files.filter { $0.value != "u1" })
        let reference = try #require(delays.reference(among: remaining))
        _ = delays.update(files: remainingFiles, reference: reference.file, at: 15)
        try #require(delays.referenceDevice == "u2")
        let outcome = delays.measured(stale, files: remainingFiles, candidates: remaining, at: 20)
        #expect(outcome.delays["u3.mov"] == nil, "\(outcome.lines)")
        #expect(outcome.lines.contains { $0.hasPrefix("counted lags of u2.mov, u3.mov dropped: measured against u1.mov") })
    }

    /// A window's lag of `other` behind `reference` is the negative of the swapped pair's, with the same clarity,
    /// within rounding, so a pair measured once gives the lags against either.
    @Test func aWindowSwappedGivesTheNegativeLag() throws {
        let input = Self.input(2, .microphone, lag: 0.25, [])
        let speech = AudioDelayInvariantTests.speech(measurements: 2, seed: 5)
        var random = SeededRandom(seed: 6)
        let a = AudioDelayInvariantTests.window(.speech, input: Self.input(1, .microphone, lag: 0, []), measurement: 0, speech: speech, random: &random)
        let b = AudioDelayInvariantTests.window(.speech, input: input, measurement: 0, speech: speech, random: &random)
        let forward = try #require(AudioDelay.window(reference: a, other: b))
        let backward = try #require(AudioDelay.window(reference: b, other: a))
        #expect(forward.lag == -backward.lag && abs(forward.clarity - backward.clarity) < 0.01, "\(forward) \(backward)")
    }
}
