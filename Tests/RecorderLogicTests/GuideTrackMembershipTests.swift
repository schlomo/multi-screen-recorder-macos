import Testing
@testable import RecorderLogic

/// Which audio inputs the "Audio inputs" guide track mixes (D79): the largest group of inputs being written
/// whose lags lie within the limit of each other stays; the others leave.
@Suite struct GuideTrackMembershipTests {
    private typealias Change = GuideTrackMembership.Change

    /// Each file's counted windows, against the reference's file "r.mov".
    private func measure(_ membership: inout GuideTrackMembership, _ lags: [String: [Double]]) {
        for (file, fileLags) in lags { for lag in fileLags { membership.add(lag, file: file, reference: "r.mov") } }
    }

    private func update(_ membership: inout GuideTrackMembership, writing: [String]) -> Change {
        membership.update(writing: Set(writing + ["r.mov"]), reference: "r.mov")
    }

    @Test func theLimitIsOneDataValue() {
        #expect(RecorderValues.guideTrackSyncLimit == 0.1)
    }

    /// A late reference, as an Osmo as the default microphone, leaves; the two microphones in sync stay.
    @Test func aLateReferenceLeavesTheInputsInSyncStay() {
        var membership = GuideTrackMembership()
        measure(&membership, ["a.mov": [-0.5], "b.mov": [-0.48]])
        #expect(update(&membership, writing: ["a.mov", "b.mov"]) == Change(leaving: ["r.mov": 0.5]))
        #expect(membership.isOut("r.mov"))
    }

    @Test func oneEarlyInputAmongThreeInSyncLeavesAlone() {
        var membership = GuideTrackMembership()
        measure(&membership, ["early.mov": [-0.4], "b.mov": [0.02], "c.mov": [0.05]])
        #expect(update(&membership, writing: ["early.mov", "b.mov", "c.mov"]) == Change(leaving: ["early.mov": -0.4]))
    }

    /// An ended file no longer counts: a new microphone in sync with the reference stays, the early one gone.
    @Test func anEndedEarlyInputMakesNoNewOneLeave() {
        var membership = GuideTrackMembership()
        measure(&membership, ["early.mov": [-0.4], "b.mov": [0]])
        _ = update(&membership, writing: ["early.mov", "b.mov"])
        measure(&membership, ["c.mov": [0.03]])
        #expect(update(&membership, writing: ["b.mov", "c.mov"]) == Change())
    }

    @Test func atTheLimitAnInputStays() {
        var membership = GuideTrackMembership()
        measure(&membership, ["a.mov": [RecorderValues.guideTrackSyncLimit]])
        #expect(update(&membership, writing: ["a.mov"]) == Change())
    }

    /// On a tie the group holding the inputs that stayed wins: a newcomer never evicts them.
    @Test func onATieTheGroupThatStayedWins() {
        var membership = GuideTrackMembership()
        measure(&membership, ["a.mov": [0.09]])
        #expect(update(&membership, writing: ["a.mov"]) == Change())
        measure(&membership, ["b.mov": [-0.05]])
        #expect(update(&membership, writing: ["a.mov", "b.mov"]) == Change(leaving: ["b.mov": -0.05]))
    }

    /// Once a file has 3 counted windows its median is its value, a staying file's too: a false first window
    /// at about 0 on a late microphone is corrected.
    @Test func aStayingFilesMedianCorrectsAFalseFirstWindow() {
        var membership = GuideTrackMembership()
        measure(&membership, ["a.mov": [0.01]])
        #expect(update(&membership, writing: ["a.mov"]) == Change())
        measure(&membership, ["a.mov": [0.5]])
        #expect(update(&membership, writing: ["a.mov"]) == Change())
        measure(&membership, ["a.mov": [0.5]])
        #expect(update(&membership, writing: ["a.mov"]) == Change(leaving: ["a.mov": 0.5]))
    }

    /// Values a counted window apart at the limit stay together wherever they lie: 0.4 − 0.3 is a little more
    /// than 0.1 in binary.
    @Test func aPairAtTheLimitStaysTogetherAwayFromZero() {
        var membership = GuideTrackMembership()
        measure(&membership, ["a.mov": [0.3], "b.mov": [0.4]])
        #expect(update(&membership, writing: ["a.mov", "b.mov"]) == Change(leaving: ["r.mov": -0.3]))
    }

    /// On a tie the group with the earliest input stays.
    @Test func onATieTheGroupWithTheEarliestInputStays() {
        var membership = GuideTrackMembership()
        measure(&membership, ["a.mov": [0.5]])
        #expect(update(&membership, writing: ["a.mov"]) == Change(leaving: ["a.mov": 0.5]))
    }

    /// The first counted window decides; a file that left rejoins once the median of its counted windows lies
    /// within the limit of the group, and leaves again only on its median.
    @Test func aFalseFirstWindowRejoinsOnItsMedianAndOnlyTheMedianMakesItLeaveAgain() {
        var membership = GuideTrackMembership()
        measure(&membership, ["a.mov": [0.5]])
        #expect(update(&membership, writing: ["a.mov"]).leaving == ["a.mov": 0.5])
        measure(&membership, ["a.mov": [0.01]])
        #expect(update(&membership, writing: ["a.mov"]) == Change())
        measure(&membership, ["a.mov": [0.02]])
        #expect(update(&membership, writing: ["a.mov"]) == Change(rejoining: ["a.mov"]))
        #expect(!membership.isOut("a.mov"))
        // One late window moves the median of 4 [0.01, 0.02, 0.5, 0.6] to 0.26: out again on the median.
        measure(&membership, ["a.mov": [0.6]])
        let left = update(&membership, writing: ["a.mov"]).leaving
        #expect(abs((left["a.mov"] ?? 0) - 0.26) < 1e-9)
    }

    /// A file out on its first counted window stays out, without a median, even when the group moves to it.
    @Test func withoutAMedianAFileThatLeftStaysOut() {
        var membership = GuideTrackMembership()
        measure(&membership, ["a.mov": [0.5]])
        _ = update(&membership, writing: ["a.mov"])
        measure(&membership, ["b.mov": [0.5]])
        #expect(update(&membership, writing: ["a.mov", "b.mov"]) == Change(leaving: ["r.mov": -0.5]))
        #expect(membership.isOut("a.mov"))
    }

    /// A file stays out until its median says otherwise; its input's next file starts in the guide track.
    @Test func aFileThatLeftStaysOutAndTheNextFileStartsIn() {
        var membership = GuideTrackMembership()
        measure(&membership, ["a1.mov": [0.5]])
        _ = update(&membership, writing: ["a1.mov"])
        #expect(membership.isOut("a1.mov"))
        #expect(!membership.isOut("a2.mov"))
        #expect(update(&membership, writing: ["a2.mov"]) == Change())
        #expect(!membership.isOut("a1.mov"))
    }
}
