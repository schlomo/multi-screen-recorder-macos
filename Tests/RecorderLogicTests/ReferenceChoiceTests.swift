import Testing
@testable import RecorderLogic

/// The reference rules (D89) in hand-written scenarios, through the recorder's own calls
/// (`AudioDelayInvariantTests.run`): evidence first, the action score only filters and orders the tries.
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

    static func moves(_ steps: [AudioDelayInvariantTests.Step]) -> Int { steps.filter(\.movedBySound).count }

    /// The owner's recordings: input 1 a dock's line-in with nothing connected, near-silence; three microphones
    /// hear the talker. Nothing is synced, so the first stall tries the microphone with the most action, and the
    /// others sync against it at the next measurement.
    @Test func aNearSilentInput1HandsTheReferenceOnAtTheFirstMeasurement() throws {
        let steps = Self.steps([
            Self.input(1, .flat, Self.repeated(.pause, 4)),
            Self.input(2, .microphone, lag: 0.5, Self.repeated(.speech, 4)),
            Self.input(3, .microphone, lag: 0, Self.repeated(.speech, 4)),
            Self.input(4, .microphone, lag: 0.1, Self.repeated(.speech, 4)),
        ])
        #expect(steps[0].triedOn == "u2", "\(steps[0].lines)")
        let second = try #require(steps.dropFirst().first)
        #expect(Self.delay(of: "u3", in: second).map { abs($0 + 0.5) < 0.002 } == true, "\(second.lines)")
        #expect(Self.delay(of: "u4", in: second).map { abs($0 + 0.4) < 0.002 } == true, "\(second.lines)")
    }

    /// A try goes to the input with the most action, not to the lowest number.
    @Test func aTryGoesToTheMostAction() {
        let steps = Self.steps([
            Self.input(1, .flat, Self.repeated(.pause, 2)),
            Self.input(2, .microphone, lag: 0, Self.repeated(.roomSpeech, 2)),
            Self.input(3, .microphone, lag: 0.1, Self.repeated(.speech, 2)),
        ])
        #expect(steps[0].triedOn == "u3", "\(steps[0].lines)")
        #expect(steps[0].lines.contains { $0.contains("; candidates u3-1.mov ") }, "\(steps[0].lines)")
    }

    /// A loud steady hum is never tried: not as input 1 beside microphones, not beside a lone microphone.
    @Test func aHumIsNeverTried() {
        let beside = Self.steps([
            Self.input(1, .flat, Self.repeated(.hum, 8)),
            Self.input(2, .microphone, lag: 0, Self.repeated(.speech, 2) + Self.repeated(.pause, 4) + Self.repeated(.speech, 2)),
            Self.input(3, .microphone, lag: 0.2, Self.repeated(.speech, 2) + Self.repeated(.pause, 4) + Self.repeated(.speech, 2)),
        ])
        #expect(beside.first?.triedOn == "u2", "\(beside.map(\.lines))")
        #expect(beside.allSatisfy { $0.reference != "u1" }, "\(beside.map(\.lines))")
        let lone = Self.steps([
            Self.input(1, .microphone, lag: 0, Self.repeated(.speech, 6)),
            Self.input(2, .flat, Self.repeated(.hum, 6)),
        ])
        #expect(lone.allSatisfy { $0.reference == "u1" && $0.triedOn == nil }, "\(lone.map(\.lines))")
    }

    /// B-1 of the review: an input with unrelated sound and more action, gated or not, never keeps the
    /// reference from microphones that sync: as input 1 it hands it on, as input 3 it never gets it.
    @Test(arguments: [Sound.unrelated, .gatedUnrelated])
    func anUnrelatedInputWithMoreActionNeverKeepsTheReference(unrelated: Sound) {
        let first = Self.steps([
            Self.input(1, .unrelated, Self.repeated(unrelated, 8)),
            Self.input(2, .microphone, lag: 0, Self.repeated(.roomSpeech, 8)),
            Self.input(3, .microphone, lag: 0.1, Self.repeated(.roomSpeech, 8)),
        ])
        #expect(first.last?.reference != "u1", "\(first.map(\.lines))")
        #expect(first.last.flatMap { Self.delay(of: "u3", in: $0) ?? Self.delay(of: "u2", in: $0) } != nil)
        let third = Self.steps([
            Self.input(1, .microphone, lag: 0, Self.repeated(.roomSpeech, 8)),
            Self.input(2, .microphone, lag: 0.1, Self.repeated(.roomSpeech, 8)),
            Self.input(3, .unrelated, Self.repeated(unrelated, 8)),
        ])
        #expect(third.allSatisfy { $0.reference == "u1" }, "\(third.map(\.lines))")
        #expect(third.last.flatMap { Self.delay(of: "u2", in: $0) }.map { abs($0 - 0.1) < 0.002 } == true)
    }

    /// M-1 of the review: a lone microphone beside an unrelated input, the microphone pausing for 40 s: at most
    /// one try and the move back, then the microphone is the reference and in the mix for good.
    @Test func aLoneMicrophoneBesideAnUnrelatedInputGetsTheReferenceBack() {
        let steps = Self.steps([
            Self.input(1, .microphone, lag: 0, Self.repeated(.speech, 3) + Self.repeated(.pause, 4) + Self.repeated(.speech, 7)),
            Self.input(2, .unrelated, Self.repeated(.unrelated, 14)),
        ])
        #expect(Self.moves(steps) <= 2, "\(steps.map(\.lines))")
        #expect(steps.suffix(7).allSatisfy { $0.reference == "u1" && $0.mixed.contains { $0.hasPrefix("u1-") } }, "\(steps.map(\.lines))")
    }

    /// M-2 of the review: a healthy recording whose input 1, a room microphone, has less action keeps its first
    /// measurement's counted lags: every input is synced after it, as before D89.
    @Test func aHealthyFirstMeasurementKeepsItsCountedLags() {
        let steps = Self.steps([
            Self.input(1, .microphone, lag: 0.05, Self.repeated(.roomSpeech, 3)),
            Self.input(2, .microphone, lag: 0, Self.repeated(.speech, 3)),
            Self.input(3, .microphone, lag: 0.1, Self.repeated(.speech, 3)),
        ])
        #expect(steps.allSatisfy { $0.reference == "u1" && !$0.movedBySound })
        #expect(Self.delay(of: "u2", in: steps[0]).map { abs($0 + 0.05) < 0.002 } == true, "\(steps[0].lines)")
        #expect(Self.delay(of: "u3", in: steps[0]).map { abs($0 - 0.05) < 0.002 } == true, "\(steps[0].lines)")
    }

    /// E2 of the review: two talkers taking turns of 60 s, each on a microphone that hears only its own: a
    /// bounded number of moves, a try and the move back once the first talker speaks again, then the reference
    /// stays for the two turns after it.
    @Test func twoTalkersThatNeverCorrelateMoveTheReferenceABoundedNumberOfTimes() throws {
        let turns = (0..<24).map { ($0 / 6) % 2 == 0 }
        let steps = Self.steps([
            Self.input(1, .unrelated, turns.map { $0 ? .unrelated : .pause }),
            Self.input(2, .unrelated, turns.map { $0 ? .pause : .unrelated }),
        ])
        #expect(Self.moves(steps) <= 2, "\(steps.map(\.lines))")
        let back = try #require(steps.firstIndex { $0.lines.contains { $0.contains("every candidate tried, back to ") } })
        #expect(back <= 12, "\(steps.map(\.lines))")
        #expect(!steps.dropFirst(back + 1).contains { $0.movedBySound }, "\(steps.map(\.lines))")
    }

    /// A reference that stops correlating hands the reference to an input with an audio delay before one with
    /// more action and none: re-based, every audio delay kept, nothing started over.
    @Test func aStallPrefersAnInputWithAnAudioDelay() throws {
        let steps = Self.steps([
            Self.input(1, .microphone, lag: 0, [.speech] + Self.repeated(.hum, 5)),
            Self.input(2, .microphone, lag: 0.3, Self.repeated(.roomSpeech, 6)),
            Self.input(3, .microphone, lag: 0.1, [.pause] + Self.repeated(.speech, 5)),
        ])
        let synced = try #require(Self.delay(of: "u2", in: steps[0]))
        #expect(abs(synced - 0.3) < 0.002)
        #expect(steps.contains { $0.triedOn == "u2" }, "\(steps.map(\.lines))")
        #expect(!steps.contains { $0.lines.contains { $0.hasSuffix("every input starts over") } }, "\(steps.map(\.lines))")
        #expect(steps.allSatisfy { Self.delay(of: "u2", in: $0) == synced })
        #expect(steps.last.flatMap { Self.delay(of: "u3", in: $0) }.map { abs($0 - 0.1) < 0.002 } == true, "\(steps.map(\.lines))")
    }

    /// Every candidate tried while it had only unrelated sound, input 1 a hum: the move back never goes to the
    /// flat input, so when the talkers start after the tries they sync against the last one tried.
    @Test func everyCandidateTriedNeverLeavesTheReferenceOnAFlatInput() {
        let steps = Self.steps([
            Self.input(1, .flat, Self.repeated(.hum, 9)),
            Self.input(2, .microphone, lag: 0, Self.repeated(.unrelated, 3) + Self.repeated(.speech, 6)),
            Self.input(3, .microphone, lag: 0.2, Self.repeated(.unrelated, 3) + Self.repeated(.speech, 6)),
        ])
        #expect(steps.dropFirst().allSatisfy { $0.reference != "u1" }, "\(steps.map(\.lines))")
        #expect(steps.last.flatMap { Self.delay(of: "u2", in: $0) ?? Self.delay(of: "u3", in: $0) } != nil, "\(steps.map(\.lines))")
    }

    /// A pause of the reference and a synced microphone for 20 s beside an unrelated input with action moves
    /// nothing and keeps both in the mix (B1 of the first review).
    @Test func aPauseBesideAnUnrelatedInputMovesNothing() {
        let speaks = Self.repeated(Sound.speech, 2) + Self.repeated(.pause, 2) + Self.repeated(.speech, 2)
        let steps = Self.steps([
            Self.input(1, .microphone, lag: 0, speaks),
            Self.input(2, .microphone, lag: 0.5, speaks),
            Self.input(3, .unrelated, Self.repeated(.unrelated, 6)),
        ])
        #expect(!steps.contains { $0.movedBySound }, "\(steps.map(\.lines))")
        #expect(steps.allSatisfy { $0.mixed.contains { $0.hasPrefix("u2-") } })
    }

    /// A measurement against a reference that moved while it ran counts no lag, though its windows counted: the
    /// input whose first window counted in it stays without an audio delay.
    @Test func aMeasurementAgainstAReferenceThatMovedCountsNoLag() throws {
        let inputs = [
            Self.input(1, .microphone, lag: 0, [.speech, .speech, .hum, .hum, .hum]),
            Self.input(2, .microphone, lag: 0.5, Self.repeated(.speech, 5)),
            Self.input(3, .microphone, lag: 0.2, [.pause] + Self.repeated(.speech, 4)),
        ]
        let speech = AudioDelayInvariantTests.speech(measurements: 5, seed: 1)
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
            })
        }
        var delays = AudioDelays()
        _ = delays.update(files: files, reference: "u1.mov")
        _ = delays.measured(measure(0), files: files, candidates: candidates, at: 10)
        let stale = measure(1)
        for measurement in 2...4 { _ = delays.measured(measure(measurement), files: files, candidates: candidates, at: Double(measurement + 1) * 10) }
        try #require(delays.referenceDevice == "u2")
        let outcome = delays.measured(stale, files: files, candidates: candidates, at: 20)
        #expect(outcome.delays["u3.mov"] == nil, "\(outcome.lines)")
        #expect(outcome.lines.contains { $0.hasPrefix("counted lags of u2.mov, u3.mov dropped: measured against u1.mov") })
    }
}
