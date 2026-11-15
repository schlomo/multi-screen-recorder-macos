import Testing
@testable import RecorderLogic

@Suite struct DisplayCheckTests {
    private let own = ScreenRect(x: 0, y: 0, width: 1728, height: 1117)
    private let other = ScreenRect(x: 1728, y: 0, width: 3840, height: 2160)
    private let second: Int64 = 1_000_000_000

    @Test func aFrameAtItsDisplaysBoundsPasses() {
        var check = DisplayCheck()
        #expect(check.judge(frameRect: own, displayBounds: own, capturedAt: 0, lastDisplayChange: nil) == .passes)
        let rounded = ScreenRect(x: 0.2, y: 0, width: 1728, height: 1116.8)
        #expect(check.judge(frameRect: rounded, displayBounds: own, capturedAt: 0, lastDisplayChange: nil) == .passes)
    }

    @Test func oneSecondOfFailingFramesInARowShowsAnotherDisplay() {
        #expect(RecorderValues.displayCheckFailuresInARow == RecorderValues.framesPerSecond)
        var check = DisplayCheck()
        for _ in 1..<RecorderValues.displayCheckFailuresInARow {
            #expect(check.judge(frameRect: other, displayBounds: own, capturedAt: 10 * second, lastDisplayChange: nil) == .fails)
        }
        #expect(check.judge(frameRect: other, displayBounds: own, capturedAt: 10 * second, lastDisplayChange: nil)
            == .showsAnotherDisplay)
    }

    @Test func aPassingFrameStartsTheCountOver() {
        var check = DisplayCheck(failuresInARow: 3)
        _ = check.judge(frameRect: other, displayBounds: own, capturedAt: 0, lastDisplayChange: nil)
        _ = check.judge(frameRect: other, displayBounds: own, capturedAt: 0, lastDisplayChange: nil)
        _ = check.judge(frameRect: own, displayBounds: own, capturedAt: 0, lastDisplayChange: nil)
        #expect(check.judge(frameRect: other, displayBounds: own, capturedAt: 0, lastDisplayChange: nil) == .fails)
        #expect(check.judge(frameRect: other, displayBounds: own, capturedAt: 0, lastDisplayChange: nil) == .fails)
        #expect(check.judge(frameRect: other, displayBounds: own, capturedAt: 0, lastDisplayChange: nil) == .showsAnotherDisplay)
    }

    @Test func failingFramesWithinTheSettleTimeAfterAChangeAreNotCounted() {
        var check = DisplayCheck(failuresInARow: 2, settleTime: .seconds(1))
        let change = 5 * second
        for tenth in Int64(0)..<10 {
            let offset = tenth * second / 10
            #expect(check.judge(frameRect: other, displayBounds: own, capturedAt: change + offset, lastDisplayChange: change) == .fails)
        }
        #expect(check.failuresSoFar == 0)
        #expect(check.judge(frameRect: other, displayBounds: own, capturedAt: change + second, lastDisplayChange: change) == .fails)
        #expect(check.judge(frameRect: other, displayBounds: own, capturedAt: change + second, lastDisplayChange: change)
            == .showsAnotherDisplay)
    }
}
