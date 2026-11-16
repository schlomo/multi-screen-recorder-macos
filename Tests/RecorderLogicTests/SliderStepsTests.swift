import Testing
@testable import RecorderLogic

@Suite struct SliderStepsTests {
    private let steps = AudioMode.allCases

    @Test func aPositionSelectsTheNearestStepKeptInRange() {
        #expect(sliderChoice(at: 1.4, in: steps, current: .none) == .defaultMicrophone)
        #expect(sliderChoice(at: -3, in: steps, current: .wired) == AudioMode.none)
        #expect(sliderChoice(at: 99, in: steps, current: .none) == .allInputs)
        #expect(sliderChoice(at: 2, in: steps, current: .wired) == nil)
    }

    @Test func aPositionThatIsNoNumberOrOutOfAnyRangeChangesNothingAndNeverCrashes() {
        #expect(sliderChoice(at: .nan, in: steps, current: .wired) == nil)
        #expect(sliderChoice(at: .infinity, in: steps, current: .wired) == nil)
        #expect(sliderChoice(at: -.infinity, in: steps, current: .wired) == nil)
        #expect(sliderChoice(at: 1e300, in: steps, current: .none) == .allInputs)
        #expect(sliderChoice(at: -1e300, in: steps, current: .wired) == AudioMode.none)
    }
}
