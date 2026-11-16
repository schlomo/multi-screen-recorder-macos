import Foundation
import ScreenCaptureKit
import Testing
@testable import RecorderCore

/// How a stream's error ends a screen file; no stream is started.
@Suite struct StreamEndTests {
    /// -3815: the screen the stream captured is gone, as on an unplug (F4).
    @Test func aCaptureSourceGoneIsNoFailure() {
        let gone = NSError(domain: SCStreamErrorDomain, code: SCStreamError.Code.noCaptureSource.rawValue)
        #expect(SCStreamError.Code.noCaptureSource.rawValue == -3815)
        #expect(ScreenCapture.streamEnd(for: gone) == .captureSourceGone)
    }

    @Test func anyOtherStreamErrorIsAFailure() {
        let internalError = NSError(domain: SCStreamErrorDomain, code: SCStreamError.Code.internalError.rawValue)
        guard case .streamFailed = ScreenCapture.streamEnd(for: internalError) else {
            Issue.record("not a failure")
            return
        }
        guard case .streamFailed = ScreenCapture.streamEnd(for: NSError(domain: NSPOSIXErrorDomain, code: -3815)) else {
            Issue.record("another domain's -3815 is not the capture source gone")
            return
        }
    }
}
