import Testing
@testable import RecorderLogic

/// A failed file ends where it really ends, and what it lacks is told (D66).
@Suite struct FailedFileEndTests {
    @Test func theEndIsTheStartPlusTheDurationTheFileHolds() {
        let end = FailedFileEnd(start: 1.0, failedAt: 6.933, duration: .seconds(4.667))
        #expect(end.end == 5.667)
        #expect(end.failedAt == 6.933)
        #expect(end.lost == "the file ends at 5.667 s, the writer failed at 6.933 s: 1.266 s of the recording are lost")
    }

    @Test func aFileHoldingEverythingLosesNothing() {
        #expect(FailedFileEnd(start: 1.0, failedAt: 6.0, duration: .seconds(5)).lost == nil)
        #expect(FailedFileEnd(start: 1.0, failedAt: 6.0, duration: .seconds(5.2)).end == 6.2)
    }

    @Test func anUnreadableFileEndsAtItsStartAndSaysSo() {
        let end = FailedFileEnd(start: 1.0, failedAt: 6.933, duration: .unreadable("no moov"))
        #expect(end.end == 1.0)
        #expect(end.lost == "the file cannot be read (no moov), so its end is its start, 1.000 s; everything up to the failure at 6.933 s is lost")
    }
}
