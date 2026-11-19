import Foundation
import Testing
@testable import EndToEndLogic

@Suite struct TimeOfDayTests {
    @Test func aTimestampIsReadAsTheLocalTimeOfDayItShows() {
        #expect(TimeOfDay.seconds(ofTimestamp: "2026-11-12T14:03:05.120+01:00") == 50_585.12)
        #expect(TimeOfDay.seconds(ofTimestamp: "2026-03-29T03:00:00.000+02:00") == 10_800)
        #expect(TimeOfDay.seconds(ofTimestamp: "2026-11-12T14:03:05+01:00") == nil)
        #expect(TimeOfDay.seconds(ofTimestamp: "2026-11-12T24:03:05.120+01:00") == nil)
        #expect(TimeOfDay.seconds(ofTimestamp: "14:03:05.120") == nil)
    }

    @Test func aFileNameStartsWithItsLocalTime() throws {
        let (seconds, rest) = try #require(TimeOfDay.fileNameStamp("2026-11-12 14.03.05 Screen 1 - Built-in Retina Display.mov"))
        #expect(seconds == 50_585)
        #expect(rest == "Screen 1 - Built-in Retina Display.mov")
        #expect(TimeOfDay.fileNameStamp("recording.json") == nil)
        #expect(TimeOfDay.fileNameStamp("2026-11-12 14:03:05 Screen 1.mov") == nil)
    }

    @Test func differencesAreTakenAcrossMidnight() {
        #expect(TimeOfDay.difference(10, 5) == 5)
        #expect(TimeOfDay.difference(1, 86_399) == 2)
        #expect(TimeOfDay.difference(86_399, 1) == -2)
    }

    @Test func aTimecodeIsReadAndWrittenAtThirtyFrames() throws {
        let timecode = try #require(TimecodeValue("14:03:05:04"))
        #expect(timecode.frame == 50_585 * 30 + 4)
        #expect(timecode.description == "14:03:05:04")
        #expect(timecode.seconds == 50_585 + 4.0 / 30)
        #expect(TimecodeValue("14:03:05:30") == nil)
        #expect(TimecodeValue("14:03:05") == nil)
    }

    private func timecodes(_ started: Double, _ start: Double) -> [String] {
        TimecodeValue.possible(recordingStarted: started, fileStart: start).map(\.description)
    }

    @Test func aFilesTimecodeIsTheStartsFrameRoundedPlusItsTicks() {
        // started 14:03:05.120: frame 3.6 rounds to 4, far from a half frame, so only that one.
        #expect(timecodes(50_585.12, 0) == ["14:03:05:04"])
        #expect(timecodes(50_585.12, 0.3) == ["14:03:05:13"])
        #expect(timecodes(50_585.12, 2285) == ["14:41:10:04"])
        // Seen on this Mac: started 08:00:56.434, a file 29 ticks in.
        #expect(timecodes(28_856.434, 0.9666666666666667) == ["08:00:57:12"])
    }

    @Test func aStartedNearAHalfFrameAllowsBothFrames() {
        // started 14:03:05.017: frame 0.51; the recorder rounds the start
        // before the millisecond was cut off, which may have been below 0.5.
        #expect(timecodes(50_585.017, 0) == ["14:03:05:00", "14:03:05:01"])
        #expect(timecodes(50_585.017, 0.1) == ["14:03:05:03", "14:03:05:04"])
        // 0.48 and 0.54 of a frame are 0.7 ms and 1.3 ms from the half frame: exact again.
        #expect(timecodes(50_585.016, 0) == ["14:03:05:00"])
        #expect(timecodes(50_585.018, 0) == ["14:03:05:01"])
    }

    @Test func midnightStartsTheDayOver() {
        #expect(timecodes(86_399.99, 0.1) == ["00:00:00:03"])
    }

    @Test func aScreenSizeIsWidthByHeight() {
        #expect(ScreenSize("1280x720") == ScreenSize(width: 1280, height: 720))
        #expect(ScreenSize(width: 1600, height: 900).description == "1600x900")
        #expect(ScreenSize("1280×720") == nil)
        #expect(ScreenSize("0x720") == nil)
    }
}
