import Testing
@testable import RecorderLogic

/// A camera that delivers no frames is failing, not showing a still picture (D74).
@Suite struct CameraFrameWatchTests {
    private let watch = CameraFrameWatch()
    private let second: Int64 = 1_000_000_000

    @Test func theLimitsAreFiveSecondsToTheFirstFrameAndTwoBetweenFrames() {
        #expect(watch.firstFrameLimit == .seconds(5))
        #expect(watch.frameGapLimit == .seconds(2))
    }

    @Test func noFirstFrameWithinTheLimitIsAFailure() {
        #expect(watch.failure(startedAt: 10 * second, lastFrameAt: nil, now: 14 * second) == nil)
        #expect(watch.failure(startedAt: 10 * second, lastFrameAt: nil, now: 15 * second)
            == "the camera delivered no frame within 5 s of its start")
    }

    @Test func noFrameForTheGapLimitIsAFailureWhateverTheStart() {
        #expect(watch.failure(startedAt: 0, lastFrameAt: 20 * second, now: 21 * second) == nil)
        #expect(watch.failure(startedAt: 0, lastFrameAt: 20 * second, now: 22 * second)
            == "the camera delivered no frame for 2 s")
    }

    @Test func itIsCheckedFourTimesWithinTheShorterLimit() {
        #expect(watch.checkInterval == .milliseconds(500))
        #expect(CameraFrameWatch(firstFrameLimit: .milliseconds(400), frameGapLimit: .seconds(1)).checkInterval == .milliseconds(100))
    }
}
