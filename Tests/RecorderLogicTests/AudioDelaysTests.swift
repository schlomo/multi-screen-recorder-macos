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
        #expect(first.delays == ["r.mov": Entry(delay: 0)])
        #expect(delays.shown("a.mov") == .notInTheGuideTrackYet)
        #expect(delays.shown("r.mov") == .anchor(0))
        let measured = delays.update(files: recorded(["a.mov", "b.mov"]), reference: "r.mov", lags: ["a.mov": 0.5], at: 20)
        #expect(measured.earlierBy == ["r.mov": 0, "a.mov": 0.5, "b.mov": nil])
        #expect(measured.delays == ["a.mov": Entry(delay: 0.5), "r.mov": Entry(delay: 0)])
        #expect(delays.shown("a.mov") == .synced(0.5, carriedOver: false))
        #expect(delays.shown("b.mov") == .notInTheGuideTrackYet)
    }

    /// An input whose file had sound in 3 measurements without a counted window has no clear sound to sync; it
    /// joins the guide track once a window counts (D80).
    @Test func anInputWithSoundButNoCountedWindowHasNoClearSoundToSync() {
        var delays = AudioDelays()
        for at in [10.0, 20] {
            _ = delays.update(files: recorded(["a.mov"]), reference: "r.mov", unclear: ["a.mov"], at: at)
            #expect(delays.shown("a.mov") == .notInTheGuideTrackYet)
        }
        _ = delays.update(files: recorded(["a.mov"]), reference: "r.mov", unclear: ["a.mov"], at: 30)
        #expect(delays.shown("a.mov") == .noClearSoundToSync)
        _ = delays.update(files: recorded(["a.mov"]), reference: "r.mov", lags: ["a.mov": 0.5], at: 40)
        #expect(delays.shown("a.mov") == .synced(0.5, carriedOver: false))
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
        #expect(rounded(outcome.delays) == ["a.mov": -0.3, "b.mov": 0.2, "r.mov": 0])
        #expect(delays.shown("r.mov") == .anchor(0.3))
        #expect(delays.shown("a.mov") == .synced(0, carriedOver: false))
    }

    /// A new earliest input mid-recording changes no other file's listed audio delay, so no other clip is split.
    @Test func aNewEarliestInputChangesNoOtherListedDelay() {
        var delays = AudioDelays()
        let before = delays.update(files: recorded(["a.mov", "b.mov"]), reference: "r.mov", lags: ["a.mov": 0.5], at: 20)
        let after = delays.update(files: recorded(["a.mov", "b.mov"]), reference: "r.mov", lags: ["b.mov": -0.3], at: 30)
        #expect(before.delays == ["a.mov": Entry(delay: 0.5), "r.mov": Entry(delay: 0)])
        #expect(after.delays["a.mov"] == Entry(delay: 0.5))
        #expect(after.delays["r.mov"] == Entry(delay: 0))
        #expect(rounded(after.earlierBy) == ["b.mov": 0, "r.mov": 0.3, "a.mov": 0.8])
    }

    /// An input too far out of step is not mixed, and its row says how far (D90); the others are placed by the
    /// earliest input mixed, and the list keeps every input's audio delay against the anchor.
    @Test func anEarlyInputNotMixedNoLongerPlacesTheOthers() {
        var delays = AudioDelays()
        let outcome = delays.update(
            files: recorded(["a.mov", "b.mov", "c.mov"]), reference: "r.mov", lags: ["a.mov": -0.9, "b.mov": 0.1, "c.mov": 0], at: 20)
        #expect(outcome.earlierBy == ["r.mov": 0, "b.mov": 0.1, "c.mov": 0, "a.mov": nil])
        #expect(outcome.delays == ["a.mov": Entry(delay: -0.9), "b.mov": Entry(delay: 0.1), "c.mov": Entry(delay: 0), "r.mov": Entry(delay: 0)])
        #expect(outcome.lines.contains("a.mov: not in the guide track, 1000 ms from the others"), "\(outcome.lines)")
        #expect(delays.shown("a.mov") == .notInTheGuideTrack(apart: 1.0))
    }

    /// A new file of an input whose earlier file had an audio delay starts with it, carried over, until its
    /// own first counted window confirms it; the list gives the value alone, a confirmation adding nothing.
    @Test func aNewFileOfAnInputCarriesOverItsAudioDelay() {
        var delays = AudioDelays()
        _ = delays.update(files: recorded(["a1.mov"]), reference: "r.mov", lags: ["a1.mov": 0.5], at: 20)
        let carried = delays.update(files: recorded(["a2.mov"]), reference: "r.mov")
        #expect(carried.earlierBy == ["r.mov": 0, "a2.mov": 0.5])
        #expect(carried.delays == ["a2.mov": Entry(delay: 0.5), "r.mov": Entry(delay: 0)])
        #expect(delays.shown("a2.mov") == .synced(0.5, carriedOver: true))
        let confirmed = delays.update(files: recorded(["a2.mov"]), reference: "r.mov", lags: ["a2.mov": 0.51], at: 40)
        #expect(confirmed.delays == ["a2.mov": Entry(delay: 0.5), "r.mov": Entry(delay: 0)])
        #expect(delays.shown("a2.mov") == .synced(0.5, carriedOver: false))
    }

    /// A new file of an input not mixed carries its audio delay over and is not mixed either; once its audio
    /// delay lies within the limit it is mixed, nothing remembered (D90).
    @Test func aNewFileOfAnInputNotMixedIsMixedOnceItsAudioDelayFits() {
        var delays = AudioDelays()
        #expect(delays.update(files: recorded(["a1.mov"]), reference: "r.mov", lags: ["a1.mov": 0.9], at: 20).earlierBy["a1.mov"] == .some(nil))
        let next = delays.update(files: recorded(["a2.mov"]), reference: "r.mov")
        #expect(next.earlierBy == ["r.mov": 0, "a2.mov": nil])
        #expect(next.lines.contains("a2.mov: not in the guide track with the carried-over audio delay"), "\(next.lines)")
        #expect(delays.shown("a2.mov") == .notInTheGuideTrack(apart: 0.9))
        let fits = delays.update(files: recorded(["a2.mov"]), reference: "r.mov", lags: ["a2.mov": 0.5], at: 40)
        #expect(fits.earlierBy == ["r.mov": 0, "a2.mov": 0.5])
        #expect(delays.shown("a2.mov") == .synced(0.5, carriedOver: false))
    }

    /// The reference's capture ending makes another input the reference: every lag is re-based onto the anchor
    /// through its audio delay, the mix keeps every input, and no listed delay changes.
    @Test func anotherReferenceWithAnAudioDelayReBasesOntoTheAnchor() {
        var delays = AudioDelays()
        _ = delays.update(files: recorded(["a.mov", "b.mov"]), reference: "r.mov", lags: ["a.mov": 0.5, "b.mov": 0.2], at: 20)
        let without = delays.update(files: ["a.mov": "A", "b.mov": "B"], reference: "a.mov", lags: ["b.mov": -0.3], at: 30)
        #expect(without.lines.first == "reference r.mov → a.mov: lags re-based onto the anchor by 500 ms late")
        #expect(rounded(without.earlierBy) == ["a.mov": 0.3, "b.mov": 0])
        #expect(rounded(without.delays) == ["a.mov": 0.5, "b.mov": 0.2])
        #expect(delays.referenceDevice == "A")
    }

    /// The owner's recording 2026-11-24 20.55.08 (D85): the Osmo "O" sounds first, the anchor, the Razer "Z"
    /// 550 ms early against it; the Osmo unplugged, the Razer is the reference; the Osmo's new file, back
    /// 100 ms less late, is measured against the Razer like any other input, from its earlier file's 0
    /// carried over, and the Razer keeps its audio delay.
    @Test func theAnchorsNewFileIsMeasuredAgainstTheReferenceInUse() {
        var delays = AudioDelays()
        for at in [10.0, 20, 30] { _ = delays.update(files: ["o1.mov": "O", "z.mov": "Z"], reference: "o1.mov", lags: ["z.mov": -0.55], at: at) }
        #expect(delays.anchor == "O")
        _ = delays.update(files: ["z.mov": "Z"], reference: "z.mov")
        let back = delays.update(files: ["o2.mov": "O", "z.mov": "Z"], reference: "z.mov")
        #expect(back.lines.first == "o2.mov: carries over 0 ms from o1.mov")
        #expect(rounded(back.delays) == ["o2.mov": 0, "z.mov": -0.55])
        #expect(delays.shown("o2.mov") == .synced(0.55, carriedOver: true))
        #expect(delays.hasAudioDelay("o2.mov", device: "O"))
        let measured = delays.update(files: ["o2.mov": "O", "z.mov": "Z"], reference: "z.mov", lags: ["o2.mov": 0.45], at: 130)
        #expect(measured.lines.first == "o2.mov: audio delay its first counted window on the carried-over: 0 ms → 100 ms early, replaced")
        #expect(rounded(measured.delays) == ["o2.mov": -0.1, "z.mov": -0.55])
        guard case .synced(let placed, carriedOver: false) = delays.shown("o2.mov") else {
            Issue.record("o2.mov is not shown measured: \(String(describing: delays.shown("o2.mov")))")
            return
        }
        #expect(abs(placed - 0.45) < 1e-9)
        #expect(delays.referenceDevice == "Z")
        #expect(delays.hindsight(of: "o1.mov", fileStart: 0) == nil)
        #expect(delays.hindsight(of: "o2.mov", fileStart: 117) == [.init(at: 0, delay: -0.1)])
    }

    /// The reference back on the anchor's device through a measured file (D85): that device's next file, after a
    /// gap or a channel change, carries over the measured audio delay; it is no anchor file at 0.
    @Test func theAnchorDevicesFileAfterAMeasuredOneCarriesItsAudioDelayOver() {
        var delays = AudioDelays()
        _ = delays.update(files: ["o1.mov": "O", "z.mov": "Z", "a.mov": "A"], reference: "o1.mov", lags: ["z.mov": -0.55], at: 10)
        _ = delays.update(files: ["z.mov": "Z", "a.mov": "A"], reference: "z.mov")
        _ = delays.update(files: ["o2.mov": "O", "z.mov": "Z", "a.mov": "A"], reference: "z.mov", lags: ["o2.mov": 0.45], at: 130)
        _ = delays.update(files: ["o2.mov": "O", "a.mov": "A"], reference: "o2.mov")
        #expect(delays.referenceDevice == "O")
        let next = delays.update(files: ["o3.mov": "O", "a.mov": "A"], reference: "o3.mov")
        #expect(next.lines.first == "o3.mov: carries over 100 ms early from o2.mov")
        #expect(rounded(next.delays)["o3.mov"] == -0.1)
        let measured = delays.update(files: ["o3.mov": "O", "a.mov": "A"], reference: "o3.mov", lags: ["a.mov": 0.2], at: 200)
        #expect(rounded(measured.delays) == ["o3.mov": -0.1, "a.mov": 0.1])
    }

    /// Across a change of reference, a stretch within a frame of the one before adds no entry, so no clip is split
    /// where the two agree; its windows are not merged into the earlier median either (D85).
    @Test func hindsightAddsNoEntryAcrossAChangeOfReferenceWhenTheyAgree() {
        var delays = AudioDelays()
        for at in [10.0, 20, 30] {
            _ = delays.update(files: recorded(["a.mov", "b.mov"]), reference: "r.mov", lags: ["a.mov": 0.5, "b.mov": 0.2], at: at)
        }
        for at in [40.0, 50, 60] { _ = delays.update(files: ["a.mov": "A", "b.mov": "B"], reference: "a.mov", lags: ["b.mov": -0.28], at: at) }
        #expect(delays.hindsight(of: "b.mov", fileStart: 5) == [.init(at: 0, delay: 0.2)])
    }

    /// A file measured against one reference and then another (D85): Stop's hindsight never merges the windows
    /// of the two into one median, the second stretch starting at the first window against the second; the
    /// new reference's own file, measured no more, gets no new entry.
    @Test func hindsightSplitsAFileAtAChangeOfReference() {
        var delays = AudioDelays()
        for at in [10.0, 20, 30] {
            _ = delays.update(files: recorded(["a.mov", "b.mov"]), reference: "r.mov", lags: ["a.mov": 0.5, "b.mov": 0.2], at: at)
        }
        for at in [40.0, 50] { _ = delays.update(files: ["a.mov": "A", "b.mov": "B"], reference: "a.mov", lags: ["b.mov": -0.2], at: at) }
        let stretches = delays.hindsight(of: "b.mov", fileStart: 5)
        #expect(stretches?.count == 2)
        #expect(stretches?.first == .init(at: 0, delay: 0.2))
        #expect(stretches?.last.map { ($0.at * 1000).rounded() / 1000 } == 35)
        #expect(stretches?.last.map { ($0.delay * 1000).rounded() / 1000 } == 0.3)
        #expect(delays.hindsight(of: "a.mov", fileStart: 5) == [.init(at: 0, delay: 0.5)])
    }

    /// A reference without an audio delay becomes the anchor: every input starts over, carrying nothing over.
    @Test func aReferenceWithoutAnAudioDelayBecomesTheAnchorAndEveryInputStartsOver() {
        var delays = AudioDelays()
        _ = delays.update(files: recorded(["a1.mov", "c.mov"]), reference: "r.mov", lags: ["a1.mov": 0.5], at: 20)
        let other = delays.update(files: ["a1.mov": "A", "c.mov": "C"], reference: "c.mov")
        #expect(other.lines.first == "reference r.mov → c.mov: it has no audio delay, so it is the new anchor and every input starts over")
        #expect(other.earlierBy == ["c.mov": 0, "a1.mov": nil])
        #expect(other.delays == ["c.mov": Entry(delay: 0)])
        #expect(delays.shown("a1.mov") == .notInTheGuideTrackYet)
        let next = delays.update(files: ["a2.mov": "A", "c.mov": "C"], reference: "c.mov")
        #expect(next.earlierBy == ["c.mov": 0, "a2.mov": nil])
        let measured = delays.update(files: ["a2.mov": "A", "c.mov": "C"], reference: "c.mov", lags: ["a2.mov": 0.4], at: 40)
        #expect(measured.delays == ["a2.mov": Entry(delay: 0.4), "c.mov": Entry(delay: 0)])
    }

    /// An input whose capture ended no longer places the others.
    @Test func anInputWhoseCaptureEndedNoLongerPlacesTheOthers() {
        var delays = AudioDelays()
        _ = delays.update(files: recorded(["a.mov", "b.mov"]), reference: "r.mov", lags: ["a.mov": -0.5, "b.mov": 0.2], at: 20)
        let after = delays.update(files: recorded(["b.mov"]), reference: "r.mov")
        #expect(rounded(after.delays) == ["b.mov": 0.2, "r.mov": 0])
        #expect(rounded(after.earlierBy) == ["r.mov": 0, "b.mov": 0.2])
    }

    /// The recording log's lines say every decision: a carry-over and its confirmation, and a change by the
    /// median of the latest minute, the mix crossfading.
    @Test func everyDecisionIsALineForTheRecordingLog() {
        var delays = AudioDelays()
        let first = delays.update(files: recorded(["a1.mov"]), reference: "r.mov", lags: ["a1.mov": 0.5], at: 10)
        #expect(first.lines == [
            "a1.mov: audio delay set by its first counted window: 500 ms late",
            "a1.mov: joins the guide track placed earlier by 500 ms (the mix's zero: r.mov)",
            "r.mov: joins the guide track placed earlier by 0 ms (the mix's zero: r.mov)",
        ])
        let carried = delays.update(files: recorded(["a2.mov"]), reference: "r.mov")
        #expect(carried.lines == ["a2.mov: carries over 500 ms late from a1.mov", "a2.mov: in the guide track with the carried-over audio delay"])
        let confirmed = delays.update(files: recorded(["a2.mov"]), reference: "r.mov", lags: ["a2.mov": 0.51], at: 20)
        #expect(confirmed.lines == [
            "a2.mov: audio delay its first counted window on the carried-over: kept at 500 ms late, 10.0 ms off, within a frame, confirmed"])
        var changed = AudioDelays.Outcome()
        for (at, lag) in [(30.0, 0.5), (40, 0.5), (50, 0.6), (60, 0.6), (70, 0.6), (80, 0.6)] {
            changed = delays.update(files: recorded(["a2.mov"]), reference: "r.mov", lags: ["a2.mov": lag], at: at)
        }
        // The last 6 windows from 30 s on, the 510 ms one at 20 s out of the latest minute.
        #expect(changed.lines == [
            "a2.mov: audio delay the median of its 6 counted windows of the latest 60 s: 555 ms late → 600 ms late",
            "a2.mov: placed earlier by 555 ms → 600 ms (the mix's zero: r.mov)",
        ])
        #expect(changed.isMoved)
    }

    /// A placement that rounds to 0 ms shows its sync, 0 ms, as every synced input does (D86).
    @Test func aPlacementRoundingTo0MillisecondsShowsSynced0Milliseconds() {
        var delays = AudioDelays()
        _ = delays.update(files: recorded(["a.mov"]), reference: "r.mov", lags: ["a.mov": 0.0004], at: 10)
        #expect(delays.shown("a.mov").map(RecordingStatusTable.audioDelayText) == "synced 0 ms")
        #expect(delays.shown("r.mov").map(RecordingStatusTable.audioDelayText) == "synced 0 ms")
    }

    /// A counted window no rule takes and a lag dropped say why in the recording log.
    @Test func aWindowNoRuleTakesAndADroppedLagAreLines() {
        var delays = AudioDelays()
        _ = delays.update(files: recorded(["a.mov"]), reference: "r.mov", lags: ["a.mov": 0.5], at: 10)
        let second = delays.update(files: recorded(["a.mov"]), reference: "r.mov", lags: ["a.mov": 0.5, "r.mov": 0, "x.mov": 0.1], at: 20)
        #expect(second.lines == [
            "a.mov: audio delay no rule: 2 of 3 counted windows for the median",
            "r.mov: lag 0 ms dropped, the reference's own",
            "x.mov: lag 100 ms late dropped, not a device's newest file",
        ])
    }

    /// Whether a file has an audio delay for being the reference: the anchor's always, a new file of a
    /// measured device by its carry-over before it is known, an unmeasured one not.
    @Test func whetherAFileHasAnAudioDelayCountsTheAnchorAndTheCarryOver() {
        var delays = AudioDelays()
        #expect(delays.anchor == nil)
        _ = delays.update(files: recorded(["a1.mov", "b.mov"]), reference: "r.mov", lags: ["a1.mov": 0.5], at: 10)
        #expect(delays.anchor == "R")
        #expect(delays.hasAudioDelay("r2.mov", device: "R"))
        #expect(delays.hasAudioDelay("a2.mov", device: "A"))
        #expect(!delays.hasAudioDelay("b.mov", device: "B"))
    }
}
