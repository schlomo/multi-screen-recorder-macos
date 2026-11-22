import Testing
@testable import RecorderLogic

/// A camera's dropped frames reach the recording log at most once a second, counted (D74).
@Suite struct DroppedFramesTests {
    private let millisecond: Int64 = 1_000_000

    @Test func theFirstDropIsWrittenAtOnceAndTheNextOnesOnceASecondCounted() {
        var drops = DroppedFrames()
        #expect(drops.dropped(reason: "FrameWasLate", at: 0) == "1 frame dropped: FrameWasLate 1")
        #expect(drops.dropped(reason: "FrameWasLate", at: 300 * millisecond) == nil)
        #expect(drops.dropped(reason: "OutOfBuffers", at: 600 * millisecond) == nil)
        #expect(drops.dropped(reason: "FrameWasLate", at: 1000 * millisecond)
            == "3 frames dropped: FrameWasLate 2, OutOfBuffers 1")
        #expect(drops.remaining() == nil)
    }

    @Test func theDropsNotWrittenYetAreWrittenAtTheEnd() {
        var drops = DroppedFrames()
        _ = drops.dropped(reason: "Discontinuity", at: 0)
        _ = drops.dropped(reason: "Discontinuity", at: millisecond)
        #expect(drops.remaining() == "1 frame dropped: Discontinuity 1")
        #expect(drops.remaining() == nil)
    }
}
