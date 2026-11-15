import Foundation

/// A display as macOS reports it at one moment, known by its UUID (display
/// identity, D45): the display ID changes when a display comes back, and the
/// name may change too.
public struct ConnectedDisplay: Equatable, Sendable {
    public var uuid: String
    public var displayID: UInt32
    /// Nil when macOS gives no name, such as for a display that mirrors another.
    public var name: String?
    /// Looks like: the size in points.
    public var pointSize: FrameSize
    /// `CGDisplayBounds`: in points, in the global display space.
    public var bounds: ScreenRect
    public var isMain: Bool
    /// The UUID of the display this one mirrors, nil when it mirrors none.
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

    var isMirroring: Bool { mirrorsUUID != nil }
}

/// A rectangle in points in the global display space, top-left origin, as
/// `CGDisplayBounds` gives a display's and ScreenCaptureKit a frame's.
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
