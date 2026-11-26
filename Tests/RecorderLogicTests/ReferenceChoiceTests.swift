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
    /// hear the talker. Nothing is synced, so the first reference miss tries the microphone with the most action, and the
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
        #expect(steps.flatMap(\.lines).filter { $0.contains("every candidate tried") }.count == 1, "\(steps.map(\.lines))")
    }

    /// Once an input is synced, a reference that stops correlating is never tried elsewhere: no start-over throws
    /// the audio delays away; it moves only on no audio or its capture's end (D80, D85, D89).
    @Test func onceSomethingIsSyncedAReferenceMissTriesNothing() throws {
        let steps = Self.steps([
            Self.input(1, .microphone, lag: 0, [.speech] + Self.repeated(.hum, 5)),
            Self.input(2, .microphone, lag: 0.3, Self.repeated(.roomSpeech, 6)),
            Self.input(3, .unrelated, Self.repeated(.unrelated, 6)),
        ])
        let synced = try #require(Self.delay(of: "u2", in: steps[0]))
        #expect(abs(synced - 0.3) < 0.002)
        #expect(steps.allSatisfy { $0.reference == "u1" && $0.triedOn == nil }, "\(steps.map(\.lines))")
        #expect(steps.allSatisfy { Self.delay(of: "u2", in: $0) == synced && Self.delay(of: "u3", in: $0) == nil })
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
            })
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

    /// The reference's capture ends: the lowest-numbered input with an audio delay takes it, not the one with
    /// the most action (D80, D85).
    @Test func aReferenceWhoseCaptureEndsGoesToTheLowestNumberWithAnAudioDelay() throws {
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

    /// Every candidate tried beside a flat input 1: the reference goes to the tried input with the highest action
    /// score, not the last one tried (D89).
    @Test func everyCandidateTriedBesideAFlatOriginSettlesOnTheMostAction() {
        let steps = Self.steps([
            Self.input(1, .flat, Self.repeated(.hum, 6)),
            Self.input(2, .unrelated, Self.repeated(.unrelated, 6)),
            Self.input(3, .microphone, lag: 0, Self.repeated(.roomSpeech, 6)),
        ])
        #expect(steps.compactMap(\.triedOn) == ["u2", "u3"], "\(steps.map(\.lines))")
        #expect(steps.last?.reference == "u2", "\(steps.map(\.lines))")
    }

    /// The reference never tries itself: after the tried inputs' captures end, the input the reference fell to
    /// tries only the others (D89).
    @Test func theReferenceNeverTriesItself() {
        let steps = Self.steps([
            Self.input(1, .flat, [.hum] + Self.repeated(.noAudio, 3)),
            Self.input(2, .unrelated, [.unrelated] + Self.repeated(.noAudio, 3)),
            Self.input(3, .unrelated, Self.repeated(.unrelated, 4)),
            Self.input(4, .unrelated, Self.repeated(.unrelated, 4)),
        ])
        #expect(steps.allSatisfy { $0.triedOn != $0.measuredAgainst }, "\(steps.map(\.lines))")
        #expect(steps.flatMap(\.lines).allSatisfy { !$0.hasPrefix("reference u3-1.mov: ") || !$0.hasSuffix("tries u3-1.mov") })
        #expect(steps.contains { $0.triedOn == "u4" }, "\(steps.map(\.lines))")
    }

    /// Another input's file starting again does not end the try episode: an input once tried is not tried
    /// again, only the input whose new file started may be (D89).
    @Test func aNewFileOfAnotherInputDoesNotEndTheEpisode() {
        let toggling: [Sound] = (0..<10).map { $0 % 2 == 0 ? .unrelated : .noAudio }
        let steps = Self.steps([
            Self.input(1, .flat, Self.repeated(.hum, 10)),
            Self.input(2, .unrelated, Self.repeated(.unrelated, 10)),
            Self.input(3, .unrelated, Self.repeated(.unrelated, 10)),
            Self.input(4, .unrelated, toggling),
        ])
        #expect(steps.filter { $0.triedOn == "u2" }.count == 1, "\(steps.map(\.lines))")
        #expect(steps.filter { $0.triedOn == "u3" }.count == 1, "\(steps.map(\.lines))")
    }

    /// A tried input's new file makes it a candidate again, though the episode settled: input 3 comes back with
    /// speech that input 4, tried before, shares, and the try syncs them (D89).
    @Test func aTriedInputsNewFileMakesItACandidateAgain() {
        let steps = Self.steps([
            Self.input(1, .flat, Self.repeated(.hum, 8)),
            Self.input(2, .unrelated, Self.repeated(.unrelated, 8)),
            Self.input(3, .microphone, lag: 0, [.unrelated, .unrelated, .noAudio, .noAudio] + Self.repeated(.speech, 4)),
            Self.input(4, .microphone, lag: 0.2, Self.repeated(.gatedUnrelated, 4) + Self.repeated(.speech, 4)),
        ])
        #expect(steps.filter { $0.triedOn == "u3" }.count == 2, "\(steps.map(\.lines))")
        #expect(steps.last.flatMap { Self.delay(of: "u4", in: $0) } != nil, "\(steps.map(\.lines))")
    }

    /// A window counted against a reference that was tried ends the episode, logged once (D89).
    @Test func aCountedWindowEndsTheEpisodeOnce() {
        let steps = Self.steps([
            Self.input(1, .flat, Self.repeated(.hum, 6)),
            Self.input(2, .unrelated, Self.repeated(.unrelated, 6)),
            Self.input(3, .microphone, lag: 0, [.unrelated] + Self.repeated(.speech, 5)),
            Self.input(4, .microphone, lag: 0.1, [.pause, .pause] + Self.repeated(.speech, 4)),
        ])
        let ends = steps.flatMap(\.lines).filter { $0.hasSuffix("a window counted against it, it stays the reference") }
        #expect(ends.count == 1, "\(steps.map(\.lines))")
    }

    /// The flat threshold lies between the owner's dock line-in, at most 2.9 dB in the replayed recordings, and
    /// speech behind a gate, which the generator's windows score from 4.1 dB (D89).
    @Test func theFlatThresholdLiesBetweenAnEmptyLineInAndGatedSpeech() {
        #expect(2.9 < RecorderValues.actionScoreFlat)
        var lowest = Double.infinity
        for seed in UInt64(1)...40 {
            let speech = AudioDelayInvariantTests.speech(measurements: 6, seed: seed)
            var random = SeededRandom(seed: seed &+ 2000)
            let input = Self.input(2, .microphone, lag: 0.1, [])
            for measurement in 0..<6 {
                let window = AudioDelayInvariantTests.window(.gatedSpeech, input: input, measurement: measurement, speech: speech, random: &random)
                lowest = min(lowest, AudioDelay.actionScore(window))
            }
        }
        #expect(lowest >= RecorderValues.actionScoreFlat, "\(lowest)")
    }
}
