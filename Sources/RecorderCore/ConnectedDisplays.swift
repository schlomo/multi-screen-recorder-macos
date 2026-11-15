import AppKit
import CoreGraphics
import RecorderLogic

/// The displays macOS reports now, each known by its UUID, the ones that
/// mirror another included. Needs no permission.
@MainActor
public func connectedDisplays() throws(DeviceReadError) -> [ConnectedDisplay] {
    var count: UInt32 = 0
    guard CGGetOnlineDisplayList(0, nil, &count) == .success else {
        throw DeviceReadError("the list of displays cannot be read")
    }
    var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
    guard CGGetOnlineDisplayList(count, &ids, &count) == .success else {
        throw DeviceReadError("the list of displays cannot be read")
    }
    let names = Dictionary(
        NSScreen.screens.compactMap { screen -> (CGDirectDisplayID, String)? in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return nil }
            return (CGDirectDisplayID(number.uint32Value), screen.localizedName)
        },
        uniquingKeysWith: { first, _ in first })
    let online = ids.prefix(Int(count)).filter { CGDisplayIsAsleep($0) == 0 }
    let uuids = Dictionary(uniqueKeysWithValues: try online.map { id throws(DeviceReadError) in (id, try uuid(of: id)) })
    return try online.map { id throws(DeviceReadError) in
        guard let mode = CGDisplayCopyDisplayMode(id) else {
            throw DeviceReadError("the display \(names[id] ?? String(id)) does not report its display mode")
        }
        let bounds = CGDisplayBounds(id)
        let mirrored = CGDisplayMirrorsDisplay(id)
        return ConnectedDisplay(
            uuid: uuids[id]!, displayID: id, name: names[id],
            pointSize: FrameSize(width: mode.width, height: mode.height),
            bounds: ScreenRect(bounds),
            isMain: CGDisplayIsMain(id) != 0,
            mirrorsUUID: mirrored == kCGNullDirectDisplay ? nil : (uuids[mirrored] ?? (try? uuid(of: mirrored))))
    }
}

private func uuid(of id: CGDirectDisplayID) throws(DeviceReadError) -> String {
    guard let uuid = CGDisplayCreateUUIDFromDisplayID(id)?.takeRetainedValue(),
          let text = CFUUIDCreateString(nil, uuid) as String?
    else { throw DeviceReadError("the display \(id) does not report its UUID") }
    return text
}

extension ScreenRect {
    init(_ rect: CGRect) {
        self.init(x: rect.origin.x, y: rect.origin.y, width: rect.size.width, height: rect.size.height)
    }
}
