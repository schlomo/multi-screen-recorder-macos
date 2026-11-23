import Foundation

/// Decides, for every camera a recording records, when its stream starts
/// and when its camera file ends, and which events go into the recording
/// manifest (recorder.md, "Cameras"; D74). Cameras follow the camera mode
/// and come and go as screens do, without mirroring, a main camera or a
/// screen check. It holds no stream and no file: the recorder carries out
/// its actions and reports back. Times are nanoseconds from t0 on the
/// shared clock.
public struct CameraTracker: Sendable {
    /// What the recorder does for a camera.
    public enum Action: Equatable, Sendable {
        /// Open the camera and start its camera file at `frameSize` with its
        /// first frame; `setsFormat`: set the camera to `format`, else, as
        /// another app uses it, keep the format it runs in. An iPhone camera
        /// (`isContinuity`) may take longer to its first frame.
        case start(
            uniqueID: String, format: CameraFormat, setsFormat: Bool, frameSize: FrameSize, number: Int, name: String,
            isContinuity: Bool)
        /// End the camera's stream and finalize its camera file.
        case stop(uniqueID: String)
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
        /// Not captured; starts once wanted, present and settled.
        case idle
        case recording(frameSize: FrameSize)
        case waitingToRestart(notBefore: Int64)
        case waitingForRoom
    }

    private struct Tracked {
        /// Given at its first start.
        var number: Int?
        var name: String
        var phase: Phase = .idle
        /// As last read; nil while the camera is gone.
        var reading: CameraInfo?
        /// Recorded under the camera mode as last read.
        var isWanted: Bool
        /// When it last appeared, went, or became wanted.
        var changedAt: Int64
        var restartDelay: Duration
        /// Whether its stream may end once with the camera gone without a
        /// failure: until it does, and again after each change of the cameras.
        var mayLoseCaptureSource = true
        /// While its recording stream delivers no frames, but has not failed.
        var isStalled = false
        /// Another app changed its format during the recording: from then on
        /// the recording keeps the camera's format, never setting it back.
        var isTakenOver = false
        /// Its latest file started in the format the camera ran in, as another app used it.
        var keptFormat = false
    }

    public let settings: Settings
    public let settleTime: Duration
    public let firstRestartDelay: Duration
    public let longestRestartDelay: Duration

    private var cameras: [String: Tracked] = [:]
    /// The unique IDs in the order the recording first saw them, the default camera first at the start.
    private var order: [String] = []
    private var nextNumber = 1
    private var defaultCamera: (uniqueID: String, name: String)?
    /// The cameras listed as last read, by unique ID.
    private var listedBefore: Set<String> = []
    private var isAsleep = false

    /// Whether a recording records `camera`, the one rule wherever a camera
    /// counts as recorded: the recording resolution records video (None is
    /// audio only), the camera mode includes it, it lists a format and is not suspended.
    public static func records(_ camera: CameraInfo, settings: Settings) -> Bool {
        settings.effectiveResolution.recordsScreens && settings.cameraModeIncludes(camera) && !camera.formats.isEmpty
            && !camera.isSuspended
    }

    public init(
        settings: Settings,
        settleTime: Duration = RecorderValues.settleTime,
        firstRestartDelay: Duration = RecorderValues.firstRestartDelay,
        longestRestartDelay: Duration = RecorderValues.longestRestartDelay
    ) {
        self.settings = settings
        self.settleTime = settleTime
        self.firstRestartDelay = firstRestartDelay
        self.longestRestartDelay = longestRestartDelay
    }

    /// The cameras connected at the start: each recorded one starts at once.
    public mutating func begin(_ connected: [CameraInfo], at now: Int64) -> Step {
        var step = observe(connected.filter(\.isDefault) + connected.filter { !$0.isDefault }, at: now, isBeginning: true)
        step.append(due(at: now))
        return step
    }

    /// The cameras as read after AVFoundation reported one connected or
    /// disconnected. A camera that went, or is no longer recorded, ends its
    /// file at once; one that came or came back starts after the settle time.
    public mutating func observe(_ connected: [CameraInfo], at now: Int64) -> Step {
        observe(connected, at: now, isBeginning: false)
    }

    private mutating func observe(_ connected: [CameraInfo], at now: Int64, isBeginning: Bool) -> Step {
        var step = Step()
        let newDefault = connected.first(where: \.isDefault).map { (uniqueID: $0.uniqueID, name: $0.name) }
        if !isBeginning, settings.effectiveCameraMode == .defaultCamera, newDefault?.uniqueID != defaultCamera?.uniqueID {
            var changed = RecordingEvent(at: now, event: .defaultCameraChanged)
            changed.from = defaultCamera.map { .name(cameras[$0.uniqueID]?.name ?? $0.name) }
            changed.to = newDefault.map { .name(cameras[$0.uniqueID]?.name ?? $0.name) }
            step.events.append(changed)
        }
        defaultCamera = newDefault
        let byID = Dictionary(connected.map { ($0.uniqueID, $0) }, uniquingKeysWith: { first, _ in first })
        for uniqueID in order {
            guard let tracked = cameras[uniqueID] else { continue }
            let reading = byID[uniqueID]
            let isWanted = reading.map { Self.records($0, settings: settings) } ?? false
            if tracked.reading != nil, reading == nil {
                cameras[uniqueID]?.changedAt = now
                cameras[uniqueID]?.mayLoseCaptureSource = true
                if tracked.phase != .idle || tracked.isWanted {
                    step.events.append(event(.cameraDisconnected, uniqueID, at: now))
                }
                if case .recording = tracked.phase { step.actions.append(.stop(uniqueID: uniqueID)) }
                if tracked.phase != .waitingForRoom { cameras[uniqueID]?.phase = .idle }
            } else if reading != nil {
                if tracked.reading == nil {
                    cameras[uniqueID]?.changedAt = now
                    cameras[uniqueID]?.mayLoseCaptureSource = true
                    if isWanted { step.events.append(event(.cameraConnected, uniqueID, at: now)) }
                } else if isWanted, !tracked.isWanted {
                    // Recorded again, as a former default camera: after the settle time.
                    cameras[uniqueID]?.changedAt = now
                }
                if case .recording = tracked.phase, !isWanted {
                    step.actions.append(.stop(uniqueID: uniqueID))
                    cameras[uniqueID]?.phase = .idle
                }
            }
            if tracked.isTakenOver, let reading, let before = tracked.reading, reading.activeFormat != before.activeFormat {
                // Another app changing the format again settles as a screen's change does (`due`).
                cameras[uniqueID]?.changedAt = now
            }
            cameras[uniqueID]?.reading = reading
            cameras[uniqueID]?.isWanted = isWanted
        }
        for camera in connected where cameras[camera.uniqueID] == nil && Self.records(camera, settings: settings) {
            cameras[camera.uniqueID] = Tracked(
                name: camera.name, reading: camera, isWanted: true, changedAt: isBeginning ? Int64.min / 2 : now,
                restartDelay: firstRestartDelay)
            order.append(camera.uniqueID)
            // Newly listed, not only newly recorded, as when it becomes the default.
            if !isBeginning, !listedBefore.contains(camera.uniqueID) {
                step.events.append(event(.cameraConnected, camera.uniqueID, at: now))
            }
        }
        listedBefore = Set(byID.keys)
        return step
    }

    /// What is due at `now`: cameras present, recorded and unchanged for the settle time start.
    public mutating func due(at now: Int64) -> Step {
        guard !isAsleep else { return Step() }
        var step = Step()
        for uniqueID in order {
            guard let tracked = cameras[uniqueID], tracked.reading != nil, tracked.isWanted,
                  now - tracked.changedAt >= settleTime.nanoseconds else { continue }
            switch tracked.phase {
            case .idle: step.actions.append(start(uniqueID))
            case .waitingToRestart(let notBefore) where notBefore <= now: step.actions.append(start(uniqueID))
            case .recording(let current):
                // Another app took control of the camera's format: a new file at its size, never set back.
                guard let frameSize = frameSizeTakenOver(tracked) else { break }
                var changed = event(.cameraFrameSizeChanged, uniqueID, at: now)
                changed.from = [current.width, current.height]
                changed.to = [frameSize.width, frameSize.height]
                step.events.append(changed)
                step.actions.append(.stop(uniqueID: uniqueID))
                step.actions.append(start(uniqueID))
            case .waitingToRestart, .waitingForRoom: break
            }
        }
        return step
    }

    /// The next time `due(at:)` may have something to do, if any.
    public func nextDueTime() -> Int64? {
        guard !isAsleep else { return nil }
        return cameras.values.compactMap { tracked -> Int64? in
            guard tracked.reading != nil, tracked.isWanted else { return nil }
            let settled = tracked.changedAt + settleTime.nanoseconds
            return switch tracked.phase {
            case .idle: settled
            case .waitingToRestart(let notBefore): max(settled, notBefore)
            case .recording: frameSizeTakenOver(tracked) == nil ? nil : settled
            case .waitingForRoom: nil
            }
        }.min()
    }

    /// The frame size of a recording camera whose format another app
    /// changed to one of another recorded frame size, if so.
    private func frameSizeTakenOver(_ tracked: Tracked) -> FrameSize? {
        guard case .recording(let current) = tracked.phase, tracked.isTakenOver, let active = tracked.reading?.activeFormat
        else { return nil }
        let frameSize = settings.effectiveResolution.cameraFrameSize(for: active.size, limited: settings.limitCameras)
        return frameSize == current ? nil : frameSize
    }

    /// The recording stream of `uniqueID` saw another app change the
    /// camera's format (`ForeignFormatWatch`): after the settle time, at a
    /// changed frame size, a new file at the format the camera runs in (`due`).
    public mutating func formatTakenOver(_ uniqueID: String, at now: Int64) {
        guard case .recording = cameras[uniqueID]?.phase else { return }
        cameras[uniqueID]?.isTakenOver = true
        cameras[uniqueID]?.changedAt = now
    }

    /// A camera file of `uniqueID` started: its restart delay starts over.
    public mutating func fileStarted(_ uniqueID: String) {
        cameras[uniqueID]?.restartDelay = firstRestartDelay
    }

    /// A stream ended by itself; `connected` is the cameras as read now. A
    /// failing writer and a full disk have their event from the recorder.
    public mutating func streamEnded(
        _ uniqueID: String, _ end: VideoStreamEnd, connected: [CameraInfo], at now: Int64
    ) -> Step {
        guard let tracked = cameras[uniqueID], case .recording = tracked.phase else { return Step() }
        var step = Step()
        let isPresent = connected.contains { $0.uniqueID == uniqueID }
        switch end {
        case .diskFull:
            cameras[uniqueID]?.phase = .waitingForRoom
        case .captureSourceGone where tracked.mayLoseCaptureSource:
            // Ends as a disconnect; `camera disconnected` comes with AVFoundation's notice.
            cameras[uniqueID]?.phase = .idle
            cameras[uniqueID]?.changedAt = now
            cameras[uniqueID]?.mayLoseCaptureSource = false
        case .captureSourceGone:
            step.append(streamFailed(uniqueID, error: Self.captureSourceGoneAgain, isPresent: isPresent, at: now))
        case .writerFellBehind:
            step.events.append(event(.cameraFileWriterFellBehind, uniqueID, at: now))
            scheduleRestart(uniqueID, at: now)
        case .writerFailed, .showsAnotherScreen:
            if isPresent { scheduleRestart(uniqueID, at: now) } else { cameras[uniqueID]?.phase = .idle }
        case .streamFailed(let error):
            step.append(streamFailed(uniqueID, error: error, isPresent: isPresent, at: now))
        }
        step.append(observe(connected, at: now))
        return step
    }

    /// The recording stream of `uniqueID` delivered no frame for the stall
    /// limit (`CameraFrameWatch`): its file goes on, repeating its last frame.
    public mutating func stalled(_ uniqueID: String, at now: Int64) -> Step {
        guard let tracked = cameras[uniqueID], case .recording = tracked.phase, !tracked.isStalled else { return Step() }
        cameras[uniqueID]?.isStalled = true
        var stalled = event(.cameraStalled, uniqueID, at: now)
        stalled.errorDetail = Self.stalledError
        return Step(events: [stalled])
    }

    /// The stalled stream of `uniqueID` delivers again, `length` nanoseconds after its last frame.
    public mutating func stallEnded(_ uniqueID: String, length: Int64, at now: Int64) -> Step {
        guard let tracked = cameras[uniqueID], case .recording = tracked.phase, tracked.isStalled else { return Step() }
        cameras[uniqueID]?.isStalled = false
        var ended = event(.cameraStallEnded, uniqueID, at: now)
        ended.length = (Double(length) / 1_000_000).rounded() / 1000
        return Step(events: [ended])
    }

    /// Why a stall is a problem: the camera file repeats its last frame meanwhile.
    public static let stalledError = ErrorDetail(
        message: "the camera delivered no frame for \(CameraFrameWatch.text(RecorderValues.cameraStallLimit)); "
            + "its file repeats the last frame until frames come again")

    /// The error of a stream that lost its camera again without a change of the cameras: a failure.
    public static let captureSourceGoneAgain: ErrorDetail =
        "AVFoundation lost the camera again without a change of the cameras"

    /// There is room on the disk again: cameras stopped by a full disk start again.
    public mutating func roomAgain() {
        for (uniqueID, tracked) in cameras where tracked.phase == .waitingForRoom {
            cameras[uniqueID]?.phase = .idle
        }
    }

    /// Whether a camera file waits for room on the disk.
    public var isWaitingForRoom: Bool { cameras.values.contains { $0.phase == .waitingForRoom } }

    /// At sleep every camera file ends; the screens' tracker tells the sleep.
    public mutating func sleep() -> [Action] {
        isAsleep = true
        return stopEach()
    }

    /// At wake the cameras start again after the settle time, as read now.
    public mutating func wake(_ connected: [CameraInfo], at now: Int64) -> Step {
        isAsleep = false
        let step = observe(connected, at: now)
        for uniqueID in cameras.keys where cameras[uniqueID]?.reading != nil {
            cameras[uniqueID]?.changedAt = now
        }
        return step
    }

    /// At Stop every camera file ends.
    public mutating func stopAll() -> [Action] {
        isAsleep = true
        return stopEach()
    }

    private mutating func stopEach() -> [Action] {
        var actions: [Action] = []
        for uniqueID in order {
            guard let tracked = cameras[uniqueID] else { continue }
            if case .recording = tracked.phase { actions.append(.stop(uniqueID: uniqueID)) }
            if tracked.phase != .waitingForRoom { cameras[uniqueID]?.phase = .idle }
        }
        return actions
    }

    // MARK: -

    private mutating func start(_ uniqueID: String) -> Action {
        var tracked = cameras[uniqueID]!
        let reading = tracked.reading!
        if tracked.number == nil {
            tracked.number = nextNumber
            nextNumber += 1
        }
        // `records` holds for a wanted camera, so it has a format, and the resolution records video.
        let keepsFormat = reading.isRunningElsewhere || tracked.isTakenOver
        let format = (keepsFormat ? reading.activeFormat : nil)
            ?? reading.chosenFormat(resolution: settings.effectiveResolution, limited: settings.limitCameras)!
        let frameSize = settings.effectiveResolution.cameraFrameSize(for: format.size, limited: settings.limitCameras)
        tracked.phase = .recording(frameSize: frameSize)
        tracked.isStalled = false
        tracked.keptFormat = keepsFormat
        cameras[uniqueID] = tracked
        return .start(
            uniqueID: uniqueID, format: format, setsFormat: !keepsFormat, frameSize: frameSize,
            number: tracked.number!, name: tracked.name, isContinuity: reading.isContinuity)
    }

    private mutating func streamFailed(_ uniqueID: String, error: ErrorDetail, isPresent: Bool, at now: Int64) -> Step {
        guard isPresent else {
            cameras[uniqueID]?.phase = .idle
            return Step()
        }
        var failed = event(.cameraStreamFailed, uniqueID, at: now)
        failed.errorDetail = error
        scheduleRestart(uniqueID, at: now)
        return Step(events: [failed])
    }

    private mutating func scheduleRestart(_ uniqueID: String, at now: Int64) {
        guard let delay = cameras[uniqueID]?.restartDelay else { return }
        cameras[uniqueID]?.phase = .waitingToRestart(notBefore: now + delay.nanoseconds)
        cameras[uniqueID]?.restartDelay = min(delay * 2, longestRestartDelay)
    }

    private func event(_ kind: RecordingEvent.Kind, _ uniqueID: String, at now: Int64) -> RecordingEvent {
        RecordingEvent(at: now, event: kind, camera: cameras[uniqueID]?.name)
    }

    /// The camera as last read, for the status window's details; its
    /// `isRunningElsewhere` says whether its latest file kept the format
    /// another app set, as a reading during the recording counts the
    /// recording's own use too. Nil while it is gone.
    public func recordedReading(of uniqueID: String) -> CameraInfo? {
        guard let tracked = cameras[uniqueID], var reading = tracked.reading else { return nil }
        reading.isRunningElsewhere = tracked.keptFormat
        return reading
    }

    /// Every camera the recording has seen, as the status window shows it.
    public struct Source: Equatable, Sendable {
        public enum State: Equatable, Sendable {
            case recording(FrameSize)
            /// Recording, but its stream delivers no frames for now: the file repeats its last frame.
            case stalled(FrameSize)
            /// Waits to start: the settle time after a change.
            case waiting
            /// Its file ended with an error; it starts again after the back-off.
            case failedRetrying
            case diskFull
            case disconnected
            /// Connected, but not recorded: suspended, or no longer in the
            /// camera mode, as a former default camera.
            case notRecorded
            case asleep
        }

        public var uniqueID: String
        public var number: Int?
        public var name: String
        public var state: State
    }

    /// The cameras in their numbers' order, those without a number last.
    public var sources: [Source] {
        order.compactMap { uniqueID in
            guard let tracked = cameras[uniqueID] else { return nil }
            let state: Source.State = switch tracked.phase {
            case .recording(let frameSize): tracked.isStalled ? .stalled(frameSize) : .recording(frameSize)
            case .waitingToRestart: .failedRetrying
            case .waitingForRoom: .diskFull
            case .idle where tracked.reading == nil: .disconnected
            case .idle where !tracked.isWanted: .notRecorded
            case .idle where isAsleep: .asleep
            case .idle: .waiting
            }
            return Source(uniqueID: uniqueID, number: tracked.number, name: tracked.name, state: state)
        }
        .enumerated()
        .sorted { ($0.element.number ?? .max, $0.offset) < ($1.element.number ?? .max, $1.offset) }
        .map(\.element)
    }
}
