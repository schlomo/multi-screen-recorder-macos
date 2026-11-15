import Testing
@testable import RecorderLogic

@Suite struct RecordingResolutionOrderTests {
    @Test func smallestFirstHoldsEveryResolutionOnce() {
        #expect(RecordingResolution.smallestFirst.count == RecordingResolution.allCases.count)
        #expect(Set(RecordingResolution.smallestFirst) == Set(RecordingResolution.allCases))
    }

    @Test func nativeIsLastAndTheOthersAscendByBoxHeight() {
        #expect(RecordingResolution.smallestFirst.last == .native)
        let heights = RecordingResolution.smallestFirst.dropLast().map { $0.box!.height }
        #expect(heights == heights.sorted())
        #expect(Set(heights).count == heights.count)
    }

    @Test func theOrderIsTheSliderOrder() {
        #expect(RecordingResolution.smallestFirst.map(\.label) == ["720p", "1080p", "1200p", "1440p", "4K", "Native"])
    }
}
