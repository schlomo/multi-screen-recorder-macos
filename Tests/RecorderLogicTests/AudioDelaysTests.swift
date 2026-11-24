import Testing
@testable import RecorderLogic

/// A recording's audio delays (D80): which inputs the "Audio inputs" guide track mixes and where it places
/// them, what `recording.json` lists, and what the status window shows.
@Suite struct AudioDelaysTests {
    private typealias Outcome = AudioDelays.Outcome
    private typealias Entry = AudioDelays.Entry

    /// The reference "r.mov" of the device "R" and `files` of devices named by their first letter, in upper case.
    private func recorded(_ files: [String], reference: String = "r.mov") -> [String: String] {
        Dictionary(uniqueKeysWithValues: (files + [reference]).map { ($0, String($0.prefix(1)).uppercased()) })
    }

    /// Only the reference is in the guide track from the start; another input joins at its first counted
    /// window, placed earlier by its audio delay; one never measured stays out of it.
    @Test func anInputJoinsTheGuideTrackAtItsFirstAudioDelay() {
        var delays = AudioDelays()
        let first = delays.update(files: recorded(["a.mov", "b.mov"]), reference: "r.mov")
        #expect(first.earlierBy == ["r.mov": 0, "a.mov": nil, "b.mov": nil])
        #expect(first.delays.isEmpty)
        #expect(delays.shown("a.mov") == .notInTheGuideTrackYet)
        #expect(delays.shown("r.mov") == nil)
        let measured = delays.update(files: recorded(["a.mov", "b.mov"]), reference: "r.mov", lags: ["a.mov": 0.5], at: 20)
        #expect(measured.earlierBy == ["r.mov": 0, "a.mov": 0.5, "b.mov": nil])
        #expect(measured.delays == ["a.mov": Entry(delay: 0.5)])
        #expect(measured.leaving.isEmpty && measured.rejoining.isEmpty)
        #expect(delays.shown("a.mov") == .synced(0.5, carriedOver: false))
        #expect(delays.shown("b.mov") == .notInTheGuideTrackYet)
    }

    /// Rounded to a nanosecond, as the sums of lags and audio delays are not exact.
    private func rounded(_ values: [String: Double?]) -> [String: Double?] { values.mapValues { $0.map { ($0 * 1e9).rounded() / 1e9 } } }
    private func rounded(_ entries: [String: Entry]) -> [String: Double] { entries.mapValues { ($0.delay * 1e9).rounded() / 1e9 } }

    /// An input earlier than the anchor: the mix places the others later than it, and the list says it is
    /// earlier than the anchor, which it leaves out.
    @Test func anEarlyInputMovesTheOthersInTheGuideAndIsNegativeInTheList() {
        var delays = AudioDelays()
        let outcome = delays.update(files: recorded(["a.mov", "b.mov"]), reference: "r.mov", lags: ["a.mov": -0.3, "b.mov": 0.2], at: 20)
        #expect(rounded(outcome.earlierBy) == ["a.mov": 0, "r.mov": 0.3, "b.mov": 0.5])
        #expect(rounded(outcome.delays) == ["a.mov": -0.3, "b.mov": 0.2])
        #expect(delays.shown("r.mov") == .synced(0.3, carriedOver: false))
        #expect(delays.shown("a.mov") == nil)
    }

    /// A new earliest input mid-recording changes no other file's listed audio delay, so no other clip is split.
    @Test func aNewEarliestInputChangesNoOtherListedDelay() {
        var delays = AudioDelays()
        let before = delays.update(files: recorded(["a.mov", "b.mov"]), reference: "r.mov", lags: ["a.mov": 0.5], at: 20)
        let after = delays.update(files: recorded(["a.mov", "b.mov"]), reference: "r.mov", lags: ["b.mov": -0.3], at: 30)
        #expect(before.delays == ["a.mov": Entry(delay: 0.5)])
        #expect(after.delays["a.mov"] == Entry(delay: 0.5))
        #expect(after.delays["r.mov"] == nil)
        #expect(rounded(after.earlierBy) == ["b.mov": 0, "r.mov": 0.3, "a.mov": 0.8])
    }

    /// An input out of sync leaves the guide track; the others are placed by the earliest staying input, and the
    /// list keeps every input's audio delay against the anchor.
    @Test func anEarlyInputThatLeftNoLongerPlacesTheOthers() {
        var delays = AudioDelays()
        let outcome = delays.update(
            files: recorded(["a.mov", "b.mov", "c.mov"]), reference: "r.mov", lags: ["a.mov": -0.9, "b.mov": 0.1, "c.mov": 0], at: 20)
        #expect(outcome.leaving == ["a.mov": -0.9])
        #expect(outcome.earlierBy == ["r.mov": 0, "b.mov": 0.1, "c.mov": 0])
        #expect(outcome.delays == ["a.mov": Entry(delay: -0.9), "b.mov": Entry(delay: 0.1), "c.mov": Entry(delay: 0)])
        #expect(delays.shown("a.mov") == nil)
    }

    /// A new file of an input whose earlier file had an audio delay starts with it, carried over, until its
    /// own first counted window confirms it; the list names the earlier file while it is carried over.
    @Test func aNewFileOfAnInputCarriesOverItsAudioDelay() {
        var delays = AudioDelays()
        _ = delays.update(files: recorded(["a1.mov"]), reference: "r.mov", lags: ["a1.mov": 0.5], at: 20)
        let carried = delays.update(files: recorded(["a2.mov"]), reference: "r.mov")
        #expect(carried.earlierBy == ["r.mov": 0, "a2.mov": 0.5])
        #expect(carried.delays == ["a2.mov": Entry(delay: 0.5, carriedOverFrom: "a1.mov")])
        #expect(delays.shown("a2.mov") == .synced(0.5, carriedOver: true))
        let confirmed = delays.update(files: recorded(["a2.mov"]), reference: "r.mov", lags: ["a2.mov": 0.51], at: 40)
        #expect(confirmed.delays == ["a2.mov": Entry(delay: 0.5)])
        #expect(delays.shown("a2.mov") == .synced(0.5, carriedOver: false))
    }

    /// A new file of an input out of the guide track stays out with it, no new leave told.
    @Test func aNewFileOfAnInputOutOfTheGuideTrackStaysOut() {
        var delays = AudioDelays()
        #expect(delays.update(files: recorded(["a1.mov"]), reference: "r.mov", lags: ["a1.mov": 0.9], at: 20).leaving == ["a1.mov": 0.9])
        let next = delays.update(files: recorded(["a2.mov"]), reference: "r.mov")
        #expect(next.leaving.isEmpty && next.rejoining.isEmpty)
        #expect(next.earlierBy == ["r.mov": 0])
        #expect(delays.shown("a2.mov") == nil)
    }

    /// The reference's capture ending makes another input the reference: every lag is re-based onto the anchor
    /// through its audio delay, the mix keeps every input, and no listed delay changes; the anchor's return
    /// changes none either.
    @Test func anotherReferenceWithAnAudioDelayReBasesOntoTheAnchor() {
        var delays = AudioDelays()
        _ = delays.update(files: recorded(["a.mov", "b.mov"]), reference: "r.mov", lags: ["a.mov": 0.5, "b.mov": 0.2], at: 20)
        let without = delays.update(files: ["a.mov": "A", "b.mov": "B"], reference: "a.mov", lags: ["b.mov": -0.3], at: 30)
        #expect(rounded(without.earlierBy) == ["a.mov": 0.3, "b.mov": 0])
        #expect(rounded(without.delays) == ["a.mov": 0.5, "b.mov": 0.2])
        #expect(without.leaving.isEmpty)
        let back = delays.update(files: recorded(["a.mov", "b.mov"], reference: "r2.mov"), reference: "r2.mov")
        #expect(rounded(back.earlierBy) == ["r2.mov": 0, "a.mov": 0.5, "b.mov": 0.2])
        #expect(rounded(back.delays) == ["a.mov": 0.5, "b.mov": 0.2])
    }

    /// A reference without an audio delay becomes the anchor: every input starts over, carrying nothing over.
    @Test func aReferenceWithoutAnAudioDelayBecomesTheAnchorAndEveryInputStartsOver() {
        var delays = AudioDelays()
        _ = delays.update(files: recorded(["a1.mov", "c.mov"]), reference: "r.mov", lags: ["a1.mov": 0.5], at: 20)
        let other = delays.update(files: ["a1.mov": "A", "c.mov": "C"], reference: "c.mov")
        #expect(other.earlierBy == ["c.mov": 0, "a1.mov": nil])
        #expect(other.delays.isEmpty)
        #expect(delays.shown("a1.mov") == .notInTheGuideTrackYet)
        let next = delays.update(files: ["a2.mov": "A", "c.mov": "C"], reference: "c.mov")
        #expect(next.earlierBy == ["c.mov": 0, "a2.mov": nil])
        let measured = delays.update(files: ["a2.mov": "A", "c.mov": "C"], reference: "c.mov", lags: ["a2.mov": 0.4], at: 40)
        #expect(measured.delays == ["a2.mov": Entry(delay: 0.4)])
    }

    /// An input whose capture ended no longer places the others.
    @Test func anInputWhoseCaptureEndedNoLongerPlacesTheOthers() {
        var delays = AudioDelays()
        _ = delays.update(files: recorded(["a.mov", "b.mov"]), reference: "r.mov", lags: ["a.mov": -0.5, "b.mov": 0.2], at: 20)
        let after = delays.update(files: recorded(["b.mov"]), reference: "r.mov")
        #expect(rounded(after.delays) == ["b.mov": 0.2])
        #expect(rounded(after.earlierBy) == ["r.mov": 0, "b.mov": 0.2])
    }
}
