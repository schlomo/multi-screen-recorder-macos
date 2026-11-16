import Testing
@testable import RecorderLogic

@Suite struct ScreenFileMetadataTests {
    private let metadata = ScreenFileMetadata(
        screenUUID: "U", screenNumber: 2, screenName: "LG HDR 4K", frameSize: FrameSize(width: 1920, height: 1080),
        recordingStarted: "2026-11-12T14:03:05.120+01:00", app: "Multi Screen Recorder 1")

    @Test func theReelNameIsTheSourceAsInTheFileName() {
        #expect(metadata.reelName == "Screen 2 - LG HDR 4K")
        #expect(RecordingNames.screenFile(start: .now, timeZone: .current, number: 2, screen: "LG HDR 4K").contains(metadata.reelName))
    }

    @Test func everyItemIsUnderTheAppsKeysAndTheAppAlsoAsSoftware() {
        let keys = metadata.items.map(\.key)
        #expect(keys.dropLast(3).allSatisfy { $0.hasPrefix("org.schapiro.multiscreenrecorder.") })
        #expect(metadata.items.suffix(3).map(\.key) == ["com.apple.quicktime.software", "com.apple.proapps.reel", "com.apple.proapps.cameraName"])
        #expect(metadata.items.suffix(3).map(\.value) == ["Multi Screen Recorder 1", "Screen 2 - LG HDR 4K", "Screen 2 - LG HDR 4K"])
        #expect(metadata.items.first { $0.key.hasSuffix(".frameSize") }?.value == "1920x1080")
    }
}
