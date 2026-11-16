/// The position of `step` on a slider that runs over `steps`.
func indexOnSlider<Step: Equatable>(of step: Step, in steps: [Step]) -> Double {
    Double(steps.firstIndex(of: step)!)
}

/// The step a slider's `position` selects (rounded, kept in range), or nil
/// when that is `current` or the position is no number: nothing to change,
/// save or check.
func sliderChoice<Step: Equatable>(at position: Double, in steps: [Step], current: Step) -> Step? {
    guard position.isFinite, !steps.isEmpty else { return nil }
    let index = Int(min(max(position.rounded(), 0), Double(steps.count - 1)))
    let chosen = steps[index]
    return chosen == current ? nil : chosen
}
