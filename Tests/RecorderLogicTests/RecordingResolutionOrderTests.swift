import Testing
@testable import RecorderLogic

@Suite struct RecordingResolutionOrderTests {
    @Test func smallestFirstHoldsEveryResolutionOnce() {
        #expect(RecordingResolution.smallestFirst.count == RecordingResolution.allCases.count)
        #expect(Set(RecordingResolution.smallestFirst) == Set(RecordingResolution.allCases))
    }

    @Test func noneIsFirstNativeIsLastAndTheOthersAscendByBoxHeight() {
        #expect(RecordingResolution.smallestFirst.first == RecordingResolution.none)
        #expect(RecordingResolution.smallestFirst.last == .native)
        let heights = RecordingResolution.smallestFirst.dropFirst().dropLast().map { $0.box!.height }
        #expect(heights == heights.sorted())
        #expect(Set(heights).count == heights.count)
    }

    @Test func theOrderIsTheSliderOrder() {
        #expect(RecordingResolution.smallestFirst.map(\.shownName) == ["None", "720p", "1080p", "1200p", "1440p", "4K", "Native"])
    }

    @Test func theSliderIndexRoundTrips() {
        for (index, resolution) in RecordingResolution.smallestFirst.enumerated() {
            #expect(resolution.sliderIndex == Double(index))
            #expect(resolution.choosing(sliderPosition: Double(index)) == nil)
            #expect(RecordingResolution.p720.choosing(sliderPosition: Double(index)) == (resolution == .p720 ? nil : resolution))
        }
    }

    @Test func aSliderPositionIsRoundedAndKeptInRange() {
        #expect(RecordingResolution.p720.choosing(sliderPosition: 2.4) == .p1080)
        #expect(RecordingResolution.p720.choosing(sliderPosition: 2.6) == .p1200)
        #expect(RecordingResolution.p720.choosing(sliderPosition: 99) == .native)
        #expect(RecordingResolution.native.choosing(sliderPosition: -3) == RecordingResolution.none)
        #expect(RecordingResolution.p1080.choosing(sliderPosition: 2.2) == nil)
    }

    /// Audio only: None records no screen, every other resolution records them all.
    @Test func noneAloneRecordsNoScreen() {
        #expect(RecordingResolution.allCases.filter { !$0.recordsScreens } == [RecordingResolution.none])
        #expect(RecordingResolution.none.rawValue == "none")
        #expect(RecordingResolution.none.box == nil)
    }
}
