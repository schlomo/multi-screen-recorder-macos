import AppKit
import AVFoundation
import CoreGraphics
import CoreMedia
import RecorderLogic

/// The connected displays, mirrored ones excluded. Needs no permission.
@MainActor
public func currentDisplays() -> [DisplayInfo] {
    let mainID = CGMainDisplayID()
    return NSScreen.screens.compactMap { screen in
        guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
              let mode = CGDisplayCopyDisplayMode(number.uint32Value)
        else { return nil }
        let id = CGDirectDisplayID(number.uint32Value)
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
public func currentAudioInputs() -> [AudioInputInfo] {
    let devices = AVCaptureDevice.DiscoverySession(
        deviceTypes: [.microphone, .external], mediaType: .audio, position: .unspecified
    ).devices
    let defaultID = AVCaptureDevice.default(for: .audio)?.uniqueID
    return devices.map { device in
        AudioInputInfo(name: device.localizedName, channelCount: channelCount(of: device),
                       isDefault: device.uniqueID == defaultID)
    }
}

/// The default audio input, if there is one.
public func defaultAudioInput() -> AudioInputInfo? {
    AVCaptureDevice.default(for: .audio).map {
        AudioInputInfo(name: $0.localizedName, channelCount: channelCount(of: $0), isDefault: true)
    }
}

private func channelCount(of device: AVCaptureDevice) -> Int {
    let description = device.activeFormat.formatDescription
    guard let format = CMAudioFormatDescriptionGetStreamBasicDescription(description) else { return 0 }
    return Int(format.pointee.mChannelsPerFrame)
}
