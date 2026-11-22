import Testing
@testable import RecorderLogic

/// A camera that delivers no frames is failing, not showing a still
/// picture; one that pauses is stalled first (D74).
@Suite struct CameraFrameWatchTests {
    private let watch = CameraFrameWatch()
    private let second: Int64 = 1_000_000_000

    @Test func theLimitsAreFiveSecondsToTheFirstFrameTenForAnIPhoneTwoToAStallAndTenToAFailure() {
        #expect(watch.firstFrameLimit == .seconds(5))
        #expect(watch.continuityFirstFrameLimit == .seconds(10))
        #expect(watch.stallLimit == .seconds(2))
        #expect(watch.frameGapLimit == .seconds(10))
    }

    @Test func noFirstFrameWithinTheLimitIsAFailure() {
        #expect(watch.verdict(startedAt: 10 * second, lastFrameAt: nil, now: 14 * second, isContinuity: false) == .delivering)
        #expect(watch.verdict(startedAt: 10 * second, lastFrameAt: nil, now: 15 * second, isContinuity: false)
            == .failed("the camera delivered no frame within 5 s of its start"))
    }

    @Test func anIPhoneCameraHasTenSecondsToItsFirstFrame() {
        #expect(watch.verdict(startedAt: 10 * second, lastFrameAt: nil, now: 19 * second, isContinuity: true) == .delivering)
        #expect(watch.verdict(startedAt: 10 * second, lastFrameAt: nil, now: 20 * second, isContinuity: true)
            == .failed("the camera delivered no frame within 10 s of its start"))
    }

    @Test func noFrameForTwoSecondsIsAStallAndForTenAFailureWhateverTheStart() {
        #expect(watch.verdict(startedAt: 0, lastFrameAt: 20 * second, now: 21 * second, isContinuity: false) == .delivering)
        #expect(watch.verdict(startedAt: 0, lastFrameAt: 20 * second, now: 22 * second, isContinuity: false) == .stalled)
        #expect(watch.verdict(startedAt: 0, lastFrameAt: 20 * second, now: 29 * second, isContinuity: true) == .stalled)
        #expect(watch.verdict(startedAt: 0, lastFrameAt: 20 * second, now: 30 * second, isContinuity: false)
            == .failed("the camera delivered no frame for 10 s"))
    }

    @Test func itIsCheckedFourTimesWithinTheShorterLimit() {
        #expect(watch.checkInterval == .milliseconds(500))
        #expect(CameraFrameWatch(firstFrameLimit: .milliseconds(400), stallLimit: .seconds(1)).checkInterval == .milliseconds(100))
    }
}
