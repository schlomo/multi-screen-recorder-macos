import Foundation
import Testing
@testable import EndToEndLogic

@Suite struct SystemLogTests {
    @Test func theArgumentsAskForTheVideoAndMediaSubsystemsSinceTheStart() throws {
        let berlin = try #require(TimeZone(identifier: "Europe/Berlin"))
        let start = Date(timeIntervalSince1970: 1_795_000_000.4)
        let arguments = SystemLog.arguments(since: start, timeZone: berlin)
        #expect(arguments.prefix(5) == ["show", "--style", "compact", "--start", SystemLog.start(start, timeZone: berlin)])
        #expect(arguments[4].wholeMatch(of: /\d{4}-\d\d-\d\d \d\d:\d\d:\d\d/) != nil)
        #expect(arguments[5] == "--predicate")
        for name in ["videotoolbox", "coremedia", "avfoundation", "screencapturekit", "display"] {
            #expect(arguments[6].contains("subsystem CONTAINS[c] \"\(name)\""))
        }
        #expect(arguments[6].contains("process == \"WindowServer\""))
    }

    @Test func theStartIsASecondEarlyInTheGivenTimeZone() throws {
        let utc = try #require(TimeZone(identifier: "UTC"))
        #expect(SystemLog.start(Date(timeIntervalSince1970: 3600), timeZone: utc) == "1970-01-01 00:59:59")
    }
}
