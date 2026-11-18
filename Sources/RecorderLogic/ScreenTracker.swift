import Foundation

/// Decides, for every screen a recording has seen, when its stream starts
/// and when its screen file ends, and which events go into the recording
/// manifest (recorder.md, "Screens coming and going", "Frame size",
/// "Screen check"). It holds no stream and no file: the recorder carries
/// out its actions and reports back what happened. Times are nanoseconds
/// from t0 on the shared clock. At the resolution None it follows no
/// screen: audio only.
public struct ScreenTracker: Sendable {
    /// Why a screen file ends.
    public enum Ending: Equatable, Sendable {
        case disconnected
        case frameSizeChanged
        case mirroringStarted
        case sleep
        case stop
    }

    /// What the recorder does for a screen.
    public enum Action: Equatable, Sendable {
        /// Start a stream on the screen and a screen file once its first frame passes the screen check.
        case start(uuid: String, displayID: UInt32, frameSize: FrameSize, number: Int, name: String)
        /// End the screen's stream and finalize its screen file.
        case stop(uuid: String, ending: Ending)
    }

    /// Why a stream ended by itself; the recorder reports it.
    public enum StreamEnd: Equatable, Sendable {
        case streamFailed(String)
        /// The screen the stream captured is gone, as on an unplug, often
        /// seconds before macOS's screen-change notice: no failure (F4).
        case captureSourceGone
        case writerFailed(String)
        case writerFellBehind
        case diskFull
        case showsAnotherScreen
    }

    public struct Step: Equatable, Sendable {
        public var events: [RecordingEvent] = []
        public var actions: [Action] = []

        public init(events: [RecordingEvent] = [], actions: [Action] = []) {
            self.events = events
            self.actions = actions
        }

        mutating func append(_ other: Step) {
            events += other.events
            actions += other.actions
        }
    }

    private enum Phase: Equatable {
        /// Waits for the settle time, then starts.
        case idle
        case recording(frameSize: FrameSize)
        case waitingToRestart(notBefore: Int64)
        /// Tried again only after the screen's next change.
        case showsAnotherScreen(since: Int64)
        case waitingForRoom
    }

    private struct Tracked {
        var number: Int?
        var name: String?
        var phase: Phase = .idle
        /// As last read; nil while the screen is gone.
        var reading: ConnectedScreen?
        /// When it last appeared, went or changed.
        var changedAt: Int64
        var restartDelay: Duration
        /// Whether its stream may end once with the capture source gone
        /// without a failure: until it does, and again after each
        /// screen-change notice for it (N-A).
        var mayLoseCaptureSource = true
    }

    public let resolution: RecordingResolution
    public let settleTime: Duration
    public let firstRestartDelay: Duration
    public let longestRestartDelay: Duration

    private var screens: [String: Tracked] = [:]
    private var nextNumber = 1
    private var mainUUID: String?
    private var isAsleep = false
    /// The newest change of any screen: the screen check does not count
    /// failing frames within the settle time after it.
    public private(set) var lastScreenChange: Int64?

    public init(
        resolution: RecordingResolution,
        settleTime: Duration = RecorderValues.settleTime,
        firstRestartDelay: Duration = RecorderValues.firstRestartDelay,
        longestRestartDelay: Duration = RecorderValues.longestRestartDelay
    ) {
        self.resolution = resolution
        self.settleTime = settleTime
        self.firstRestartDelay = firstRestartDelay
        self.longestRestartDelay = longestRestartDelay
    }

    /// The screens connected at the start: each gets its stream at once.
    /// Screen 1 is the main screen, the others are numbered left to right.
    public mutating func begin(_ connected: [ConnectedScreen], at now: Int64) -> Step {
        let connected = followed(connected)
        for screen in connected {
            screens[screen.uuid] = Tracked(
                name: screen.name, reading: screen, changedAt: Int64.min / 2, restartDelay: firstRestartDelay)
        }
        mainUUID = connected.first(where: \.isMain)?.uuid
        var step = Step()
        for screen in Self.leftToRight(connected.filter { !$0.isMirroring }) {
            step.actions.append(start(screen.uuid, at: now))
        }
        return step
    }

    /// The screen file of `uuid` started: its restart delay starts over.
    public mutating func fileStarted(_ uuid: String) {
        screens[uuid]?.restartDelay = firstRestartDelay
    }

    /// The screens as read after macOS reported a change. A screen that
    /// went or started mirroring ends its file at once; one that came, came
    /// back or changed starts after the settle time (`due(at:)`).
    public mutating func observe(_ connected: [ConnectedScreen], at now: Int64) -> Step {
        let connected = followed(connected)
        var step = Step()
        let byUUID = Dictionary(connected.map { ($0.uuid, $0) }, uniquingKeysWith: { first, _ in first })
        for (uuid, tracked) in screens.sorted(by: { $0.key < $1.key }) where tracked.reading != nil && byUUID[uuid] == nil {
            screens[uuid]?.reading = nil
            screens[uuid]?.changedAt = now
            screens[uuid]?.mayLoseCaptureSource = true
            lastScreenChange = now
            if !(tracked.reading?.isMirroring ?? false) {
                step.events.append(event(.screenDisconnected, uuid, at: now))
            }
            if case .recording = tracked.phase { step.actions.append(.stop(uuid: uuid, ending: .disconnected)) }
            if tracked.phase != .waitingForRoom { screens[uuid]?.phase = .idle }
        }
        for screen in Self.leftToRight(connected) {
            guard var tracked = screens[screen.uuid] else {
                screens[screen.uuid] = Tracked(
                    name: screen.name, reading: screen, changedAt: now, restartDelay: firstRestartDelay)
                lastScreenChange = now
                if !screen.isMirroring { step.events.append(event(.screenConnected, screen.uuid, at: now)) }
                continue
            }
            let previous = tracked.reading
            guard previous != screen else { continue }
            tracked.reading = screen
            tracked.changedAt = now
            tracked.mayLoseCaptureSource = true
            if tracked.name == nil { tracked.name = screen.name }
            screens[screen.uuid] = tracked
            lastScreenChange = now
            if previous == nil {
                if !screen.isMirroring { step.events.append(event(.screenConnected, screen.uuid, at: now)) }
            } else if let previous, !previous.isMirroring, screen.isMirroring {
                var started = event(.screenMirroringStarted, screen.uuid, at: now)
                started.mirrors = screen.mirrorsUUID.flatMap { name(of: $0) }
                step.events.append(started)
                if case .recording = tracked.phase {
                    step.actions.append(.stop(uuid: screen.uuid, ending: .mirroringStarted))
                    screens[screen.uuid]?.phase = .idle
                }
            } else if let previous, previous.isMirroring, !screen.isMirroring {
                step.events.append(event(.screenMirroringStopped, screen.uuid, at: now))
            }
        }
        let newMain = connected.first(where: \.isMain)?.uuid
        if let newMain, newMain != mainUUID {
            if mainUUID != nil { step.events.append(event(.mainScreenChanged, newMain, at: now)) }
            mainUUID = newMain
        }
        return step
    }

    /// What is due at `now`: screens unchanged for the settle time start,
    /// and one whose frame size changed ends its file and starts a new one.
    public mutating func due(at now: Int64) -> Step {
        guard !isAsleep else { return Step() }
        var step = Step()
        let settled = screens.filter { _, tracked in
            guard let reading = tracked.reading, !reading.isMirroring else { return false }
            return now - tracked.changedAt >= settleTime.nanoseconds
        }
        let ordered = Self.leftToRight(settled.values.compactMap(\.reading))
        for screen in ordered {
            guard let tracked = screens[screen.uuid] else { continue }
            let frameSize = resolution.frameSize(forLooksLike: screen.pointSize)
            switch tracked.phase {
            case .recording(let current) where current != frameSize:
                var changed = event(.screenFrameSizeChanged, screen.uuid, at: now)
                changed.from = [current.width, current.height]
                changed.to = [frameSize.width, frameSize.height]
                step.events.append(changed)
                step.actions.append(.stop(uuid: screen.uuid, ending: .frameSizeChanged))
                step.actions.append(start(screen.uuid, at: now))
            case .recording, .waitingForRoom:
                break
            case .idle:
                step.actions.append(start(screen.uuid, at: now))
            case .waitingToRestart(let notBefore) where notBefore <= now:
                step.actions.append(start(screen.uuid, at: now))
            case .waitingToRestart:
                break
            case .showsAnotherScreen(let since) where tracked.changedAt > since:
                step.actions.append(start(screen.uuid, at: now))
            case .showsAnotherScreen:
                break
            }
        }
        return step
    }

    /// The next time `due(at:)` may have something to do, if any.
    public func nextDueTime() -> Int64? {
        guard !isAsleep else { return nil }
        return screens.values.compactMap { tracked -> Int64? in
            guard let reading = tracked.reading, !reading.isMirroring else { return nil }
            let settled = tracked.changedAt + settleTime.nanoseconds
            switch tracked.phase {
            case .idle: return settled
            case .recording(let current):
                return resolution.frameSize(forLooksLike: reading.pointSize) == current ? nil : settled
            case .waitingToRestart(let notBefore): return max(settled, notBefore)
            case .showsAnotherScreen(let since): return tracked.changedAt > since ? settled : nil
            case .waitingForRoom: return nil
            }
        }.min()
    }

    /// A stream ended by itself; `connected` is the screens as read now.
    /// A failing writer and a full disk have their event from the recorder,
    /// once per capture end, also when the tracker no longer follows it.
    public mutating func streamEnded(_ uuid: String, _ end: StreamEnd, connected: [ConnectedScreen], at now: Int64) -> Step {
        guard let tracked = screens[uuid], case .recording = tracked.phase else { return Step() }
        var step = Step()
        let isPresent = connected.contains { $0.uuid == uuid && !$0.isMirroring }
        switch end {
        case .showsAnotherScreen:
            step.events.append(event(.screenShowsAnotherScreensPicture, uuid, at: now))
            screens[uuid]?.phase = .showsAnotherScreen(since: now)
        case .diskFull:
            screens[uuid]?.phase = .waitingForRoom
        case .captureSourceGone where tracked.mayLoseCaptureSource:
            // Ends as a disconnect; `screen disconnected` comes with the
            // notice. Still listed after the settle time: a new stream.
            screens[uuid]?.phase = .idle
            screens[uuid]?.changedAt = now
            screens[uuid]?.mayLoseCaptureSource = false
        case .captureSourceGone:
            step.append(streamFailed(
                uuid, error: Self.captureSourceGoneAgain, isPresent: isPresent, at: now))
        case .writerFellBehind:
            step.events.append(event(.screenFileWriterFellBehind, uuid, at: now))
            scheduleRestart(uuid, at: now)
        case .writerFailed:
            if isPresent { scheduleRestart(uuid, at: now) } else { screens[uuid]?.phase = .idle }
        case .streamFailed(let error):
            step.append(streamFailed(uuid, error: error, isPresent: isPresent, at: now))
        }
        step.append(observe(connected, at: now))
        return step
    }

    /// There is room on the disk again: screens stopped by a full disk start again.
    public mutating func roomAgain() {
        for (uuid, tracked) in screens where tracked.phase == .waitingForRoom {
            screens[uuid]?.phase = .idle
        }
    }

    /// Whether a screen file waits for room on the disk.
    public var isWaitingForRoom: Bool { screens.values.contains { $0.phase == .waitingForRoom } }

    /// At sleep every screen file ends.
    public mutating func sleep(at now: Int64) -> Step {
        isAsleep = true
        var step = Step(events: [RecordingEvent(at: now, event: .sleep)])
        for (uuid, tracked) in screens.sorted(by: { $0.key < $1.key }) {
            if case .recording = tracked.phase { step.actions.append(.stop(uuid: uuid, ending: .sleep)) }
            if tracked.phase != .waitingForRoom { screens[uuid]?.phase = .idle }
        }
        return step
    }

    /// At wake the screens start again after the settle time, as read now.
    public mutating func wake(_ connected: [ConnectedScreen], at now: Int64) -> Step {
        isAsleep = false
        var step = Step(events: [RecordingEvent(at: now, event: .wake)])
        step.append(observe(connected, at: now))
        for uuid in screens.keys where screens[uuid]?.reading != nil {
            screens[uuid]?.changedAt = now
        }
        lastScreenChange = now
        return step
    }

    /// At Stop every screen file ends.
    public mutating func stopAll() -> [Action] {
        var actions: [Action] = []
        for (uuid, tracked) in screens.sorted(by: { $0.key < $1.key }) {
            if case .recording = tracked.phase { actions.append(.stop(uuid: uuid, ending: .stop)) }
            screens[uuid]?.phase = .idle
        }
        isAsleep = true
        return actions
    }

    /// Whether a screen's file ended because it showed another screen's picture and it was not tried again since.
    public var showsAnotherScreensPicture: Bool {
        screens.values.contains { if case .showsAnotherScreen = $0.phase { true } else { false } }
    }

    // MARK: -

    /// The screens the tracker follows: none at the resolution None.
    private func followed(_ connected: [ConnectedScreen]) -> [ConnectedScreen] {
        resolution.recordsScreens ? connected : []
    }

    private mutating func start(_ uuid: String, at now: Int64) -> Action {
        var tracked = screens[uuid]!
        let reading = tracked.reading!
        if tracked.number == nil {
            tracked.number = nextNumber
            nextNumber += 1
        }
        let name = tracked.name ?? reading.name ?? "Screen \(tracked.number!)"
        tracked.name = name
        let frameSize = resolution.frameSize(forLooksLike: reading.pointSize)
        tracked.phase = .recording(frameSize: frameSize)
        screens[uuid] = tracked
        return .start(uuid: uuid, displayID: reading.displayID, frameSize: frameSize, number: tracked.number!, name: name)
    }

    /// The error of a stream that lost its capture source again without a
    /// screen-change notice in between: a failure (N-A).
    public static let captureSourceGoneAgain =
        "ScreenCaptureKit lost the screen again without a screen change (noCaptureSource, -3815)"

    private mutating func streamFailed(_ uuid: String, error: String, isPresent: Bool, at now: Int64) -> Step {
        guard isPresent else {
            screens[uuid]?.phase = .idle
            return Step()
        }
        var failed = event(.screenStreamFailed, uuid, at: now)
        failed.error = error
        scheduleRestart(uuid, at: now)
        return Step(events: [failed])
    }

    private mutating func scheduleRestart(_ uuid: String, at now: Int64) {
        guard let delay = screens[uuid]?.restartDelay else { return }
        screens[uuid]?.phase = .waitingToRestart(notBefore: now + delay.nanoseconds)
        screens[uuid]?.restartDelay = min(delay * 2, longestRestartDelay)
    }

    /// Every screen the recording has seen, as the status window shows it.
    public struct Source: Equatable, Sendable {
        public enum State: Equatable, Sendable {
            case recording(FrameSize)
            /// Waits to start: the settle time after a change.
            case waiting
            /// Its file ended with an error; it starts again after the back-off.
            case failedRetrying
            case showsAnotherScreen
            case diskFull
            case mirroring
            case disconnected
            case asleep
        }

        public var uuid: String
        public var number: Int?
        public var name: String
        public var state: State
    }

    /// The screens in their numbers' order, those without a number last.
    public var sources: [Source] {
        screens.map { uuid, tracked in
            let state: Source.State = switch tracked.phase {
            case .recording(let frameSize): .recording(frameSize)
            case .waitingToRestart: .failedRetrying
            case .showsAnotherScreen: .showsAnotherScreen
            case .waitingForRoom: .diskFull
            case .idle where tracked.reading == nil: .disconnected
            case .idle where tracked.reading?.isMirroring == true: .mirroring
            case .idle where isAsleep: .asleep
            case .idle: .waiting
            }
            return Source(uuid: uuid, number: tracked.number, name: name(of: uuid) ?? uuid, state: state)
        }
        .sorted { ($0.number ?? .max, $0.uuid) < ($1.number ?? .max, $1.uuid) }
    }

    private func name(of uuid: String) -> String? {
        screens[uuid]?.name ?? screens[uuid]?.reading?.name
    }

    private func event(_ kind: RecordingEvent.Kind, _ uuid: String, at now: Int64) -> RecordingEvent {
        RecordingEvent(at: now, event: kind, screen: name(of: uuid))
    }

    /// Main screen first, then left to right, then top to bottom.
    static func leftToRight(_ connected: [ConnectedScreen]) -> [ConnectedScreen] {
        connected.sorted { lhs, rhs in
            if lhs.isMain != rhs.isMain { return lhs.isMain }
            if lhs.bounds.x != rhs.bounds.x { return lhs.bounds.x < rhs.bounds.x }
            if lhs.bounds.y != rhs.bounds.y { return lhs.bounds.y < rhs.bounds.y }
            return lhs.uuid < rhs.uuid
        }
    }
}
