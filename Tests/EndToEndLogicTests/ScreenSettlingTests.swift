import Testing
@testable import EndToEndLogic

@Suite struct ScreenSettlingTests {
    static let virtual = "virtual 101"
    static let own = "own A95C"

    /// The first observation is taken before the ask; the virtual screen's place is nil while it is not there.
    func lastChange(_ states: [(Double, String?, String)]) -> Double? {
        let observations = states.map { time, virtual, own in
            ScreenSettling.Observation(time: time, screens: [Self.own: own].merging(virtual.map { [Self.virtual: $0] } ?? [:]) { first, _ in first })
        }
        return ScreenSettling.lastChange(of: Self.virtual, observations: observations, settleTime: 1)
    }

    @Test func aConnectedScreenLastChangedWhenItAppeared() {
        #expect(lastChange([(2.0, nil, "1024x768"), (2.5, "1280x720", "1024x768"), (3.6, "1280x720", "1024x768")]) == 2.5)
    }

    @Test func aKnockOnChangeOfTheSameScreenCounts() {
        // The own screen's mode switch moved the virtual screen too.
        #expect(lastChange([(2.0, nil, "1024x768"), (2.5, "0,0 1280x720", "1024x768"),
                            (3.0, "1920,0 1280x720", "1920x1080"), (3.6, "1920,0 1280x720", "1920x1080"),
                            (4.1, "1920,0 1280x720", "1920x1080")]) == 3.0)
    }

    @Test func anotherScreensChangeDoesNotCount() {
        #expect(lastChange([(2.0, nil, "1024x768"), (2.5, "1280x720", "1024x768"),
                            (3.0, "1280x720", "1920x1080"), (3.6, "1280x720", "1920x1080")]) == 2.5)
    }

    @Test func aChangeAfterTheScreenSettledBelongsToSomethingElse() {
        #expect(lastChange([(6.0, "1280x720", "a"), (6.4, "1600x900", "a"), (7.5, "1600x900", "a"), (7.6, "1280x720", "a")]) == 6.4)
    }

    @Test func aDisconnectedScreenLastChangedWhenItVanished() {
        #expect(lastChange([(11.0, "1600x900", "a"), (11.2, nil, "a"), (12.3, nil, "a")]) == 11.2)
    }

    @Test func aScreenStillChangingHasNotSettled() {
        #expect(lastChange([(6.0, "1280x720", "a"), (6.4, "1600x900", "a"), (7.0, "1280x720", "a")]) == nil)
    }

    @Test func aScreenThatNeverChangedHasNotSettled() {
        #expect(lastChange([(6.0, "1280x720", "a"), (7.6, "1280x720", "a")]) == nil)
    }

    @Test func theSettledWindowIsTheSettleTimeAfterTheScreensLastChange() {
        let change = ChangeTimes(asked: 2.25, done: 3.75, lastChange: 3.5)
        #expect(change.window(.settled, settleTime: 1, tolerance: 0.5) == 4.0...5.0)
        // The immediate window does not wait for the screen.
        #expect(change.window(.immediate, settleTime: 1, tolerance: 0.5) == 1.75...4.25)
        // Not watched: from the ask to the done, the settle time later.
        #expect(ChangeTimes(asked: 2.25, done: 3.75).window(.settled, settleTime: 1, tolerance: 0.5) == 2.75...5.25)
    }

    @Test func theSettledWindowFollowsTheLaterOfTheNoticeAndTheLastChange() {
        var change = ChangeTimes(asked: 2.0, done: 2.75, lastChange: 2.0625)
        change.notice = 2.5
        #expect(change.anchor == .init(time: 2.5, source: .notice))
        #expect(change.window(.settled, settleTime: 1, tolerance: 0.5) == 3.0...4.0)
        change.notice = 1.75
        #expect(change.anchor == .init(time: 2.0625, source: .lastChange))
        #expect(change.window(.settled, settleTime: 1, tolerance: 0.5) == 2.5625...3.5625)
    }
}
