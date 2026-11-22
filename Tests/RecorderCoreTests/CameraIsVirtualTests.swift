import AVFoundation
import Testing
@testable import RecorderCore

/// Which cameras are virtual, by AVFoundation's device type and Core Audio's transport type (D74).
@Suite struct CameraIsVirtualTests {
    private func transport(_ code: String) -> Int32 {
        Int32(bitPattern: code.utf8.reduce(0) { $0 << 8 | UInt32($1) })
    }

    @Test func builtInContinuityAndDeskViewCamerasAreReal() {
        for type in [AVCaptureDevice.DeviceType.builtInWideAngleCamera, .continuityCamera, .deskViewCamera] {
            #expect(!cameraIsVirtual(deviceType: type, transportType: 0))
        }
    }

    @Test func anExternalCameraIsRealByItsPort() {
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
