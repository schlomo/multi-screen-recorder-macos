/// Decides when the start window may re-read the devices: at once, unless one
/// of its menus is open. A window that changes under an open menu has
/// crashed in AppKit, so a change that arrives then waits for the menu to
/// close.
public struct RefreshGate: Sendable {
    private var openMenus = 0
    private var changeIsWaiting = false

    public init() {}

    public var isMenuOpen: Bool { openMenus > 0 }

    /// True if the change may be acted on now; otherwise it waits.
    public mutating func changeArrived() -> Bool {
        guard isMenuOpen else { return true }
        changeIsWaiting = true
        return false
    }

    public mutating func menuOpened() {
        openMenus += 1
    }

    /// True if a change waited and the last menu has closed.
    public mutating func menuClosed() -> Bool {
        openMenus = max(0, openMenus - 1)
        guard !isMenuOpen, changeIsWaiting else { return false }
        changeIsWaiting = false
        return true
    }
}
