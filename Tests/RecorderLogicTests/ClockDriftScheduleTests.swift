import Testing
@testable import RecorderLogic

@Suite struct ClockDriftScheduleTests {
    private let millisecond: Int64 = 1_000_000

    @Test func theStatusComesAtTheFirstBufferThenEverySecond() {
        var schedule = ClockDriftSchedule()
        var status: [Int64] = []
        // A buffer every 30 ms for 25 s, the first at 7 s.
        for index in Int64(0)..<834 {
            let now = 7_000 * millisecond + index * 30 * millisecond
            if schedule.due(at: now) { status.append(now / millisecond - 7_000) }
        }
        #expect(status.prefix(4) == [0, 1_020, 2_040, 3_060])
        #expect(status.count == 25)
    }

    /// The `--debug` block of every audio source's clock drift: at the first check, then every 10 s.
    @Test func theDebugBlockComesEveryTenSecondsFromTheFirstCheck() {
        var schedule = ClockDriftDetailSchedule()
        var blocks: [Int64] = []
        // A check every second for 35 s, the first at 7 s.
        for second in Int64(0)..<35 {
            let now = 7_000 * millisecond + second * 1_000 * millisecond
            if schedule.due(at: now) { blocks.append(second) }
        }
        #expect(blocks == [10, 20, 30])
    }
}
