import Foundation

/// Runs `action` when the main run loop is next in its default mode: with
/// its next pass when it is idle there, and otherwise when the open menu,
/// the dragged control or the modal panel that put it into another mode is
/// let go.
@MainActor
public func whenMainRunLoopIsInDefaultMode(_ action: @escaping @MainActor () -> Void) {
    RunLoop.main.perform(inModes: [.default]) { MainActor.assumeIsolated(action) }
}
