import AppKit
import CoreGraphics

/// Content that changes every frame on a virtual screen: a borderless
/// window covering only that screen, with a block that moves and a frame
/// counter. Screen capture delivers a new frame only when the picture
/// changes, so a static screen gives no frames to start its file
/// (docs/design/end-to-end-tests.md, "Known content"). The window never
/// takes the focus or the mouse, and ends with the helper's process.
@MainActor
final class MovingContent {
    private let display: CGDirectDisplayID
    private let window: NSWindow
    private let view = MovingView()
    private var timer: Timer?

    init(display: CGDirectDisplayID) {
        self.display = display
        NSApplication.shared.setActivationPolicy(.accessory)
        window = NSWindow(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.ignoresMouseEvents = true
        window.hasShadow = false
        window.collectionBehavior = [.stationary, .ignoresCycle, .fullScreenNone]
        window.contentView = view
        follow()
        window.orderFrontRegardless()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
    }

    private func tick() {
        follow()
        view.frameCount += 1
        view.needsDisplay = true
    }

    /// Keeps the window on the virtual screen's bounds, which change with a
    /// mode switch; Cocoa counts from the main screen's bottom left.
    private func follow() {
        let bounds = CGDisplayBounds(display)
        let mainHeight = CGDisplayBounds(CGMainDisplayID()).height
        let frame = NSRect(x: bounds.minX, y: mainHeight - bounds.maxY, width: bounds.width, height: bounds.height)
        if window.frame != frame { window.setFrame(frame, display: false) }
    }
}

private final class MovingView: NSView {
    var frameCount = 0

    override func draw(_ dirtyRect: NSRect) {
        NSColor(calibratedWhite: 0.15, alpha: 1).setFill()
        bounds.fill()
        let side = bounds.height / 4
        let travel = max(bounds.width - side, 1)
        let x = CGFloat(frameCount * 8).truncatingRemainder(dividingBy: travel)
        NSColor.white.setFill()
        NSRect(x: x, y: (bounds.height - side) / 2, width: side, height: side).fill()
        let label = NSAttributedString(string: "frame \(frameCount)", attributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 48, weight: .regular), .foregroundColor: NSColor.white,
        ])
        label.draw(at: NSPoint(x: 40, y: 40))
    }
}
