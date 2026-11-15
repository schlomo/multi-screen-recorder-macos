import Testing
@testable import RecorderLogic

@Suite struct DisplayTrackerTests {
    private let second: Int64 = 1_000_000_000

    private static let builtIn = ConnectedDisplay(
        uuid: "37D8832A", displayID: 1, name: "Built-in Retina Display", pointSize: FrameSize(width: 1728, height: 1117),
        bounds: ScreenRect(x: 0, y: 0, width: 1728, height: 1117), isMain: true)
    private static let lg = ConnectedDisplay(
        uuid: "1E6E43E3", displayID: 2, name: "LG HDR 4K", pointSize: FrameSize(width: 3840, height: 2160),
        bounds: ScreenRect(x: 1728, y: 0, width: 3840, height: 2160), isMain: false)
    private static let left = ConnectedDisplay(
        uuid: "AAAA", displayID: 3, name: "Left", pointSize: FrameSize(width: 1920, height: 1080),
        bounds: ScreenRect(x: -1920, y: 0, width: 1920, height: 1080), isMain: false)

    private func tracker(_ resolution: RecordingResolution = .native) -> DisplayTracker {
        DisplayTracker(resolution: resolution)
    }

    private func starts(_ step: DisplayTracker.Step) -> [String] {
        step.actions.compactMap { if case .start(let uuid, _, _, _, _) = $0 { uuid } else { nil } }
    }

    private func numbers(_ step: DisplayTracker.Step) -> [Int] {
        step.actions.compactMap { if case .start(_, _, _, let number, _) = $0 { number } else { nil } }
    }

    @Test func atTheStartTheMainDisplayIsOneAndTheOthersGoLeftToRight() {
        var displays = tracker()
        let step = displays.begin([Self.lg, Self.left, Self.builtIn], at: 0)
        #expect(starts(step) == [Self.builtIn.uuid, Self.left.uuid, Self.lg.uuid])
        #expect(numbers(step) == [1, 2, 3])
        #expect(step.events.isEmpty)
    }

    @Test func aDisplayThatGoesEndsItsFileAtOnceAndComesBackAfterTheSettleTimeWithItsNumberAndName() {
        var displays = tracker()
        _ = displays.begin([Self.builtIn, Self.lg], at: 0)
        let gone = displays.observe([Self.builtIn], at: 10 * second)
        #expect(gone.actions == [.stop(uuid: Self.lg.uuid, ending: .disconnected)])
        #expect(gone.events == [RecordingEvent(at: 10 * second, event: .displayDisconnected, display: "LG HDR 4K")])

        var back = Self.lg
        back.displayID = 7
        back.name = "LG HDR 4K (1)"
        let returned = displays.observe([Self.builtIn, back], at: 20 * second)
        #expect(returned.actions.isEmpty)
        #expect(returned.events == [RecordingEvent(at: 20 * second, event: .displayConnected, display: "LG HDR 4K")])
        #expect(displays.due(at: 20 * second + second / 2).actions.isEmpty)
        #expect(displays.nextDueTime() == 21 * second)
        let started = displays.due(at: 21 * second)
        #expect(started.actions == [.start(uuid: Self.lg.uuid, displayID: 7, frameSize: FrameSize(width: 3840, height: 2160),
                                           number: 2, name: "LG HDR 4K")])
    }

    @Test func aNewDisplayGetsTheNextNumberAndAnEvent() {
        var displays = tracker()
        _ = displays.begin([Self.builtIn], at: 0)
        let step = displays.observe([Self.builtIn, Self.lg], at: 5 * second)
        #expect(step.events.map(\.event) == [.displayConnected])
        #expect(numbers(displays.due(at: 6 * second)) == [2])
    }

    @Test func quickModeSwitchesMakeNoBurstOfFiles() {
        var displays = tracker()
        _ = displays.begin([Self.builtIn], at: 0)
        var changed = Self.builtIn
        for step in 0..<5 {
            changed.pointSize = FrameSize(width: 1500 + step * 10, height: 1000)
            _ = displays.observe([changed], at: Int64(step) * second / 2)
            #expect(displays.due(at: Int64(step) * second / 2 + second / 3).actions.isEmpty)
        }
        let settled = displays.due(at: 2 * second + second)
        #expect(settled.events.map(\.event) == [.displayFrameSizeChanged])
        #expect(settled.actions.count == 2)
    }

    @Test func aNewFrameSizeEndsTheFileAfterTheSettleTimeAndStartsANewOne() {
        var displays = tracker(.p1080)
        _ = displays.begin([Self.builtIn], at: 0)
        var changed = Self.builtIn
        changed.pointSize = FrameSize(width: 1512, height: 982)
        #expect(displays.observe([changed], at: 100 * second).actions.isEmpty)
        let step = displays.due(at: 101 * second)
        var event = RecordingEvent(at: 101 * second, event: .displayFrameSizeChanged, display: "Built-in Retina Display")
        event.from = [1670, 1080]
        event.to = [1512, 982]
        #expect(step.events == [event])
        #expect(step.actions == [
            .stop(uuid: Self.builtIn.uuid, ending: .frameSizeChanged),
            .start(uuid: Self.builtIn.uuid, displayID: 1, frameSize: FrameSize(width: 1512, height: 982), number: 1,
                   name: "Built-in Retina Display"),
        ])
    }

    @Test func anUnchangedFrameSizeContinuesTheFile() {
        // At 1080p, 3840×2160 and 5120×2880 both record at 1920×1080.
        var displays = tracker(.p1080)
        _ = displays.begin([Self.lg], at: 0)
        var changed = Self.lg
        changed.pointSize = FrameSize(width: 5120, height: 2880)
        changed.bounds.width = 5120
        _ = displays.observe([changed], at: second)
        #expect(displays.due(at: 5 * second) == DisplayTracker.Step())
        #expect(displays.nextDueTime() == nil)
    }

    @Test func mirroringEndsTheFileAndItsEndStartsANewOneWithTheSameNumber() {
        var displays = tracker()
        _ = displays.begin([Self.builtIn, Self.lg], at: 0)
        var mirroring = Self.lg
        mirroring.mirrorsUUID = Self.builtIn.uuid
        mirroring.name = nil
        let started = displays.observe([Self.builtIn, mirroring], at: second)
        var event = RecordingEvent(at: second, event: .displayMirroringStarted, display: "LG HDR 4K")
        event.mirrors = "Built-in Retina Display"
        #expect(started.events == [event])
        #expect(started.actions == [.stop(uuid: Self.lg.uuid, ending: .mirroringStarted)])
        #expect(displays.due(at: 10 * second).actions.isEmpty)

        let stopped = displays.observe([Self.builtIn, Self.lg], at: 20 * second)
        #expect(stopped.events.map(\.event) == [.displayMirroringStopped])
        #expect(numbers(displays.due(at: 21 * second)) == [2])
    }

    @Test func aChangeOfTheMainDisplayIsAnEventAndKeepsTheNumbers() {
        var displays = tracker()
        _ = displays.begin([Self.builtIn, Self.lg], at: 0)
        var builtIn = Self.builtIn
        builtIn.isMain = false
        var lg = Self.lg
        lg.isMain = true
        let step = displays.observe([builtIn, lg], at: second)
        #expect(step.events == [RecordingEvent(at: second, event: .mainDisplayChanged, display: "LG HDR 4K")])
        #expect(step.actions.isEmpty)
    }

    @Test func aFailingStreamIsRestartedWithABackOffAsLongAsTheDisplayExists() {
        var displays = tracker()
        _ = displays.begin([Self.builtIn], at: 0)
        var restarts: [Int64] = []
        var now: Int64 = 0
        for _ in 0..<6 {
            let failed = displays.streamEnded(Self.builtIn.uuid, .streamFailed("-3811"), connected: [Self.builtIn], at: now)
            #expect(failed.events.map(\.event) == [.displayStreamFailed])
            #expect(failed.events.first?.error == "-3811")
            let due = displays.nextDueTime()!
            #expect(displays.due(at: due - 1).actions.isEmpty)
            #expect(starts(displays.due(at: due)) == [Self.builtIn.uuid])
            restarts.append((due - now) / second)
            now = due
        }
        #expect(restarts == [1, 2, 4, 8, 10, 10])
        displays.fileStarted(Self.builtIn.uuid)
        _ = displays.streamEnded(Self.builtIn.uuid, .streamFailed("-3811"), connected: [Self.builtIn], at: now)
        #expect(displays.nextDueTime() == now + second)
    }

    @Test func aStreamThatFailsBecauseItsDisplayWentIsADisconnection() {
        var displays = tracker()
        _ = displays.begin([Self.builtIn, Self.lg], at: 0)
        let step = displays.streamEnded(Self.lg.uuid, .streamFailed("-3811"), connected: [Self.builtIn], at: second)
        #expect(step.events.map(\.event) == [.displayDisconnected])
        #expect(step.actions.isEmpty)
        #expect(displays.nextDueTime() == nil)
    }

    @Test func aDisplayShowingAnotherDisplaysPictureIsTriedAgainOnlyAfterItsNextChange() {
        var displays = tracker()
        _ = displays.begin([Self.builtIn, Self.lg], at: 0)
        let step = displays.streamEnded(Self.lg.uuid, .showsAnotherDisplay, connected: [Self.builtIn, Self.lg], at: second)
        #expect(step.events == [RecordingEvent(at: second, event: .displayShowsAnotherDisplaysPicture, display: "LG HDR 4K")])
        #expect(displays.showsAnotherDisplaysPicture)
        #expect(displays.due(at: 100 * second).actions.isEmpty)
        // The other display changing is not this one's change.
        var builtIn = Self.builtIn
        builtIn.bounds.y = 10
        _ = displays.observe([builtIn, Self.lg], at: 101 * second)
        #expect(displays.due(at: 200 * second).actions.isEmpty)
        var moved = Self.lg
        moved.bounds.y = 100
        _ = displays.observe([builtIn, moved], at: 300 * second)
        #expect(starts(displays.due(at: 301 * second)) == [Self.lg.uuid])
        #expect(!displays.showsAnotherDisplaysPicture)
    }

    /// An unplug: the stream ends because its display is gone, seconds
    /// before macOS's notice. No failure and no back-off; the notice brings
    /// `display disconnected` (F4).
    @Test func aStreamWhoseDisplayIsGoneEndsAsADisconnectWithoutAFailure() {
        var displays = tracker()
        _ = displays.begin([Self.builtIn, Self.lg], at: 0)
        let ended = displays.streamEnded(Self.lg.uuid, .captureSourceGone, connected: [Self.builtIn, Self.lg], at: 10 * second)
        #expect(ended.events.isEmpty && ended.actions.isEmpty)
        #expect(displays.due(at: 10 * second + displays.settleTime.nanoseconds / 2).actions.isEmpty)
        let notice = displays.observe([Self.builtIn], at: 18 * second)
        #expect(notice.events.map(\.event) == [.displayDisconnected])
        #expect(notice.actions.isEmpty)
        #expect(displays.due(at: 30 * second).actions.isEmpty)
    }

    /// Still listed one settle time after its stream ended: a new stream, as after any change.
    @Test func aStreamWhoseDisplayIsGoneButStillListedStartsAgainAfterTheSettleTime() {
        var displays = tracker()
        _ = displays.begin([Self.builtIn, Self.lg], at: 0)
        _ = displays.streamEnded(Self.lg.uuid, .captureSourceGone, connected: [Self.builtIn, Self.lg], at: 10 * second)
        let due = displays.due(at: 10 * second + displays.settleTime.nanoseconds)
        #expect(starts(due) == [Self.lg.uuid])
        #expect(due.events.isEmpty)
    }

    @Test func aFailingWriterStartsANewFileAfterTheBackOff() {
        var displays = tracker()
        _ = displays.begin([Self.builtIn], at: 0)
        let step = displays.streamEnded(Self.builtIn.uuid, .writerFailed("cannot write"), connected: [Self.builtIn], at: second)
        // The recorder writes its event, once per capture end (FileEndReport).
        #expect(step.events.isEmpty)
        #expect(displays.nextDueTime() == 2 * second)
    }

    @Test func aWriterThatFellBehindStartsANewFileAsAfterAFailingStream() {
        var displays = tracker()
        _ = displays.begin([Self.builtIn], at: 0)
        let step = displays.streamEnded(Self.builtIn.uuid, .writerFellBehind, connected: [Self.builtIn], at: second)
        #expect(step.events.map(\.event) == [.displayFileWriterFellBehind])
        #expect(displays.nextDueTime() == 2 * second)
    }

    @Test func aFullDiskWaitsForRoom() {
        var displays = tracker()
        _ = displays.begin([Self.builtIn], at: 0)
        let step = displays.streamEnded(Self.builtIn.uuid, .diskFull, connected: [Self.builtIn], at: second)
        // The recorder writes its event, once per capture end (FileEndReport).
        #expect(step.events.isEmpty)
        #expect(displays.isWaitingForRoom)
        #expect(displays.due(at: 60 * second).actions.isEmpty)
        displays.roomAgain()
        #expect(starts(displays.due(at: 61 * second)) == [Self.builtIn.uuid])
    }

    @Test func atSleepEveryFileEndsAndAtWakeTheDisplaysStartAfterTheSettleTime() {
        var displays = tracker()
        _ = displays.begin([Self.builtIn, Self.lg], at: 0)
        let asleep = displays.sleep(at: 10 * second)
        #expect(asleep.events.map(\.event) == [.sleep])
        #expect(asleep.actions.count == 2)
        #expect(displays.due(at: 20 * second).actions.isEmpty)
        let awake = displays.wake([Self.builtIn, Self.lg], at: 3600 * second)
        #expect(awake.events.map(\.event) == [.wake])
        #expect(displays.due(at: 3600 * second).actions.isEmpty)
        #expect(numbers(displays.due(at: 3601 * second)) == [1, 2])
    }

    @Test func aStreamEndAfterItsFileWasStoppedChangesNothing() {
        var displays = tracker()
        _ = displays.begin([Self.builtIn], at: 0)
        _ = displays.stopAll()
        #expect(displays.streamEnded(Self.builtIn.uuid, .streamFailed("x"), connected: [Self.builtIn], at: second)
            == DisplayTracker.Step())
    }
}
