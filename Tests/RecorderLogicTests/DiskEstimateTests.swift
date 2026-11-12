import Testing
@testable import RecorderLogic

@Suite struct DiskEstimateTests {
    private let fullHD = FrameSize(width: 1920, height: 1080)

    @Test func oneGigabytePerDisplayPerHourAt1080p() {
        #expect(DiskEstimate.bytesNeeded(frameSizes: [fullHD], hours: 1) == 1_000_000_000)
        #expect(DiskEstimate.bytesNeeded(frameSizes: [fullHD, fullHD], hours: 2) == 4_000_000_000)
    }

    @Test func scalesByThePixelCount() {
        #expect(DiskEstimate.bytesNeeded(frameSizes: [FrameSize(width: 3840, height: 2160)], hours: 1) == 4_000_000_000)
        #expect(DiskEstimate.bytesNeeded(frameSizes: [FrameSize(width: 960, height: 540)], hours: 2) == 500_000_000)
    }

    @Test func noDisplaysNeedNoSpace() {
        #expect(DiskEstimate.bytesNeeded(frameSizes: [], hours: 2) == 0)
    }

    @Test(arguments: [
        (3_100_000_000.0, "3.1 GB"),
        (4_000_000_000.0, "4.0 GB"),
        (3_739_500_000.0, "3.7 GB"),
        (512_000_000_000.0, "512.0 GB"),
        (0.0, "0.0 GB"),
    ])
    func gigabytesAreDecimalWithOneDigit(bytes: Double, text: String) {
        #expect(DiskEstimate.gigabytes(bytes) == text)
    }
}
