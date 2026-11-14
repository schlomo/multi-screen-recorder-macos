import AppKit
import CoreGraphics
import RecorderLogic

/// The connected displays, mirrored ones excluded. Needs no permission.
@MainActor
public func currentDisplays() throws(DeviceReadError) -> [DisplayInfo] {
    let mainID = CGMainDisplayID()
    return try NSScreen.screens.map { screen throws(DeviceReadError) in
        guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            throw DeviceReadError("the display \(screen.localizedName) does not report its display number")
        }
        let id = CGDirectDisplayID(number.uint32Value)
        guard let mode = CGDisplayCopyDisplayMode(id) else {
            throw DeviceReadError("the display \(screen.localizedName) does not report its display mode")
        }
        let bounds = CGDisplayBounds(id)
        return DisplayInfo(
            name: screen.localizedName,
            pixelSize: FrameSize(width: mode.pixelWidth, height: mode.pixelHeight),
            pointSize: FrameSize(width: mode.width, height: mode.height),
            isMain: id == mainID,
            originX: bounds.origin.x,
            originY: bounds.origin.y)
    }
}
