/// The position of `step` on a slider that runs over `steps`.
func indexOnSlider<Step: Equatable>(of step: Step, in steps: [Step]) -> Double {
    Double(steps.firstIndex(of: step)!)
}

/// The step a slider's `position` selects (rounded, kept in range), or nil
/// when that is `current`: nothing to change, save or check.
func sliderChoice<Step: Equatable>(at position: Double, in steps: [Step], current: Step) -> Step? {
    let chosen = steps[min(max(Int(position.rounded()), 0), steps.count - 1)]
    return chosen == current ? nil : chosen
}
