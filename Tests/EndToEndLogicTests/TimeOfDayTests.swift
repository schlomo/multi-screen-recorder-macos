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

    @Test func aFilesTimecodeIsTheStartsFrameRoundedPlusItsTicks() {
        // started 14:03:05.120: frame 3.6 rounds to 4.
        #expect(TimecodeValue(recordingStarted: 50_585.12, fileStart: 0).description == "14:03:05:04")
        #expect(TimecodeValue(recordingStarted: 50_585.12, fileStart: 0.3).description == "14:03:05:13")
        #expect(TimecodeValue(recordingStarted: 50_585.12, fileStart: 2285).description == "14:41:10:04")
        // Seen on this Mac: started 08:00:56.434, a file 29 ticks in.
        #expect(TimecodeValue(recordingStarted: 28_856.434, fileStart: 0.9666666666666667).description == "08:00:57:12")
    }

    @Test func midnightStartsTheDayOver() {
        #expect(TimecodeValue(recordingStarted: 86_399.99, fileStart: 0.1).description == "00:00:00:03")
    }

    @Test func aScreenSizeIsWidthByHeight() {
        #expect(ScreenSize("1280x720") == ScreenSize(width: 1280, height: 720))
        #expect(ScreenSize(width: 1600, height: 900).description == "1600x900")
        #expect(ScreenSize("1280×720") == nil)
        #expect(ScreenSize("0x720") == nil)
    }
}
