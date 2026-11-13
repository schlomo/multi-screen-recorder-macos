import Foundation

/// Runs `action` when the main run loop is next in its default mode: with
/// its next pass when it is idle there, and otherwise when the open menu,
/// the dragged control or the modal panel that put it into another mode is
/// let go. That AppKit leaves the default mode for those is how it is
/// documented to work, not observed in this app [ASSUMED].
@MainActor
public func whenMainRunLoopIsInDefaultMode(_ action: @escaping @MainActor () -> Void) {
    RunLoop.main.perform(inModes: [.default]) { MainActor.assumeIsolated(action) }
}
