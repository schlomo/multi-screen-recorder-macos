import Testing
@testable import RecorderLogic

/// Only a change of the active format the recording did not make is another app's (D74).
@Suite struct ForeignFormatWatchTests {
    private let ours = CameraFormat(size: FrameSize(width: 1920, height: 1080), maxFramesPerSecond: 30)
    private let theirs = CameraFormat(size: FrameSize(width: 1280, height: 720), maxFramesPerSecond: 30)

    @Test func theRecordingsOwnOpenChangesNothing() {
        var watch = ForeignFormatWatch()
        // While the open configures the camera, its changes are its own.
        #expect(!watch.isForeign(theirs))
        #expect(!watch.isForeign(ours))
        watch.opened(in: ours)
        #expect(!watch.isForeign(ours))
    }

    @Test func aChangeAfterTheOpenToAnotherFormatIsAnotherApps() {
        var watch = ForeignFormatWatch()
        watch.opened(in: ours)
        #expect(watch.isForeign(theirs))
    }
}
