import Testing
@testable import RecorderLogic

/// Which audio inputs the "Audio inputs" guide track mixes (D80, D90): every input with an audio delay, unless
/// they lie further apart than the limit; then the largest set within it, on a tie the reference's.
@Suite struct GuideTrackMembershipTests {
    /// The audio delays against the reference "r", which is 0.
    private func mixed(_ delays: [String: Double], limit: Double = RecorderValues.guideTrackSyncLimit) -> [String] {
        GuideTrackMembership.mixed(delays.merging(["r": 0]) { $1 }, reference: "r", limit: limit).sorted()
    }

    /// A late reference, as an Osmo as the first input, is not mixed; the two microphones in sync are.
    @Test func aLateReferenceIsNotMixedTheInputsInSyncAre() {
        #expect(mixed(["a": -0.9, "b": -0.88]) == ["a", "b"])
    }

    @Test func oneEarlyInputAmongThreeInSyncIsNotMixed() {
        #expect(mixed(["early": -0.9, "b": 0.02, "c": 0.05]) == ["b", "c", "r"])
    }

    /// Inputs within the limit are all mixed, 0.5 s late among them: the guide places them by their audio delays.
    @Test func inputsWithinTheLimitAreAllMixed() {
        #expect(mixed(["a": 0.5, "b": -0.2]) == ["a", "b", "r"])
    }

    @Test func atTheLimitAnInputIsMixed() {
        #expect(mixed(["a": RecorderValues.guideTrackSyncLimit]) == ["a", "r"])
    }

    /// On a tie the set holding the reference is mixed, whichever input is earliest.
    @Test func onATieTheReferencesSetIsMixed() {
        #expect(mixed(["a": 0.9]) == ["r"])
        #expect(mixed(["a": -0.9]) == ["r"])
    }

    /// Without the reference among them, a tie goes to the set with the earliest input.
    @Test func withoutTheReferenceATieGoesToTheEarliestSet() {
        #expect(GuideTrackMembership.mixed(["a": 0, "b": 0.9], reference: nil) == ["a"])
        #expect(GuideTrackMembership.mixed(["a": 0, "b": 0.9], reference: "c") == ["a"])
    }

    /// Values at the limit stay together wherever they lie: 0.4 − 0.3 is a little more than 0.1 in binary.
    @Test func aPairAtTheLimitStaysTogetherAwayFromZero() {
        #expect(GuideTrackMembership.mixed(["a": 0.3, "b": 0.4], reference: "a", limit: 0.1) == ["a", "b"])
    }

    /// Half a sample beyond the limit, the step of an even-count median, is apart, wherever the pair lies.
    @Test func aPairHalfASampleBeyondTheLimitIsApart() {
        let beyond = 0.3 + 6400.5 / Double(AudioDelay.sampleRate)
        #expect(GuideTrackMembership.mixed(["a": 0.3, "b": beyond], reference: "a") == ["a"])
    }

    /// Nothing is remembered: the same audio delays give the same set whatever came before.
    @Test func theSetDependsOnTheAudioDelaysAlone() {
        #expect(mixed(["a": 0.9, "b": 0.9]) == ["a", "b"])
        #expect(mixed(["a": 0.5]) == ["a", "r"])
        #expect(mixed([:]) == ["r"])
        #expect(GuideTrackMembership.mixed([:], reference: nil).isEmpty)
    }
}
