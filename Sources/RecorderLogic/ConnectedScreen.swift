import Foundation

/// A screen as macOS reports it at one moment, known by its UUID (screen
/// identity, D45): the display ID changes when a screen comes back, and the
/// name may change too.
public struct ConnectedScreen: Equatable, Sendable {
    public var uuid: String
    public var displayID: UInt32
    /// Nil when macOS gives no name, such as for a screen that mirrors another.
    public var name: String?
    /// Looks like: the size in points.
    public var pointSize: FrameSize
    /// `CGDisplayBounds`: in points, in the global screen space.
    public var bounds: ScreenRect
    public var isMain: Bool
    /// The UUID of the screen this one mirrors, nil when it mirrors none.
    public var mirrorsUUID: String?

    public init(
        uuid: String, displayID: UInt32, name: String?, pointSize: FrameSize, bounds: ScreenRect, isMain: Bool,
        mirrorsUUID: String? = nil
    ) {
        self.uuid = uuid
        self.displayID = displayID
        self.name = name
        self.pointSize = pointSize
        self.bounds = bounds
        self.isMain = isMain
        self.mirrorsUUID = mirrorsUUID
    }

    public var isMirroring: Bool { mirrorsUUID != nil }
}

extension ConnectedScreen: PlacedScreen {
    public var originX: Double { bounds.x }
    public var originY: Double { bounds.y }
    public var placementTieBreak: String { uuid }
}

/// A screen where the recording numbers it: main first, then left to
/// right, then top to bottom (D45).
public protocol PlacedScreen {
    var isMain: Bool { get }
    var originX: Double { get }
    var originY: Double { get }
    /// It mirrors another screen, so a recording does not record it.
    var isMirroring: Bool { get }
    /// Orders two screens at the same place.
    var placementTieBreak: String { get }
}

/// A rectangle in points in the global screen space, top-left origin, as
/// `CGDisplayBounds` gives a screen's and ScreenCaptureKit a frame's.
public struct ScreenRect: Equatable, Sendable, CustomStringConvertible {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public var description: String { "(\(x), \(y), \(width)×\(height))" }
}
