import Testing
@testable import EndToEndLogic

@Suite struct ScreenSettlingTests {
    let before = ["main 0,0 1024x768"]
    let after = ["main 0,0 1024x768", "virtual 1024,0 1280x720"]
    let knockOn = ["main 0,0 1920x1080", "virtual 1920,0 1280x720"]

    func observed(_ states: [(Double, [String])]) -> [ScreenSettling.Observation] {
        states.map { .init(time: $0.0, screens: $0.1) }
    }

    @Test func screensUnchangedAfterTheChangeSettleTheSettleTimeAfterIt() {
        let settled = ScreenSettling.settledAt(changeDone: 3.0, observations: observed([(3.0, after), (3.5, after), (4.1, after)]),
                                               settleTime: 1)
        #expect(settled == 4.0)
    }

    @Test func aKnockOnChangeOfAnotherScreenStartsTheSettleTimeAgain() {
        // As on the runner: the connect also switched the own screen's mode.
        let settled = ScreenSettling.settledAt(
            changeDone: 3.75, observations: observed([(3.75, after), (4.25, knockOn), (4.5, knockOn), (5.2, knockOn), (6.25, knockOn)]),
            settleTime: 1)
        #expect(settled == 5.25)
    }

    @Test func aChangeAfterTheScreensSettledBelongsToSomethingElse() {
        let settled = ScreenSettling.settledAt(
            changeDone: 3.0, observations: observed([(3.0, after), (4.2, after), (4.5, knockOn), (5.6, knockOn)]), settleTime: 1)
        #expect(settled == 4.0)
    }

    @Test func screensStillChangingHaveNotSettled() {
        let settled = ScreenSettling.settledAt(changeDone: 3.0, observations: observed([(3.0, after), (3.6, knockOn), (4.2, knockOn)]),
                                               settleTime: 1)
        #expect(settled == nil)
        #expect(before != after)
    }

    @Test func theSettledWindowEndsWhenTheScreensSettledAndStillStartsAfterTheSettleTime() {
        let change = ChangeTimes(asked: 2.25, done: 3.75, screensSettled: 6.0)
        let window = change.window(.settled, settleTime: 1, tolerance: 0.5)
        #expect(window == 2.75...6.5)
        // A file that starts before the change could have settled still fails.
        #expect(!window.contains(2.5))
        // The immediate window does not wait for the screens.
        #expect(change.window(.immediate, settleTime: 1, tolerance: 0.5) == 1.75...4.25)
        // Without a watch, the done plus the settle time.
        #expect(ChangeTimes(asked: 2.25, done: 3.75).window(.settled, settleTime: 1, tolerance: 0.5) == 2.75...5.25)
    }
}
