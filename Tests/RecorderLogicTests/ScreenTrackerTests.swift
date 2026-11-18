import Testing
@testable import RecorderLogic

@Suite struct ScreenTrackerTests {
    private let second: Int64 = 1_000_000_000

    private static let builtIn = ConnectedScreen(
        uuid: "37D8832A", displayID: 1, name: "Built-in Retina Display", pointSize: FrameSize(width: 1728, height: 1117),
        bounds: ScreenRect(x: 0, y: 0, width: 1728, height: 1117), isMain: true)
    private static let lg = ConnectedScreen(
        uuid: "1E6E43E3", displayID: 2, name: "LG HDR 4K", pointSize: FrameSize(width: 3840, height: 2160),
        bounds: ScreenRect(x: 1728, y: 0, width: 3840, height: 2160), isMain: false)
    private static let left = ConnectedScreen(
        uuid: "AAAA", displayID: 3, name: "Left", pointSize: FrameSize(width: 1920, height: 1080),
        bounds: ScreenRect(x: -1920, y: 0, width: 1920, height: 1080), isMain: false)

    private func tracker(_ resolution: RecordingResolution = .native) -> ScreenTracker {
        ScreenTracker(resolution: resolution)
    }

    private func starts(_ step: ScreenTracker.Step) -> [String] {
        step.actions.compactMap { if case .start(let uuid, _, _, _, _) = $0 { uuid } else { nil } }
    }

    private func numbers(_ step: ScreenTracker.Step) -> [Int] {
        step.actions.compactMap { if case .start(_, _, _, let number, _) = $0 { number } else { nil } }
    }

    @Test func atTheStartTheMainScreenIsOneAndTheOthersGoLeftToRight() {
        var screens = tracker()
        let step = screens.begin([Self.lg, Self.left, Self.builtIn], at: 0)
        #expect(starts(step) == [Self.builtIn.uuid, Self.left.uuid, Self.lg.uuid])
        #expect(numbers(step) == [1, 2, 3])
        #expect(step.events.isEmpty)
    }

    @Test func aScreenThatGoesEndsItsFileAtOnceAndComesBackAfterTheSettleTimeWithItsNumberAndName() {
        var screens = tracker()
        _ = screens.begin([Self.builtIn, Self.lg], at: 0)
        let gone = screens.observe([Self.builtIn], at: 10 * second)
        #expect(gone.actions == [.stop(uuid: Self.lg.uuid, ending: .disconnected)])
        #expect(gone.events == [RecordingEvent(at: 10 * second, event: .screenDisconnected, screen: "LG HDR 4K")])

        var back = Self.lg
        back.displayID = 7
        back.name = "LG HDR 4K (1)"
        let returned = screens.observe([Self.builtIn, back], at: 20 * second)
        #expect(returned.actions.isEmpty)
        #expect(returned.events == [RecordingEvent(at: 20 * second, event: .screenConnected, screen: "LG HDR 4K")])
        #expect(screens.due(at: 20 * second + second / 2).actions.isEmpty)
        #expect(screens.nextDueTime() == 21 * second)
        let started = screens.due(at: 21 * second)
        #expect(started.actions == [.start(uuid: Self.lg.uuid, displayID: 7, frameSize: FrameSize(width: 3840, height: 2160),
                                           number: 2, name: "LG HDR 4K")])
    }

    @Test func aNewScreenGetsTheNextNumberAndAnEvent() {
        var screens = tracker()
        _ = screens.begin([Self.builtIn], at: 0)
        let step = screens.observe([Self.builtIn, Self.lg], at: 5 * second)
        #expect(step.events.map(\.event) == [.screenConnected])
        #expect(numbers(screens.due(at: 6 * second)) == [2])
    }

    @Test func quickModeSwitchesMakeNoBurstOfFiles() {
        var screens = tracker()
        _ = screens.begin([Self.builtIn], at: 0)
        var changed = Self.builtIn
        for step in 0..<5 {
            changed.pointSize = FrameSize(width: 1500 + step * 10, height: 1000)
            _ = screens.observe([changed], at: Int64(step) * second / 2)
            #expect(screens.due(at: Int64(step) * second / 2 + second / 3).actions.isEmpty)
        }
        let settled = screens.due(at: 2 * second + second)
        #expect(settled.events.map(\.event) == [.screenFrameSizeChanged])
        #expect(settled.actions.count == 2)
    }

    @Test func aNewFrameSizeEndsTheFileAfterTheSettleTimeAndStartsANewOne() {
        var screens = tracker(.p1080)
        _ = screens.begin([Self.builtIn], at: 0)
        var changed = Self.builtIn
        changed.pointSize = FrameSize(width: 1512, height: 982)
        #expect(screens.observe([changed], at: 100 * second).actions.isEmpty)
        let step = screens.due(at: 101 * second)
        var event = RecordingEvent(at: 101 * second, event: .screenFrameSizeChanged, screen: "Built-in Retina Display")
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
        var screens = tracker(.p1080)
        _ = screens.begin([Self.lg], at: 0)
        var changed = Self.lg
        changed.pointSize = FrameSize(width: 5120, height: 2880)
        changed.bounds.width = 5120
        _ = screens.observe([changed], at: second)
        #expect(screens.due(at: 5 * second) == ScreenTracker.Step())
        #expect(screens.nextDueTime() == nil)
    }

    @Test func mirroringEndsTheFileAndItsEndStartsANewOneWithTheSameNumber() {
        var screens = tracker()
        _ = screens.begin([Self.builtIn, Self.lg], at: 0)
        var mirroring = Self.lg
        mirroring.mirrorsUUID = Self.builtIn.uuid
        mirroring.name = nil
        let started = screens.observe([Self.builtIn, mirroring], at: second)
        var event = RecordingEvent(at: second, event: .screenMirroringStarted, screen: "LG HDR 4K")
        event.mirrors = "Built-in Retina Display"
        #expect(started.events == [event])
        #expect(started.actions == [.stop(uuid: Self.lg.uuid, ending: .mirroringStarted)])
        #expect(screens.due(at: 10 * second).actions.isEmpty)

        let stopped = screens.observe([Self.builtIn, Self.lg], at: 20 * second)
        #expect(stopped.events.map(\.event) == [.screenMirroringStopped])
        #expect(numbers(screens.due(at: 21 * second)) == [2])
    }

    @Test func aChangeOfTheMainScreenIsAnEventAndKeepsTheNumbers() {
        var screens = tracker()
        _ = screens.begin([Self.builtIn, Self.lg], at: 0)
        var builtIn = Self.builtIn
        builtIn.isMain = false
        var lg = Self.lg
        lg.isMain = true
        let step = screens.observe([builtIn, lg], at: second)
        #expect(step.events == [RecordingEvent(at: second, event: .mainScreenChanged, screen: "LG HDR 4K")])
        #expect(step.actions.isEmpty)
    }

    @Test func aFailingStreamIsRestartedWithABackOffAsLongAsTheScreenExists() {
        var screens = tracker()
        _ = screens.begin([Self.builtIn], at: 0)
        var restarts: [Int64] = []
        var now: Int64 = 0
        for _ in 0..<6 {
            let failed = screens.streamEnded(Self.builtIn.uuid, .streamFailed("-3811"), connected: [Self.builtIn], at: now)
            #expect(failed.events.map(\.event) == [.screenStreamFailed])
            #expect(failed.events.first?.error == "-3811")
            let due = screens.nextDueTime()!
            #expect(screens.due(at: due - 1).actions.isEmpty)
            #expect(starts(screens.due(at: due)) == [Self.builtIn.uuid])
            restarts.append((due - now) / second)
            now = due
        }
        #expect(restarts == [1, 2, 4, 8, 10, 10])
        screens.fileStarted(Self.builtIn.uuid)
        _ = screens.streamEnded(Self.builtIn.uuid, .streamFailed("-3811"), connected: [Self.builtIn], at: now)
        #expect(screens.nextDueTime() == now + second)
    }

    @Test func aStreamThatFailsBecauseItsScreenWentIsADisconnection() {
        var screens = tracker()
        _ = screens.begin([Self.builtIn, Self.lg], at: 0)
        let step = screens.streamEnded(Self.lg.uuid, .streamFailed("-3811"), connected: [Self.builtIn], at: second)
        #expect(step.events.map(\.event) == [.screenDisconnected])
        #expect(step.actions.isEmpty)
        #expect(screens.nextDueTime() == nil)
    }

    @Test func aScreenShowingAnotherScreensPictureIsTriedAgainOnlyAfterItsNextChange() {
        var screens = tracker()
        _ = screens.begin([Self.builtIn, Self.lg], at: 0)
        let step = screens.streamEnded(Self.lg.uuid, .showsAnotherScreen, connected: [Self.builtIn, Self.lg], at: second)
        #expect(step.events == [RecordingEvent(at: second, event: .screenShowsAnotherScreensPicture, screen: "LG HDR 4K")])
        #expect(screens.showsAnotherScreensPicture)
        #expect(screens.due(at: 100 * second).actions.isEmpty)
        // The other screen changing is not this one's change.
        var builtIn = Self.builtIn
        builtIn.bounds.y = 10
        _ = screens.observe([builtIn, Self.lg], at: 101 * second)
        #expect(screens.due(at: 200 * second).actions.isEmpty)
        var moved = Self.lg
        moved.bounds.y = 100
        _ = screens.observe([builtIn, moved], at: 300 * second)
        #expect(starts(screens.due(at: 301 * second)) == [Self.lg.uuid])
        #expect(!screens.showsAnotherScreensPicture)
    }

    /// An unplug: the stream ends because its screen is gone, seconds
    /// before macOS's notice. No failure and no back-off; the notice brings
    /// `screen disconnected` (F4).
    @Test func aStreamWhoseScreenIsGoneEndsAsADisconnectWithoutAFailure() {
        var screens = tracker()
        _ = screens.begin([Self.builtIn, Self.lg], at: 0)
        let ended = screens.streamEnded(Self.lg.uuid, .captureSourceGone, connected: [Self.builtIn, Self.lg], at: 10 * second)
        #expect(ended.events.isEmpty && ended.actions.isEmpty)
        #expect(screens.due(at: 10 * second + screens.settleTime.nanoseconds / 2).actions.isEmpty)
        let notice = screens.observe([Self.builtIn], at: 18 * second)
        #expect(notice.events.map(\.event) == [.screenDisconnected])
        #expect(notice.actions.isEmpty)
        #expect(screens.due(at: 30 * second).actions.isEmpty)
    }

    /// N-A: only the first such end is free. Again without a screen-change
    /// notice for the screen in between, it is a failure with back-off.
    @Test func aSecondCaptureSourceGoneWithoutANoticeIsAFailure() {
        var screens = tracker()
        _ = screens.begin([Self.builtIn, Self.lg], at: 0)
        _ = screens.streamEnded(Self.lg.uuid, .captureSourceGone, connected: [Self.builtIn, Self.lg], at: 10 * second)
        let restarted = screens.due(at: 10 * second + screens.settleTime.nanoseconds)
        #expect(starts(restarted) == [Self.lg.uuid])
        let again = screens.streamEnded(Self.lg.uuid, .captureSourceGone, connected: [Self.builtIn, Self.lg], at: 20 * second)
        #expect(again.events.map(\.event) == [.screenStreamFailed])
        #expect(again.events.first?.error?.contains("-3815") == true)
        #expect(screens.nextDueTime() == 21 * second)
    }

    /// A notice for the screen in between makes the next such end free again.
    @Test func aCaptureSourceGoneAfterANoticeIsFreeAgain() {
        var screens = tracker()
        _ = screens.begin([Self.builtIn, Self.lg], at: 0)
        _ = screens.streamEnded(Self.lg.uuid, .captureSourceGone, connected: [Self.builtIn, Self.lg], at: 10 * second)
        _ = screens.observe([Self.builtIn], at: 12 * second)
        _ = screens.observe([Self.builtIn, Self.lg], at: 30 * second)
        #expect(starts(screens.due(at: 30 * second + screens.settleTime.nanoseconds)) == [Self.lg.uuid])
        let again = screens.streamEnded(Self.lg.uuid, .captureSourceGone, connected: [Self.builtIn, Self.lg], at: 40 * second)
        #expect(again.events.isEmpty && again.actions.isEmpty)
    }

    /// Still listed one settle time after its stream ended: a new stream, as after any change.
    @Test func aStreamWhoseScreenIsGoneButStillListedStartsAgainAfterTheSettleTime() {
        var screens = tracker()
        _ = screens.begin([Self.builtIn, Self.lg], at: 0)
        _ = screens.streamEnded(Self.lg.uuid, .captureSourceGone, connected: [Self.builtIn, Self.lg], at: 10 * second)
        let due = screens.due(at: 10 * second + screens.settleTime.nanoseconds)
        #expect(starts(due) == [Self.lg.uuid])
        #expect(due.events.isEmpty)
    }

    @Test func aFailingWriterStartsANewFileAfterTheBackOff() {
        var screens = tracker()
        _ = screens.begin([Self.builtIn], at: 0)
        let step = screens.streamEnded(Self.builtIn.uuid, .writerFailed("cannot write"), connected: [Self.builtIn], at: second)
        // The recorder writes its event, once per capture end (FileEndReport).
        #expect(step.events.isEmpty)
        #expect(screens.nextDueTime() == 2 * second)
    }

    @Test func aWriterThatFellBehindStartsANewFileAsAfterAFailingStream() {
        var screens = tracker()
        _ = screens.begin([Self.builtIn], at: 0)
        let step = screens.streamEnded(Self.builtIn.uuid, .writerFellBehind, connected: [Self.builtIn], at: second)
        #expect(step.events.map(\.event) == [.screenFileWriterFellBehind])
        #expect(screens.nextDueTime() == 2 * second)
    }

    @Test func aFullDiskWaitsForRoom() {
        var screens = tracker()
        _ = screens.begin([Self.builtIn], at: 0)
        let step = screens.streamEnded(Self.builtIn.uuid, .diskFull, connected: [Self.builtIn], at: second)
        // The recorder writes its event, once per capture end (FileEndReport).
        #expect(step.events.isEmpty)
        #expect(screens.isWaitingForRoom)
        #expect(screens.due(at: 60 * second).actions.isEmpty)
        screens.roomAgain()
        #expect(starts(screens.due(at: 61 * second)) == [Self.builtIn.uuid])
    }

    @Test func atSleepEveryFileEndsAndAtWakeTheScreensStartAfterTheSettleTime() {
        var screens = tracker()
        _ = screens.begin([Self.builtIn, Self.lg], at: 0)
        let asleep = screens.sleep(at: 10 * second)
        #expect(asleep.events.map(\.event) == [.sleep])
        #expect(asleep.actions.count == 2)
        #expect(screens.due(at: 20 * second).actions.isEmpty)
        let awake = screens.wake([Self.builtIn, Self.lg], at: 3600 * second)
        #expect(awake.events.map(\.event) == [.wake])
        #expect(screens.due(at: 3600 * second).actions.isEmpty)
        #expect(numbers(screens.due(at: 3601 * second)) == [1, 2])
    }

    @Test func aStreamEndAfterItsFileWasStoppedChangesNothing() {
        var screens = tracker()
        _ = screens.begin([Self.builtIn], at: 0)
        _ = screens.stopAll()
        #expect(screens.streamEnded(Self.builtIn.uuid, .streamFailed("x"), connected: [Self.builtIn], at: second)
            == ScreenTracker.Step())
    }

    /// Audio only: at the resolution None no screen gets a stream, a number,
    /// an event or a row, whatever the screens do; sleep and wake are still told.
    @Test func atTheResolutionNoneNoScreenIsRecordedOrTold() {
        var screens = tracker(.none)
        let begun = screens.begin([Self.builtIn, Self.lg], at: 0)
        #expect(begun == ScreenTracker.Step())
        #expect(screens.observe([Self.builtIn, Self.lg, Self.left], at: second) == ScreenTracker.Step())
        #expect(screens.observe([Self.lg], at: 2 * second) == ScreenTracker.Step())
        #expect(screens.due(at: 60 * second) == ScreenTracker.Step())
        #expect(screens.nextDueTime() == nil)
        #expect(screens.sleep(at: 70 * second).events.map(\.event) == [.sleep])
        #expect(screens.wake([Self.builtIn], at: 80 * second).events.map(\.event) == [.wake])
        #expect(screens.due(at: 90 * second) == ScreenTracker.Step())
        #expect(screens.sources.isEmpty)
        #expect(screens.stopAll().isEmpty)
    }
}
