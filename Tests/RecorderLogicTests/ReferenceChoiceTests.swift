import Testing
@testable import RecorderLogic

/// The reference rules (D90) in hand-written scenarios, through the recorder's own calls
/// (`AudioDelayInvariantTests.run`): the reference moves for lack of sync only to an input the measurement proves.
@Suite struct ReferenceChoiceTests {
    typealias Input = AudioDelayInvariantTests.Input
    typealias Sound = AudioDelayInvariantTests.Sound

    static func input(_ number: Int, _ kind: AudioDelayInvariantTests.Kind, lag: Double = 0, _ sounds: [Sound]) -> Input {
        Input(uid: "u\(number)", number: number, kind: kind, lag: lag, sounds: sounds)
    }

    static func repeated(_ sound: Sound, _ count: Int) -> [Sound] { Array(repeating: sound, count: count) }

    /// Each measurement's step, in order.
    static func steps(_ inputs: [Input], seed: UInt64 = 1) async -> [AudioDelayInvariantTests.Step] {
        var steps: [AudioDelayInvariantTests.Step] = []
        await AudioDelayInvariantTests.run(.init(inputs: inputs), seed: seed) { _, step, _ in steps.append(step) }
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
    @Test func aNearSilentInput1HandsTheReferenceOnAtTheFirstMeasurement() async {
        let steps = await Self.steps([
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
    @Test func aHumIsNeverTheReferenceBesideMicrophones() async {
        let beside = await Self.steps([
            Self.input(1, .steady, Self.repeated(.hum, 6)),
            Self.input(2, .microphone, lag: 0, Self.repeated(.speech, 2) + Self.repeated(.pause, 2) + Self.repeated(.speech, 2)),
            Self.input(3, .microphone, lag: 0.2, Self.repeated(.speech, 2) + Self.repeated(.pause, 2) + Self.repeated(.speech, 2)),
        ])
        #expect(beside.allSatisfy { $0.reference == "u2" }, "\(beside.map(\.lines))")
        let lone = await Self.steps([
            Self.input(1, .microphone, lag: 0, Self.repeated(.speech, 4)),
            Self.input(2, .steady, Self.repeated(.hum, 4)),
        ])
        #expect(lone.allSatisfy { $0.reference == "u1" }, "\(lone.map(\.lines))")
    }

    /// An input with unrelated sound, gated or not, never takes the reference from
    /// microphones that sync: as input 1 it hands it on to them, as input 3 it never gets it.
    @Test(arguments: [Sound.unrelated, .gatedUnrelated])
    func anUnrelatedInputNeverKeepsTheReference(unrelated: Sound) async {
        let first = await Self.steps([
            Self.input(1, .unrelated, Self.repeated(unrelated, 4)),
            Self.input(2, .microphone, lag: 0, Self.repeated(.roomSpeech, 4)),
            Self.input(3, .microphone, lag: 0.1, Self.repeated(.roomSpeech, 4)),
        ])
        #expect(first.allSatisfy { $0.reference == "u2" }, "\(first.map(\.lines))")
        #expect(Self.isNear(Self.delay(of: "u3", in: first[0]), 0.1), "\(first[0].lines)")
        let third = await Self.steps([
            Self.input(1, .microphone, lag: 0, Self.repeated(.roomSpeech, 4)),
            Self.input(2, .microphone, lag: 0.1, Self.repeated(.roomSpeech, 4)),
            Self.input(3, .unrelated, Self.repeated(unrelated, 4)),
        ])
        #expect(third.allSatisfy { $0.reference == "u1" }, "\(third.map(\.lines))")
        #expect(Self.isNear(third.last.flatMap { Self.delay(of: "u2", in: $0) }, 0.1))
    }

    /// Input 1's talker starts after 30 s, input 2 has room speech all along, input 3
    /// unrelated sound: nothing proves another reference, so nothing moves, and input 2 syncs once input 1 speaks,
    /// as under main's rules.
    @Test func aTalkerStartingLateOnInput1SyncsAsBefore() async {
        let steps = await Self.steps([
            Self.input(1, .microphone, lag: 0, Self.repeated(.pause, 3) + Self.repeated(.speech, 4)),
            Self.input(2, .microphone, lag: 0.1, Self.repeated(.roomSpeech, 7)),
            Self.input(3, .unrelated, Self.repeated(.unrelated, 7)),
        ])
        #expect(steps.allSatisfy { $0.reference == "u1" }, "\(steps.map(\.lines))")
        #expect(Self.isNear(steps.last.flatMap { Self.delay(of: "u2", in: $0) }, 0.1), "\(steps.map(\.lines))")
    }

    /// A lone microphone beside an unrelated input whose file
    /// ends and starts again, the microphone pausing: nothing moves, the microphone stays the anchor and in the mix.
    @Test func aLoneMicrophoneBesideAnUnrelatedInputKeepsTheReference() async {
        let steps = await Self.steps([
            Self.input(1, .microphone, lag: 0, Self.repeated(.speech, 3) + Self.repeated(.pause, 4) + Self.repeated(.speech, 3)),
            Self.input(2, .unrelated, Self.repeated(.unrelated, 4) + [.noAudio] + Self.repeated(.unrelated, 5)),
        ])
        #expect(steps.allSatisfy { $0.reference == "u1" && $0.anchor == "u1" && $0.mixed.contains { $0.hasPrefix("u1-") } },
                "\(steps.map(\.lines))")
    }

    /// Input 1 matches once, as a burst on the dock gives, then hums: the microphones prove input 2, synced by
    /// that one window, and the reference moves to it keeping every audio delay (D90); every microphone ends
    /// synced against input 1, the anchor.
    @Test func aReferenceThatHumsAfterOneMatchHandsOnToTheSyncedInput() async {
        let steps = await Self.steps([
            Self.input(1, .steady, [.speech] + Self.repeated(.hum, 4)),
            Self.input(2, .microphone, lag: 0.3, Self.repeated(.speech, 5)),
            Self.input(3, .microphone, lag: 0.1, [.pause] + Self.repeated(.speech, 4)),
            Self.input(4, .microphone, lag: 0.2, [.pause] + Self.repeated(.speech, 4)),
        ])
        #expect(Self.delay(of: "u2", in: steps[0]) != nil && steps[1].anchorGroupBefore == 1, "\(steps[0].lines)")
        #expect(steps[1].movedBySound && steps[1].reference == "u2" && steps[1].startOvers.isEmpty, "\(steps[1].lines)")
        #expect(steps.allSatisfy { $0.anchor == "u1" })
        #expect(Self.isNear(steps.last.flatMap { Self.delay(of: "u2", in: $0) }, 0.3), "\(steps.map(\.lines))")
        #expect(Self.isNear(steps.last.flatMap { Self.delay(of: "u3", in: $0) }, 0.1), "\(steps.map(\.lines))")
        #expect(Self.isNear(steps.last.flatMap { Self.delay(of: "u4", in: $0) }, 0.2), "\(steps.map(\.lines))")
    }

    /// Two counted windows put input 2 in the anchor's group; input 1 then hums while inputs 2 and 3 talk: the
    /// reference moves to input 2, nothing starting over, and input 3 syncs against the anchor (D90).
    @Test func aReferenceThatGoesQuietAfterTheSyncHandsOnWithoutStartingOver() async {
        let steps = await Self.steps([
            Self.input(1, .steady, [.speech, .speech] + Self.repeated(.hum, 3)),
            Self.input(2, .microphone, lag: 0.3, Self.repeated(.speech, 5)),
            Self.input(3, .microphone, lag: 0.1, [.pause, .pause] + Self.repeated(.speech, 3)),
        ])
        #expect(steps[2].anchorGroupBefore == 2, "\(steps.map(\.lines))")
        #expect(steps[2].movedBySound && steps[2].reference == "u2", "\(steps.map(\.lines))")
        #expect(steps.allSatisfy { $0.startOvers.isEmpty && $0.anchor == "u1" }, "\(steps.map(\.lines))")
        #expect(Self.isNear(steps.last.flatMap { Self.delay(of: "u2", in: $0) }, 0.3), "\(steps.map(\.lines))")
        #expect(Self.isNear(steps.last.flatMap { Self.delay(of: "u3", in: $0) }, 0.1), "\(steps.map(\.lines))")
    }

    /// A healthy recording whose input 1, a room microphone, syncs everything at the first measurement: nothing
    /// moves, as before D89.
    @Test func aHealthyFirstMeasurementKeepsItsCountedLags() async {
        let steps = await Self.steps([
            Self.input(1, .microphone, lag: 0.05, Self.repeated(.roomSpeech, 3)),
            Self.input(2, .microphone, lag: 0, Self.repeated(.speech, 3)),
            Self.input(3, .microphone, lag: 0.1, Self.repeated(.speech, 3)),
        ])
        #expect(steps.allSatisfy { $0.reference == "u1" && !$0.movedBySound })
        #expect(Self.isNear(Self.delay(of: "u2", in: steps[0]), -0.05), "\(steps[0].lines)")
        #expect(Self.isNear(Self.delay(of: "u3", in: steps[0]), 0.05), "\(steps[0].lines)")
    }

    /// Two talkers taking turns of 60 s, each on a microphone that hears only its own:
    /// nothing proves another reference, so nothing moves.
    @Test func twoTalkersThatNeverCorrelateMoveNothing() async {
        let turns = (0..<12).map { ($0 / 6) % 2 == 0 }
        let steps = await Self.steps([
            Self.input(1, .unrelated, turns.map { $0 ? .unrelated : .pause }),
            Self.input(2, .unrelated, turns.map { $0 ? .pause : .unrelated }),
            Self.input(3, .unrelated, Self.repeated(.unrelated, 12)),
        ])
        #expect(Self.moves(steps) == 0, "\(steps.map(\.lines))")
    }

    /// A 40 s pause of the reference and a synced microphone beside an unrelated input moves nothing and keeps
    /// both in the mix.
    @Test func aPauseBesideAnUnrelatedInputMovesNothing() async {
        let speaks = Self.repeated(Sound.speech, 2) + Self.repeated(.pause, 4) + Self.repeated(.speech, 2)
        let steps = await Self.steps([
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
            reference: "u1.mov",
            files: names.dropFirst().map { .init(file: "\($0).mov", window: window(0, false)) },
            pairs: [
                .init(reference: "u2.mov", other: "u3.mov", window: window(0.1, true)),
                .init(reference: "u2.mov", other: "u4.mov", window: window(0.2, false)),
                .init(reference: "u3.mov", other: "u4.mov", window: window(0.3, true)),
            ])
        let outcome = delays.measured(measurement, files: files, candidates: candidates, at: 10)
        #expect(delays.referenceDevice == "u3", "\(outcome.lines)")
        #expect(outcome.delays["u2.mov"]?.delay == -0.1 && outcome.delays["u4.mov"]?.delay == 0.3, "\(outcome.lines)")
    }

    /// A miss move in a measurement whose files include one not known yet (the old anchor's next file): the move
    /// starts every input over, so that file carries nothing over (D89).
    @Test func aMissMoveCarriesNothingOverToAFileNotKnownYet() {
        let window = { (lag: Double, counts: Bool) in AudioDelay.Window(lag: lag, clarity: counts ? 40 : 5) }
        var delays = AudioDelays()
        _ = delays.update(files: ["u1-1.mov": "u1", "u2.mov": "u2", "u3.mov": "u3"], reference: "u1-1.mov")
        let files = ["u1-2.mov": "u1", "u2.mov": "u2", "u3.mov": "u3"]
        let candidates = [AudioDelays.Candidate(file: "u1-2.mov", uid: "u1", number: 1), .init(file: "u2.mov", uid: "u2", number: 2),
                          .init(file: "u3.mov", uid: "u3", number: 3)]
        let measurement = AudioDelays.Measurement(
            reference: "u1-2.mov", files: [.init(file: "u2.mov", window: window(0, false)), .init(file: "u3.mov", window: window(0, false))],
            pairs: [.init(reference: "u2.mov", other: "u3.mov", window: window(0.1, true))])
        let outcome = delays.measured(measurement, files: files, candidates: candidates, at: 10)
        #expect(delays.referenceDevice == "u2", "\(outcome.lines)")
        #expect(!outcome.lines.contains { $0.contains("carries over") } && outcome.delays["u1-2.mov"] == nil, "\(outcome.lines)")
    }

    /// Counted pairs of synced inputs move the reference to the one the most others count against, a tie to the
    /// lowest number, as a re-base: every audio delay stays (D90).
    @Test func countedPairsOfSyncedInputsReBaseKeepingEveryAudioDelay() {
        let window = { (lag: Double, counts: Bool) in AudioDelay.Window(lag: lag, clarity: counts ? 30 : 5) }
        let names = ["u1", "u2", "u3"]
        let candidates = names.enumerated().map { AudioDelays.Candidate(file: "\($1).mov", uid: $1, number: $0 + 1) }
        let files = Dictionary(uniqueKeysWithValues: candidates.map { ($0.file, $0.uid) })
        var delays = AudioDelays()
        _ = delays.update(files: files, reference: "u1.mov")
        for at in [10.0, 20] { _ = delays.update(files: files, reference: "u1.mov", lags: ["u2.mov": 0.2, "u3.mov": 0.1], at: at) }
        #expect(delays.anchorGroup == 3)
        let measurement = AudioDelays.Measurement(
            reference: "u1.mov",
            files: names.dropFirst().map { .init(file: "\($0).mov", window: window(0, false)) },
            pairs: [.init(reference: "u2.mov", other: "u3.mov", window: window(-0.1, true))])
        let outcome = delays.measured(measurement, files: files, candidates: candidates, at: 30)
        #expect(delays.referenceDevice == "u2" && delays.anchor == "u1", "\(outcome.lines)")
        #expect(outcome.lines.contains("reference u1.mov → u2.mov: lags re-based onto the anchor by 200 ms late"), "\(outcome.lines)")
        #expect(outcome.delays["u2.mov"]?.delay == 0.2 && outcome.delays["u3.mov"]?.delay == 0.1, "\(outcome.lines)")
        #expect(outcome.delays["u1.mov"]?.delay == 0 && outcome.cleared.isEmpty, "\(outcome.lines)")
    }

    /// After a re-base the anchor's file shows its own 0 until measured, not one carried over from a previous file
    /// it does not have; once measured, it shows its measured audio delay (D90).
    @Test func theAnchorsRowAfterAReBaseShowsItsOwnZeroUntilMeasured() {
        let window = { (lag: Double, counts: Bool) in AudioDelay.Window(lag: lag, clarity: counts ? 30 : 5) }
        let names = ["u1", "u2", "u3"]
        let candidates = names.enumerated().map { AudioDelays.Candidate(file: "\($1).mov", uid: $1, number: $0 + 1) }
        let files = Dictionary(uniqueKeysWithValues: candidates.map { ($0.file, $0.uid) })
        var delays = AudioDelays()
        _ = delays.update(files: files, reference: "u1.mov")
        for at in [10.0, 20] { _ = delays.update(files: files, reference: "u1.mov", lags: ["u2.mov": 0.2, "u3.mov": 0.1], at: at) }
        let miss = AudioDelays.Measurement(
            reference: "u1.mov", files: ["u2", "u3"].map { .init(file: "\($0).mov", window: window(0, false)) },
            pairs: [.init(reference: "u2.mov", other: "u3.mov", window: window(-0.1, true))])
        let moved = delays.measured(miss, files: files, candidates: candidates, at: 30)
        #expect(delays.referenceDevice == "u2", "\(moved.lines)")
        let shown = delays.shown("u1.mov")
        #expect(shown == .anchor(0), "\(String(describing: shown))")
        let measured = AudioDelays.Measurement(reference: "u2.mov", files: [.init(file: "u1.mov", window: window(-0.15, true))])
        _ = delays.measured(measured, files: files, candidates: candidates, at: 40)
        let measuredShown = delays.shown("u1.mov")
        let isMeasured = if case .synced(_, carriedOver: false)? = measuredShown { true } else { false }
        #expect(isMeasured, "\(String(describing: measuredShown))")
    }

    /// An anchor's file that ended is not measured after a re-base, so the log says so only of one being written.
    @Test func anEndedAnchorFileIsNotSaidToBeMeasuredAfterAReBase() {
        let names = ["u1", "u2", "u3"]
        let candidates = names.enumerated().map { AudioDelays.Candidate(file: "\($1).mov", uid: $1, number: $0 + 1) }
        let files = Dictionary(uniqueKeysWithValues: candidates.map { ($0.file, $0.uid) })
        var delays = AudioDelays()
        _ = delays.update(files: files, reference: "u1.mov")
        for at in [10.0, 20] { _ = delays.update(files: files, reference: "u1.mov", lags: ["u2.mov": 0.2, "u3.mov": 0.1], at: at) }
        let moved = delays.update(files: files, reference: "u2.mov", at: 30, ended: ["u1.mov"])
        #expect(delays.referenceDevice == "u2", "\(moved.lines)")
        #expect(!moved.lines.contains { $0.hasPrefix("u1.mov: the anchor's file") }, "\(moved.lines)")
    }

    /// A stray pair, as one burst on two inputs gives, does not outnumber an anchor whose group holds another
    /// input matched twice: nothing moves. A group of three does, and every input starts over at its input (D90).
    @Test func aStartOverNeedsAGroupThatOutnumbersTheAnchors() {
        let window = { (lag: Double, counts: Bool) in AudioDelay.Window(lag: lag, clarity: counts ? 30 : 5) }
        let names = ["u1", "u2", "u3", "u4", "u5"]
        let candidates = names.enumerated().map { AudioDelays.Candidate(file: "\($1).mov", uid: $1, number: $0 + 1) }
        let files = Dictionary(uniqueKeysWithValues: candidates.map { ($0.file, $0.uid) })
        var delays = AudioDelays()
        _ = delays.update(files: files, reference: "u1.mov")
        for at in [10.0, 20] { _ = delays.update(files: files, reference: "u1.mov", lags: ["u2.mov": 0.2], at: at) }
        #expect(delays.anchorGroup == 2)
        let unsynced = names.dropFirst().map { AudioDelays.Measurement.Measured(file: "\($0).mov", window: window(0, false)) }
        let pair = AudioDelays.Measurement(
            reference: "u1.mov", files: unsynced, pairs: [.init(reference: "u3.mov", other: "u4.mov", window: window(0.1, true))])
        let stays = delays.measured(pair, files: files, candidates: candidates, at: 30)
        #expect(delays.referenceDevice == "u1", "\(stays.lines)")
        #expect(stays.lines.contains("reference u1.mov: u3.mov's group of 2 does not outnumber the anchor's group of 2: nothing moves"),
                "\(stays.lines)")
        let three = AudioDelays.Measurement(reference: "u1.mov", files: unsynced, pairs: [
            .init(reference: "u3.mov", other: "u4.mov", window: window(0.1, true)),
            .init(reference: "u3.mov", other: "u5.mov", window: window(0.2, true)),
        ])
        let moves = delays.measured(three, files: files, candidates: candidates, at: 40)
        #expect(delays.referenceDevice == "u3" && delays.anchor == "u3", "\(moves.lines)")
        #expect(moves.cleared == Set(files.keys) && moves.delays["u2.mov"] == nil, "\(moves.lines)")
        #expect(moves.delays["u4.mov"]?.delay == 0.1 && moves.delays["u5.mov"]?.delay == 0.2, "\(moves.lines)")
    }

    /// The anchor's new file, measured against the reference it handed on to, is synced like any other input's,
    /// so a later miss of that reference moves back to it, re-based, and wipes nothing (D85, D90).
    @Test func theAnchorsNewFileIsSyncedSoAMissWipesNothing() async {
        let steps = await Self.steps([
            Self.input(1, .microphone, lag: 0, [.speech, .noAudio] + Self.repeated(.speech, 8)),
            Self.input(2, .microphone, lag: 0.2, Self.repeated(.speech, 5) + [.pause, .pause] + Self.repeated(.speech, 3)),
            Self.input(3, .microphone, lag: 0.1, Self.repeated(.pause, 5) + Self.repeated(.speech, 5)),
        ])
        #expect(Self.delay(of: "u1", in: steps[4]) != nil, "\(steps.map(\.lines))")
        #expect(steps.allSatisfy { $0.anchor == "u1" } && !steps.flatMap(\.lines).contains { $0.hasSuffix("every input starts over") },
                "\(steps.map(\.lines))")
        #expect(Self.isNear(steps.last.flatMap { Self.delay(of: "u2", in: $0) }, 0.2), "\(steps.map(\.lines))")
    }

    /// The move is decided before anything is applied, so the measurement in which an
    /// input syncs logs no "no clear sound" for it, and the move's start-over says why it happened (D89).
    @Test func aMoveIsDecidedBeforeTheMeasurementIsApplied() async {
        let steps = await Self.steps([
            Self.input(1, .steady, Self.repeated(.noise, 4)),
            Self.input(2, .microphone, lag: 0.2, Self.repeated(.speech, 4)),
            Self.input(3, .microphone, lag: 0.1, [.noAudio, .noAudio] + Self.repeated(.speech, 2)),
        ])
        #expect(steps[2].movedBySound && steps[2].reference == "u2", "\(steps.map(\.lines))")
        #expect(!steps[2].lines.contains { $0.contains("no clear sound") }, "\(steps[2].lines)")
        #expect(steps[2].lines.contains { $0.hasSuffix("u2-1.mov: moved on a reference miss, so it is the new anchor and every input starts over") },
                "\(steps[2].lines)")
    }

    /// The reference's capture ends: the lowest-numbered input with an audio delay takes it (D80, D85).
    @Test func aReferenceWhoseCaptureEndsGoesToTheLowestNumberWithAnAudioDelay() async {
        let steps = await Self.steps([
            Self.input(1, .microphone, lag: 0, [.speech, .noAudio, .noAudio]),
            Self.input(2, .microphone, lag: 0.3, Self.repeated(.roomSpeech, 3)),
            Self.input(3, .microphone, lag: 0.1, Self.repeated(.speech, 3)),
        ])
        #expect(Self.delay(of: "u2", in: steps[0]) != nil && Self.delay(of: "u3", in: steps[0]) != nil, "\(steps[0].lines)")
        #expect(steps[1].measuredAgainst == "u2", "\(steps.map(\.lines))")
    }

    /// The reference's capture ends: an input with an audio delay takes it before a lower-numbered one without,
    /// re-based, nothing started over (D80, D85).
    @Test func aReferenceWhoseCaptureEndsPrefersAnInputWithAnAudioDelay() async {
        let steps = await Self.steps([
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
            return AudioDelays.measure(reference: "u1.mov", others: inputs.dropFirst().map {
                (file: "\($0.uid).mov", reference: reference, other: window($0, measurement))
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
