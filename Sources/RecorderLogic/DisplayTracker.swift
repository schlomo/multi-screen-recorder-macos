import Foundation

/// Decides, for every display a recording has seen, when its stream starts
/// and when its display file ends, and which events go into the recording
/// manifest (recorder.md, "Displays coming and going", "Frame size",
/// "Display check"). It holds no stream and no file: the recorder carries
/// out its actions and reports back what happened. Times are nanoseconds
/// from t0 on the shared clock.
public struct DisplayTracker: Sendable {
    /// Why a display file ends.
    public enum Ending: Equatable, Sendable {
        case disconnected
        case frameSizeChanged
        case mirroringStarted
        case sleep
        case stop
    }

    /// What the recorder does for a display.
    public enum Action: Equatable, Sendable {
        /// Start a stream on the display and a display file once its first frame passes the display check.
        case start(uuid: String, displayID: UInt32, frameSize: FrameSize, number: Int, name: String)
        /// End the display's stream and finalize its display file.
        case stop(uuid: String, ending: Ending)
    }

    /// Why a stream ended by itself; the recorder reports it.
    public enum StreamEnd: Equatable, Sendable {
        case streamFailed(String)
        case writerFailed(String)
        case writerFellBehind
        case diskFull
        case showsAnotherDisplay
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
        /// Tried again only after the display's next change.
        case showsAnotherDisplay(since: Int64)
        case waitingForRoom
    }

    private struct Tracked {
        var number: Int?
        var name: String?
        var phase: Phase = .idle
        /// As last read; nil while the display is gone.
        var reading: ConnectedDisplay?
        /// When it last appeared, went or changed.
        var changedAt: Int64
        var restartDelay: Duration
    }

    public let resolution: RecordingResolution
    public let settleTime: Duration
    public let firstRestartDelay: Duration
    public let longestRestartDelay: Duration

    private var displays: [String: Tracked] = [:]
    private var nextNumber = 1
    private var mainUUID: String?
    private var isAsleep = false
    /// The newest change of any display: the display check does not count
    /// failing frames within the settle time after it.
    public private(set) var lastDisplayChange: Int64?

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

    /// The displays connected at the start: each gets its stream at once.
    /// Display 1 is the main display, the others are numbered left to right.
    public mutating func begin(_ connected: [ConnectedDisplay], at now: Int64) -> Step {
        for display in connected {
            displays[display.uuid] = Tracked(
                name: display.name, reading: display, changedAt: Int64.min / 2, restartDelay: firstRestartDelay)
        }
        mainUUID = connected.first(where: \.isMain)?.uuid
        var step = Step()
        for display in Self.leftToRight(connected.filter { !$0.isMirroring }) {
            step.actions.append(start(display.uuid, at: now))
        }
        return step
    }

    /// The display file of `uuid` started: its restart delay starts over.
    public mutating func fileStarted(_ uuid: String) {
        displays[uuid]?.restartDelay = firstRestartDelay
    }

    /// The displays as read after macOS reported a change. A display that
    /// went or started mirroring ends its file at once; one that came, came
    /// back or changed starts after the settle time (`due(at:)`).
    public mutating func observe(_ connected: [ConnectedDisplay], at now: Int64) -> Step {
        var step = Step()
        let byUUID = Dictionary(connected.map { ($0.uuid, $0) }, uniquingKeysWith: { first, _ in first })
        for (uuid, tracked) in displays.sorted(by: { $0.key < $1.key }) where tracked.reading != nil && byUUID[uuid] == nil {
            displays[uuid]?.reading = nil
            displays[uuid]?.changedAt = now
            lastDisplayChange = now
            if !(tracked.reading?.isMirroring ?? false) {
                step.events.append(event(.displayDisconnected, uuid, at: now))
            }
            if case .recording = tracked.phase { step.actions.append(.stop(uuid: uuid, ending: .disconnected)) }
            if tracked.phase != .waitingForRoom { displays[uuid]?.phase = .idle }
        }
        for display in Self.leftToRight(connected) {
            guard var tracked = displays[display.uuid] else {
                displays[display.uuid] = Tracked(
                    name: display.name, reading: display, changedAt: now, restartDelay: firstRestartDelay)
                lastDisplayChange = now
                if !display.isMirroring { step.events.append(event(.displayConnected, display.uuid, at: now)) }
                continue
            }
            let previous = tracked.reading
            guard previous != display else { continue }
            tracked.reading = display
            tracked.changedAt = now
            if tracked.name == nil { tracked.name = display.name }
            displays[display.uuid] = tracked
            lastDisplayChange = now
            if previous == nil {
                if !display.isMirroring { step.events.append(event(.displayConnected, display.uuid, at: now)) }
            } else if let previous, !previous.isMirroring, display.isMirroring {
                var started = event(.displayMirroringStarted, display.uuid, at: now)
                started.mirrors = display.mirrorsUUID.flatMap { name(of: $0) }
                step.events.append(started)
                if case .recording = tracked.phase {
                    step.actions.append(.stop(uuid: display.uuid, ending: .mirroringStarted))
                    displays[display.uuid]?.phase = .idle
                }
            } else if let previous, previous.isMirroring, !display.isMirroring {
                step.events.append(event(.displayMirroringStopped, display.uuid, at: now))
            }
        }
        let newMain = connected.first(where: \.isMain)?.uuid
        if let newMain, newMain != mainUUID {
            if mainUUID != nil { step.events.append(event(.mainDisplayChanged, newMain, at: now)) }
            mainUUID = newMain
        }
        return step
    }

    /// What is due at `now`: displays unchanged for the settle time start,
    /// and one whose frame size changed ends its file and starts a new one.
    public mutating func due(at now: Int64) -> Step {
        guard !isAsleep else { return Step() }
        var step = Step()
        let settled = displays.filter { _, tracked in
            guard let reading = tracked.reading, !reading.isMirroring else { return false }
            return now - tracked.changedAt >= settleTime.nanoseconds
        }
        let ordered = Self.leftToRight(settled.values.compactMap(\.reading))
        for display in ordered {
            guard let tracked = displays[display.uuid] else { continue }
            let frameSize = resolution.frameSize(forLooksLike: display.pointSize)
            switch tracked.phase {
            case .recording(let current) where current != frameSize:
                var changed = event(.displayFrameSizeChanged, display.uuid, at: now)
                changed.from = [current.width, current.height]
                changed.to = [frameSize.width, frameSize.height]
                step.events.append(changed)
                step.actions.append(.stop(uuid: display.uuid, ending: .frameSizeChanged))
                step.actions.append(start(display.uuid, at: now))
            case .recording, .waitingForRoom:
                break
            case .idle:
                step.actions.append(start(display.uuid, at: now))
            case .waitingToRestart(let notBefore) where notBefore <= now:
                step.actions.append(start(display.uuid, at: now))
            case .waitingToRestart:
                break
            case .showsAnotherDisplay(let since) where tracked.changedAt > since:
                step.actions.append(start(display.uuid, at: now))
            case .showsAnotherDisplay:
                break
            }
        }
        return step
    }

    /// The next time `due(at:)` may have something to do, if any.
    public func nextDueTime() -> Int64? {
        guard !isAsleep else { return nil }
        return displays.values.compactMap { tracked -> Int64? in
            guard let reading = tracked.reading, !reading.isMirroring else { return nil }
            let settled = tracked.changedAt + settleTime.nanoseconds
            switch tracked.phase {
            case .idle: return settled
            case .recording(let current):
                return resolution.frameSize(forLooksLike: reading.pointSize) == current ? nil : settled
            case .waitingToRestart(let notBefore): return max(settled, notBefore)
            case .showsAnotherDisplay(let since): return tracked.changedAt > since ? settled : nil
            case .waitingForRoom: return nil
            }
        }.min()
    }

    /// A stream ended by itself; `connected` is the displays as read now.
    /// A failing writer and a full disk have their event from the recorder,
    /// once per capture end, also when the tracker no longer follows it.
    public mutating func streamEnded(_ uuid: String, _ end: StreamEnd, connected: [ConnectedDisplay], at now: Int64) -> Step {
        guard let tracked = displays[uuid], case .recording = tracked.phase else { return Step() }
        var step = Step()
        let isPresent = connected.contains { $0.uuid == uuid && !$0.isMirroring }
        switch end {
        case .showsAnotherDisplay:
            step.events.append(event(.displayShowsAnotherDisplaysPicture, uuid, at: now))
            displays[uuid]?.phase = .showsAnotherDisplay(since: now)
        case .diskFull:
            displays[uuid]?.phase = .waitingForRoom
        case .writerFellBehind:
            step.events.append(event(.displayFileWriterFellBehind, uuid, at: now))
            scheduleRestart(uuid, at: now)
        case .writerFailed:
            if isPresent { scheduleRestart(uuid, at: now) } else { displays[uuid]?.phase = .idle }
        case .streamFailed(let error):
            if isPresent {
                var failed = event(.displayStreamFailed, uuid, at: now)
                failed.error = error
                step.events.append(failed)
                scheduleRestart(uuid, at: now)
            } else {
                displays[uuid]?.phase = .idle
            }
        }
        step.append(observe(connected, at: now))
        return step
    }

    /// There is room on the disk again: displays stopped by a full disk start again.
    public mutating func roomAgain() {
        for (uuid, tracked) in displays where tracked.phase == .waitingForRoom {
            displays[uuid]?.phase = .idle
        }
    }

    /// Whether a display file waits for room on the disk.
    public var isWaitingForRoom: Bool { displays.values.contains { $0.phase == .waitingForRoom } }

    /// At sleep every display file ends.
    public mutating func sleep(at now: Int64) -> Step {
        isAsleep = true
        var step = Step(events: [RecordingEvent(at: now, event: .sleep)])
        for (uuid, tracked) in displays.sorted(by: { $0.key < $1.key }) {
            if case .recording = tracked.phase { step.actions.append(.stop(uuid: uuid, ending: .sleep)) }
            if tracked.phase != .waitingForRoom { displays[uuid]?.phase = .idle }
        }
        return step
    }

    /// At wake the displays start again after the settle time, as read now.
    public mutating func wake(_ connected: [ConnectedDisplay], at now: Int64) -> Step {
        isAsleep = false
        var step = Step(events: [RecordingEvent(at: now, event: .wake)])
        step.append(observe(connected, at: now))
        for uuid in displays.keys where displays[uuid]?.reading != nil {
            displays[uuid]?.changedAt = now
        }
        lastDisplayChange = now
        return step
    }

    /// At Stop every display file ends.
    public mutating func stopAll() -> [Action] {
        var actions: [Action] = []
        for (uuid, tracked) in displays.sorted(by: { $0.key < $1.key }) {
            if case .recording = tracked.phase { actions.append(.stop(uuid: uuid, ending: .stop)) }
            displays[uuid]?.phase = .idle
        }
        isAsleep = true
        return actions
    }

    /// Whether a display's file ended because it showed another display's picture and it was not tried again since.
    public var showsAnotherDisplaysPicture: Bool {
        displays.values.contains { if case .showsAnotherDisplay = $0.phase { true } else { false } }
    }

    // MARK: -

    private mutating func start(_ uuid: String, at now: Int64) -> Action {
        var tracked = displays[uuid]!
        let reading = tracked.reading!
        if tracked.number == nil {
            tracked.number = nextNumber
            nextNumber += 1
        }
        let name = tracked.name ?? reading.name ?? "Display \(tracked.number!)"
        tracked.name = name
        let frameSize = resolution.frameSize(forLooksLike: reading.pointSize)
        tracked.phase = .recording(frameSize: frameSize)
        displays[uuid] = tracked
        return .start(uuid: uuid, displayID: reading.displayID, frameSize: frameSize, number: tracked.number!, name: name)
    }

    private mutating func scheduleRestart(_ uuid: String, at now: Int64) {
        guard let delay = displays[uuid]?.restartDelay else { return }
        displays[uuid]?.phase = .waitingToRestart(notBefore: now + delay.nanoseconds)
        displays[uuid]?.restartDelay = min(delay * 2, longestRestartDelay)
    }

    /// Every display the recording has seen, as the status window shows it.
    public struct Source: Equatable, Sendable {
        public enum State: Equatable, Sendable {
            case recording(FrameSize)
            /// Waits to start: the settle time after a change.
            case waiting
            /// Its file ended with an error; it starts again after the back-off.
            case failedRetrying
            case showsAnotherDisplay
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

    /// The displays in their numbers' order, those without a number last.
    public var sources: [Source] {
        displays.map { uuid, tracked in
            let state: Source.State = switch tracked.phase {
            case .recording(let frameSize): .recording(frameSize)
            case .waitingToRestart: .failedRetrying
            case .showsAnotherDisplay: .showsAnotherDisplay
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
        displays[uuid]?.name ?? displays[uuid]?.reading?.name
    }

    private func event(_ kind: RecordingEvent.Kind, _ uuid: String, at now: Int64) -> RecordingEvent {
        RecordingEvent(at: now, event: kind, display: name(of: uuid))
    }

    /// Main display first, then left to right, then top to bottom.
    static func leftToRight(_ connected: [ConnectedDisplay]) -> [ConnectedDisplay] {
        connected.sorted { lhs, rhs in
            if lhs.isMain != rhs.isMain { return lhs.isMain }
            if lhs.bounds.x != rhs.bounds.x { return lhs.bounds.x < rhs.bounds.x }
            if lhs.bounds.y != rhs.bounds.y { return lhs.bounds.y < rhs.bounds.y }
            return lhs.uuid < rhs.uuid
        }
    }
}
