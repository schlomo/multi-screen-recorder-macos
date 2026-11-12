import AppKit
import AVFoundation
import CoreGraphics
import CoreMedia
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
            isMain: id == mainID,
            originX: bounds.origin.x,
            originY: bounds.origin.y)
    }
}

/// The audio inputs, the default one marked. Listing needs no permission.
public func currentAudioInputs() throws(DeviceReadError) -> [AudioInputInfo] {
    let devices = AVCaptureDevice.DiscoverySession(
        deviceTypes: [.microphone, .external], mediaType: .audio, position: .unspecified
    ).devices
    let defaultID = AVCaptureDevice.default(for: .audio)?.uniqueID
    return try devices.map { device throws(DeviceReadError) in
        AudioInputInfo(name: device.localizedName, channelCount: try channelCount(of: device),
                       isDefault: device.uniqueID == defaultID)
    }
}

/// The name of the default audio input, if there is one.
public func defaultAudioInputName() -> String? {
    AVCaptureDevice.default(for: .audio)?.localizedName
}

private func channelCount(of device: AVCaptureDevice) throws(DeviceReadError) -> Int {
    guard let format = CMAudioFormatDescriptionGetStreamBasicDescription(device.activeFormat.formatDescription) else {
        throw DeviceReadError("the audio input \(device.localizedName) does not report its format")
    }
    return Int(format.pointee.mChannelsPerFrame)
}
