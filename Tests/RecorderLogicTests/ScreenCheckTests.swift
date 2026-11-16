import Testing
@testable import RecorderLogic

@Suite struct ScreenCheckTests {
    private let own = ScreenRect(x: 0, y: 0, width: 1728, height: 1117)
    private let other = ScreenRect(x: 1728, y: 0, width: 3840, height: 2160)
    private let second: Int64 = 1_000_000_000

    @Test func aFrameAtItsScreensBoundsPasses() {
        var check = ScreenCheck()
        #expect(check.judge(frameRect: own, screenBounds: own, capturedAt: 0, lastScreenChange: nil) == .passes)
        let rounded = ScreenRect(x: 0.2, y: 0, width: 1728, height: 1116.8)
        #expect(check.judge(frameRect: rounded, screenBounds: own, capturedAt: 0, lastScreenChange: nil) == .passes)
    }

    @Test func oneSecondOfFailingFramesInARowShowsAnotherScreen() {
        #expect(RecorderValues.screenCheckFailuresInARow == RecorderValues.framesPerSecond)
        var check = ScreenCheck()
        for _ in 1..<RecorderValues.screenCheckFailuresInARow {
            #expect(check.judge(frameRect: other, screenBounds: own, capturedAt: 10 * second, lastScreenChange: nil) == .fails)
        }
        #expect(check.judge(frameRect: other, screenBounds: own, capturedAt: 10 * second, lastScreenChange: nil)
            == .showsAnotherScreen)
    }

    @Test func aPassingFrameStartsTheCountOver() {
        var check = ScreenCheck(failuresInARow: 3)
        _ = check.judge(frameRect: other, screenBounds: own, capturedAt: 0, lastScreenChange: nil)
        _ = check.judge(frameRect: other, screenBounds: own, capturedAt: 0, lastScreenChange: nil)
        _ = check.judge(frameRect: own, screenBounds: own, capturedAt: 0, lastScreenChange: nil)
        #expect(check.judge(frameRect: other, screenBounds: own, capturedAt: 0, lastScreenChange: nil) == .fails)
        #expect(check.judge(frameRect: other, screenBounds: own, capturedAt: 0, lastScreenChange: nil) == .fails)
        #expect(check.judge(frameRect: other, screenBounds: own, capturedAt: 0, lastScreenChange: nil) == .showsAnotherScreen)
    }

    @Test func failingFramesWithinTheSettleTimeAfterAChangeAreNotCounted() {
        var check = ScreenCheck(failuresInARow: 2, settleTime: .seconds(1))
        let change = 5 * second
        for tenth in Int64(0)..<10 {
            let offset = tenth * second / 10
            #expect(check.judge(frameRect: other, screenBounds: own, capturedAt: change + offset, lastScreenChange: change) == .fails)
        }
        #expect(check.failuresSoFar == 0)
        #expect(check.judge(frameRect: other, screenBounds: own, capturedAt: change + second, lastScreenChange: change) == .fails)
        #expect(check.judge(frameRect: other, screenBounds: own, capturedAt: change + second, lastScreenChange: change)
            == .showsAnotherScreen)
    }
}
