import Testing
@testable import RecorderLogic

/// A recording's audio delays (D80): which inputs the "Audio inputs" guide track mixes and where it places
/// them, what `recording.json` lists, and what the status window shows.
@Suite struct AudioDelaysTests {
    private typealias Outcome = AudioDelays.Outcome
    private typealias Entry = AudioDelays.Entry

    /// The reference "r.mov" of the device "R" and `files` of devices named by their first letter, in upper case.
    private func writing(_ files: [String], reference: String = "r.mov") -> [String: String] {
        Dictionary(uniqueKeysWithValues: (files + [reference]).map { ($0, String($0.prefix(1)).uppercased()) })
    }

    /// Only the reference is in the guide track from the start; another input joins at its first counted
    /// window, placed earlier by its audio delay; one never measured stays out of it.
    @Test func anInputJoinsTheGuideTrackAtItsFirstAudioDelay() {
        var delays = AudioDelays()
        let first = delays.update(writing: writing(["a.mov", "b.mov"]), reference: "r.mov")
        #expect(first.placements == ["r.mov": 0, "a.mov": nil, "b.mov": nil])
        #expect(first.delays.isEmpty)
        #expect(delays.shown("a.mov") == .notInTheGuideTrackYet)
        #expect(delays.shown("r.mov") == nil)
        let measured = delays.update(writing: writing(["a.mov", "b.mov"]), reference: "r.mov", lags: ["a.mov": 0.5], at: 20)
        #expect(measured.placements == ["r.mov": 0, "a.mov": 0.5, "b.mov": nil])
        #expect(measured.delays == ["a.mov": Entry(delay: 0.5)])
        #expect(measured.leaving.isEmpty && measured.rejoining.isEmpty)
        #expect(delays.shown("a.mov") == .synced(0.5, carriedOver: false))
        #expect(delays.shown("b.mov") == .notInTheGuideTrackYet)
    }

    /// An input earlier than the reference: the reference moves earlier in the guide, the earliest input
    /// stays where it is, and the delays listed are normalized so the earliest is 0, the reference's included.
    @Test func anEarlyInputMovesTheOthersInTheGuideAndIsZeroInTheList() {
        var delays = AudioDelays()
        let outcome = delays.update(writing: writing(["a.mov", "b.mov"]), reference: "r.mov", lags: ["a.mov": -0.3, "b.mov": 0.2], at: 20)
        #expect(outcome.placements.mapValues { $0.map { ($0 * 1e9).rounded() / 1e9 } } == ["a.mov": 0, "r.mov": 0.3, "b.mov": 0.5])
        #expect(outcome.delays.mapValues { ($0.delay * 1e9).rounded() / 1e9 } == ["a.mov": 0, "r.mov": 0.3, "b.mov": 0.5])
        #expect(delays.shown("r.mov") == .synced(0.3, carriedOver: false))
    }

    /// An input out of sync leaves the guide track; the others are placed by the earliest staying input, while
    /// the list stays normalized over every measured file.
    @Test func anEarlyInputThatLeftNoLongerPlacesTheOthers() {
        var delays = AudioDelays()
        let outcome = delays.update(
            writing: writing(["a.mov", "b.mov", "c.mov"]), reference: "r.mov", lags: ["a.mov": -0.9, "b.mov": 0.1, "c.mov": 0], at: 20)
        #expect(outcome.leaving == ["a.mov": -0.9])
        #expect(outcome.placements == ["r.mov": 0, "b.mov": 0.1, "c.mov": 0])
        #expect(outcome.delays.mapValues { ($0.delay * 1e9).rounded() / 1e9 } == ["a.mov": 0, "r.mov": 0.9, "b.mov": 1, "c.mov": 0.9])
        #expect(delays.shown("a.mov") == nil)
    }

    /// A new file of an input whose earlier file had an audio delay starts with it, carried over, until its
    /// own first counted window confirms it; the list names the earlier file while it is carried over.
    @Test func aNewFileOfAnInputCarriesOverItsAudioDelay() {
        var delays = AudioDelays()
        _ = delays.update(writing: writing(["a1.mov"]), reference: "r.mov", lags: ["a1.mov": 0.5], at: 20)
        let carried = delays.update(writing: writing(["a2.mov"]), reference: "r.mov")
        #expect(carried.placements == ["r.mov": 0, "a2.mov": 0.5])
        #expect(carried.delays == ["a2.mov": Entry(delay: 0.5, carriedOverFrom: "a1.mov")])
        #expect(delays.shown("a2.mov") == .synced(0.5, carriedOver: true))
        let confirmed = delays.update(writing: writing(["a2.mov"]), reference: "r.mov", lags: ["a2.mov": 0.51], at: 40)
        #expect(confirmed.delays == ["a2.mov": Entry(delay: 0.5)])
        #expect(delays.shown("a2.mov") == .synced(0.5, carriedOver: false))
    }

    /// A new file of an input whose earlier file was out of the guide track is out at once.
    @Test func aNewFileOfAnInputOutOfTheGuideTrackIsOutAtOnce() {
        var delays = AudioDelays()
        #expect(delays.update(writing: writing(["a1.mov"]), reference: "r.mov", lags: ["a1.mov": 0.9], at: 20).leaving == ["a1.mov": 0.9])
        let next = delays.update(writing: writing(["a2.mov"]), reference: "r.mov")
        #expect(next.leaving == ["a2.mov": 0.9])
        #expect(next.placements == ["r.mov": 0])
    }

    /// Another reference device starts over: no audio delay holds, no carry-over; the same reference
    /// device's new file keeps them.
    @Test func anotherReferenceDeviceStartsOverTheSameOnesNewFileKeepsTheAudioDelays() {
        var delays = AudioDelays()
        _ = delays.update(writing: writing(["a1.mov", "b.mov"]), reference: "r.mov", lags: ["a1.mov": 0.5], at: 20)
        let sameDevice = delays.update(writing: writing(["a1.mov", "b.mov"], reference: "r2.mov"), reference: "r2.mov")
        #expect(sameDevice.placements == ["r2.mov": 0, "a1.mov": 0.5, "b.mov": nil])
        var files = writing(["a2.mov"], reference: "r2.mov")
        files["b.mov"] = "B"
        let other = delays.update(writing: files, reference: "b.mov")
        #expect(other.placements == ["b.mov": 0, "r2.mov": nil, "a2.mov": nil])
        #expect(other.delays.isEmpty)
        #expect(delays.shown("a2.mov") == .notInTheGuideTrackYet)
    }

    /// A file that ended keeps its audio delay in the normalization: an earlier input gone, the others'
    /// listed delays stay (D77).
    @Test func anEndedFileStillCountsInTheNormalization() {
        var delays = AudioDelays()
        _ = delays.update(writing: writing(["a.mov", "b.mov"]), reference: "r.mov", lags: ["a.mov": -0.5, "b.mov": 0.2], at: 20)
        let after = delays.update(writing: writing(["b.mov"]), reference: "r.mov")
        #expect(after.delays.mapValues { ($0.delay * 1e9).rounded() / 1e9 } == ["r.mov": 0.5, "b.mov": 0.7])
        #expect(after.placements.mapValues { $0.map { ($0 * 1e9).rounded() / 1e9 } } == ["r.mov": 0, "b.mov": 0.2])
    }
}
