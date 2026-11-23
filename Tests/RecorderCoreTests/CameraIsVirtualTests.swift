import AVFoundation
import Testing
@testable import RecorderCore

/// Which cameras are virtual and which are an iPhone's, by AVFoundation's device type and Core Audio's transport type (D74).
@Suite struct CameraIsVirtualTests {
    private func transport(_ code: String) -> Int32 {
        Int32(bitPattern: code.utf8.reduce(0) { $0 << 8 | UInt32($1) })
    }

    @Test func builtInContinuityAndDeskViewCamerasAreNotVirtual() {
        for type in [AVCaptureDevice.DeviceType.builtInWideAngleCamera, .continuityCamera, .deskViewCamera] {
            #expect(!cameraIsVirtual(deviceType: type, transportType: 0))
        }
    }

    /// An iPhone's camera is a Continuity Camera or Desk View, or connected by Continuity Capture (D74).
    @Test func continuityAndDeskViewCamerasAndContinuityCaptureAreIPhoneCameras() {
        for type in [AVCaptureDevice.DeviceType.continuityCamera, .deskViewCamera] {
            #expect(cameraIsContinuity(deviceType: type, transportType: 0))
        }
        for code in ["ccwd", "ccwl"] {
            #expect(cameraIsContinuity(deviceType: .external, transportType: transport(code)), "\(code)")
        }
        #expect(!cameraIsContinuity(deviceType: .builtInWideAngleCamera, transportType: transport("bltn")))
        #expect(!cameraIsContinuity(deviceType: .external, transportType: transport("usb ")))
        #expect(!cameraIsContinuity(deviceType: .external, transportType: transport("virt")))
    }

    @Test func anExternalCameraIsNotVirtualByItsPort() {
        for code in ["bltn", "usb ", "1394", "pci ", "thun", "ccwd", "ccwl"] {
            #expect(!cameraIsVirtual(deviceType: .external, transportType: transport(code)), "\(code)")
        }
    }

    @Test func anExternalCameraOfAVirtualOrUnknownTransportIsVirtual() {
        for code in ["virt", "grup", "airp", "blue"] {
            #expect(cameraIsVirtual(deviceType: .external, transportType: transport(code)), "\(code)")
        }
        #expect(cameraIsVirtual(deviceType: .external, transportType: 0))
    }
}
