import Testing
@testable import RecorderLogic

@Suite struct ClockDriftScheduleTests {
    @Test func theStatusComesAtTheFirstBufferThenEverySecondTheDebugLineEveryTenSeconds() {
        var schedule = ClockDriftSchedule()
        let millisecond: Int64 = 1_000_000
        var status: [Int64] = []
        var debugLines: [Int64] = []
        // A buffer every 30 ms for 25 s, the first at 7 s.
        for index in Int64(0)..<834 {
            let now = 7_000 * millisecond + index * 30 * millisecond
            let due = schedule.due(at: now)
            if due.status { status.append(now / millisecond - 7_000) }
            if due.debugLine { debugLines.append(now / millisecond - 7_000) }
            #expect(!due.debugLine || due.status)
        }
        #expect(status.prefix(4) == [0, 1_020, 2_040, 3_060])
        #expect(status.count == 25)
        #expect(debugLines == [10_200, 20_400])
    }
}
