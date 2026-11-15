import Testing
@testable import RecorderLogic

@Suite struct DisplayFileMetadataTests {
    private let metadata = DisplayFileMetadata(
        displayUUID: "U", displayNumber: 2, displayName: "LG HDR 4K", frameSize: FrameSize(width: 1920, height: 1080),
        recordingStarted: "2026-11-12T14:03:05.120+01:00", app: "Multi Screen Recorder 1")

    @Test func theReelNameIsTheSourceAsInTheFileName() {
        #expect(metadata.reelName == "Display 2 - LG HDR 4K")
        #expect(RecordingNames.displayFile(start: .now, timeZone: .current, number: 2, display: "LG HDR 4K").contains(metadata.reelName))
    }

    @Test func everyItemIsUnderTheAppsKeysAndTheAppAlsoAsSoftware() {
        let keys = metadata.items.map(\.key)
        #expect(keys.dropLast().allSatisfy { $0.hasPrefix("org.schapiro.multiscreenrecorder.") })
        #expect(metadata.items.last! == ("com.apple.quicktime.software", "Multi Screen Recorder 1"))
        #expect(metadata.items.first { $0.key.hasSuffix(".frameSize") }?.value == "1920x1080")
    }
}
