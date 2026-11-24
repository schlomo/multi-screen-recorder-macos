import Testing
@testable import RecorderLogic

/// Which audio inputs the "Audio inputs" guide track mixes (D79, D80): the largest group of inputs being
/// written whose audio delays lie within the limit of each other stays; the others leave.
@Suite struct GuideTrackMembershipTests {
    private typealias Change = GuideTrackMembership.Change

    /// The audio delays against the reference's file "r.mov", which is 0 and always written.
    private func update(_ membership: inout GuideTrackMembership, _ delays: [String: Double], writing: [String] = []) -> Change {
        membership.update(delays: delays.merging(["r.mov": 0]) { $1 }, writing: Set(delays.keys + writing + ["r.mov"]))
    }

    @Test func theLimitIsOneDataValue() {
        #expect(RecorderValues.guideTrackSyncLimit == 0.8)
    }

    /// A late reference, as an Osmo as the default microphone, leaves; the two microphones in sync stay.
    @Test func aLateReferenceLeavesTheInputsInSyncStay() {
        var membership = GuideTrackMembership()
        #expect(update(&membership, ["a.mov": -0.9, "b.mov": -0.88]) == Change(leaving: ["r.mov": 0.9]))
        #expect(membership.isOut("r.mov"))
    }

    @Test func oneEarlyInputAmongThreeInSyncLeavesAlone() {
        var membership = GuideTrackMembership()
        #expect(update(&membership, ["early.mov": -0.9, "b.mov": 0.02, "c.mov": 0.05]) == Change(leaving: ["early.mov": -0.9]))
    }

    /// Inputs within the limit stay, 0.5 s late among them: the guide places them by their audio delays (D80).
    @Test func inputsWithinTheLimitStay() {
        var membership = GuideTrackMembership()
        #expect(update(&membership, ["a.mov": 0.5, "b.mov": -0.2]) == Change())
    }

    /// An ended file no longer counts: a new microphone in sync with the reference stays, the early one gone.
    @Test func anEndedEarlyInputMakesNoNewOneLeave() {
        var membership = GuideTrackMembership()
        _ = update(&membership, ["early.mov": -0.9, "b.mov": 0])
        #expect(update(&membership, ["b.mov": 0, "c.mov": 0.03]) == Change())
    }

    @Test func atTheLimitAnInputStays() {
        var membership = GuideTrackMembership()
        #expect(update(&membership, ["a.mov": RecorderValues.guideTrackSyncLimit]) == Change())
    }

    /// On a tie the group holding the inputs that stayed wins: a newcomer never evicts them.
    @Test func onATieTheGroupThatStayedWins() {
        var membership = GuideTrackMembership()
        #expect(update(&membership, ["a.mov": 0.79]) == Change())
        #expect(update(&membership, ["a.mov": 0.79, "b.mov": -0.05]) == Change(leaving: ["b.mov": -0.05]))
    }

    /// Values at the limit stay together wherever they lie: 0.4 − 0.3 is a little more than 0.1 in binary.
    @Test func aPairAtTheLimitStaysTogetherAwayFromZero() {
        var membership = GuideTrackMembership()
        #expect(update(&membership, ["a.mov": 0.3, "b.mov": 0.4], writing: []) == Change())
        #expect(membership.update(delays: ["a.mov": 0.3, "b.mov": 0.4], writing: ["a.mov", "b.mov"], limit: 0.1) == Change())
    }

    /// Half a sample beyond the limit, the step of an even-count median, is apart, wherever the pair lies.
    @Test func aPairHalfASampleBeyondTheLimitIsApart() {
        var membership = GuideTrackMembership()
        let beyond = 0.3 + 6400.5 / Double(AudioDelay.sampleRate)
        #expect(update(&membership, ["a.mov": 0.3, "b.mov": beyond]).leaving.keys.sorted() == ["b.mov"])
    }

    /// On a tie the group with the earliest input stays.
    @Test func onATieTheGroupWithTheEarliestInputStays() {
        var membership = GuideTrackMembership()
        #expect(update(&membership, ["a.mov": 0.9]) == Change(leaving: ["a.mov": 0.9]))
    }

    /// A file that left rejoins once its audio delay lies within the limit of the group, and leaves again
    /// when it no longer does.
    @Test func aFileRejoinsWhenItsAudioDelayFitsAndLeavesAgainWhenItDoesNot() {
        var membership = GuideTrackMembership()
        #expect(update(&membership, ["a.mov": 0.9]).leaving == ["a.mov": 0.9])
        #expect(update(&membership, ["a.mov": 0.9]) == Change())
        #expect(update(&membership, ["a.mov": 0.5]) == Change(rejoining: ["a.mov"]))
        #expect(!membership.isOut("a.mov"))
        #expect(update(&membership, ["a.mov": 0.95]) == Change(leaving: ["a.mov": 0.95]))
    }

    /// A file that left and whose input no longer has an audio delay (the reference changed) rejoins, to be
    /// not in the guide track yet; a file without one never leaves.
    @Test func aFileThatLeftRejoinsWithoutAnAudioDelay() {
        var membership = GuideTrackMembership()
        _ = update(&membership, ["a.mov": 0.9])
        #expect(update(&membership, [:], writing: ["a.mov"]) == Change(rejoining: ["a.mov"]))
        #expect(update(&membership, [:], writing: ["a.mov"]) == Change())
    }

    /// With the files that stayed gone, a tie falls back to the group with the earliest input, and the
    /// reference rejoins.
    @Test func withTheFilesThatStayedGoneATieFallsBackToTheEarliestGroup() {
        var membership = GuideTrackMembership()
        #expect(update(&membership, ["a.mov": 0.9, "b.mov": 0.9]) == Change(leaving: ["r.mov": -0.9]))
        #expect(update(&membership, ["c.mov": 0, "d.mov": 0.9, "e.mov": 0.9])
            == Change(leaving: ["d.mov": 0.9, "e.mov": 0.9], rejoining: ["r.mov"]))
    }

    /// An ended file is forgotten: a file of the same name written again starts in.
    @Test func anEndedFileIsForgotten() {
        var membership = GuideTrackMembership()
        _ = update(&membership, ["a1.mov": 0.9])
        #expect(membership.isOut("a1.mov"))
        #expect(update(&membership, ["a2.mov": 0.1]) == Change())
        #expect(!membership.isOut("a1.mov"))
    }
}
