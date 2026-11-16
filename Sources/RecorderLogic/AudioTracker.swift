/// Decides, for every audio source a recording records, when its capture
/// starts and ends, and which events go into the recording manifest
/// (recorder.md, "Audio"; D49). Audio inputs follow the audio mode and the
/// default microphone; the system audio comes from a stream on the main
/// display and moves with it. It holds no capture and no file: the recorder
/// carries out its actions and reports back. Times are nanoseconds from t0
/// on the shared clock.
public struct AudioTracker: Sendable {
    public enum SourceID: Hashable, Sendable, Comparable {
        /// An audio input by its Core Audio UID.
        case input(String)
        case systemAudio
    }

    public enum Action: Equatable, Sendable {
        /// Capture the audio input into audio files under its unique name.
        case startInput(uid: String, name: String)
        /// Capture the system audio through a stream on the main display as
        /// read when it starts; the recorder reports the display back.
        case startSystemAudio
        /// End the source's capture and finalize its audio file.
        case stop(SourceID)
    }

    /// Why a capture ended by itself; the recorder reports it.
    public enum CaptureEnd: Equatable, Sendable {
        /// The audio input was unplugged, or the system audio's display went: no failure.
        case disconnected
        case captureFailed(String)
        case writerFailed(String)
        /// The writer took none of the samples of the late-tick bound.
        case writerFellBehind
        case diskFull
    }

    public struct Step: Equatable, Sendable {
        public var events: [RecordingEvent] = []
        public var actions: [Action] = []
        /// Audio inputs that are to be recorded and cannot be: their names.
        public var notRecordable: [String] = []

        public init(events: [RecordingEvent] = [], actions: [Action] = [], notRecordable: [String] = []) {
            self.events = events
            self.actions = actions
            self.notRecordable = notRecordable
        }

        mutating func append(_ other: Step) {
            events += other.events
            actions += other.actions
            notRecordable += other.notRecordable
        }
    }

    private enum Phase: Equatable {
        /// Not captured; starts once wanted, present and settled.
        case idle
        case recording
        case waitingToRestart(notBefore: Int64)
        case waitingForRoom
    }

    private struct Tracked {
        var name: String
        var phase: Phase = .idle
        /// Listed by Core Audio as last read, or for the system audio: on.
        var isPresent: Bool
        /// Recorded under the audio mode as last read.
        var isWanted: Bool
        /// When it last appeared, went, or its capture ended without a failure.
        var changedAt: Int64
        var restartDelay: Duration
        /// The channel count as last read, to start a new file when it changes.
        var channelCount: Int?
        /// It was recorded at some time: the status window and events name it.
        var wasRecorded = false
        /// Its capture saw it disconnect, which was told; the device list may follow.
        var disconnectTold = false
        /// A capture may end as disconnected without a failure: true until
        /// one did, and again once the device list or the displays changed.
        var mayLoseCaptureSource = true
    }

    public let settings: Settings
    public let settleTime: Duration
    public let firstRestartDelay: Duration
    public let longestRestartDelay: Duration

    private var sources: [SourceID: Tracked] = [:]
    private var names = AudioInputNames()
    private var defaultInput: (uid: String, name: String)?
    /// The audio inputs listed as last read, by UID.
    private var listedBefore: Set<String> = []
    private var mainDisplayID: UInt32?
    /// The displays as last read, to tell a display change.
    private var connectedDisplays: Set<UInt32>?
    /// The display the system audio's stream captures, while it runs.
    private var systemAudioDisplayID: UInt32?
    private var isAsleep = false

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

    /// The audio inputs and the main display at the start: what is recorded starts at once.
    public mutating func begin(inputs: [AudioInputInfo], mainDisplayID: UInt32?, at now: Int64) -> Step {
        var step = observe(inputs, at: now, isBeginning: true)
        if settings.systemAudio {
            sources[.systemAudio] = Tracked(
                name: AudioFileDescription.systemAudioName, isPresent: true, isWanted: true, changedAt: Int64.min / 2,
                restartDelay: firstRestartDelay)
        }
        self.mainDisplayID = mainDisplayID
        step.append(due(at: now))
        return step
    }

    /// The audio inputs as read after Core Audio reported a change of the
    /// devices or of the default input.
    public mutating func observe(_ inputs: [AudioInputInfo], at now: Int64) -> Step {
        observe(inputs, at: now, isBeginning: false)
    }

    private mutating func observe(_ inputs: [AudioInputInfo], at now: Int64, isBeginning: Bool) -> Step {
        var step = Step()
        let newDefault = inputs.first(where: \.isDefault).flatMap { input in input.uid.map { ($0, input.name) } }
        if !isBeginning, settings.effectiveAudioMode != .none, newDefault?.0 != defaultInput?.uid {
            var changed = RecordingEvent(at: now, event: .defaultMicrophoneChanged)
            changed.from = defaultInput.map { .name(displayName($0.uid, fallback: $0.name)) }
            changed.to = newDefault.map { .name(displayName($0.0, fallback: $0.1)) }
            step.events.append(changed)
        }
        defaultInput = newDefault.map { (uid: $0.0, name: $0.1) }

        let listed = Dictionary(inputs.compactMap { input in input.uid.map { ($0, input) } }, uniquingKeysWith: { first, _ in first })
        for (id, tracked) in sources.sorted(by: { $0.key < $1.key }) {
            guard case .input(let uid) = id else { continue }
            let input = listed[uid]
            let isWanted = input.map(settings.records) ?? false
            let channelCount = input.flatMap { try? $0.channelCount.get() }
            if tracked.isPresent, input == nil {
                sources[id]?.isPresent = false
                sources[id]?.changedAt = now
                sources[id]?.mayLoseCaptureSource = true
                if tracked.wasRecorded, !tracked.disconnectTold, tracked.phase != .idle || tracked.isWanted {
                    step.events.append(RecordingEvent(at: now, event: .audioInputDisconnected, audioSource: tracked.name))
                }
                if tracked.phase == .recording { step.actions.append(.stop(id)) }
                if tracked.phase != .waitingForRoom { sources[id]?.phase = .idle }
            } else if input != nil {
                if !tracked.isPresent {
                    sources[id]?.isPresent = true
                    sources[id]?.changedAt = now
                    sources[id]?.disconnectTold = false
                    sources[id]?.mayLoseCaptureSource = true
                    if isWanted, tracked.wasRecorded {
                        step.events.append(RecordingEvent(at: now, event: .audioInputConnected, audioSource: tracked.name))
                    }
                } else if isWanted, !tracked.isWanted {
                    // Recorded again, as a former default microphone: after the settle time.
                    sources[id]?.changedAt = now
                }
                if tracked.phase == .recording, !isWanted || (channelCount != nil && channelCount != tracked.channelCount) {
                    // No longer recorded, or a new file at the new channel count after the settle time.
                    step.actions.append(.stop(id))
                    sources[id]?.phase = .idle
                    sources[id]?.changedAt = now
                }
                sources[id]?.channelCount = channelCount ?? tracked.channelCount
            }
            sources[id]?.isWanted = isWanted
        }
        for input in inputs where settings.records(input) {
            guard let uid = input.uid else {
                step.notRecordable.append(input.name)
                continue
            }
            guard sources[.input(uid)] == nil else { continue }
            let name = names.name(coreAudioUID: uid, deviceName: input.name)
            sources[.input(uid)] = Tracked(
                name: name, isPresent: true, isWanted: true, changedAt: isBeginning ? Int64.min / 2 : now,
                restartDelay: firstRestartDelay, channelCount: try? input.channelCount.get())
            // Newly listed, not only newly recorded, as when it becomes the default.
            if !isBeginning, !listedBefore.contains(uid) {
                step.events.append(RecordingEvent(at: now, event: .audioInputConnected, audioSource: name))
            }
        }
        listedBefore = Set(listed.keys)
        return step
    }

    /// The main display and the displays connected, as read after a display
    /// change: the system audio's stream moves to the new main display when
    /// its display goes.
    public mutating func observeDisplays(mainDisplayID: UInt32?, connected: Set<UInt32>, at now: Int64) -> Step {
        if connectedDisplays != nil, connectedDisplays != connected || self.mainDisplayID != mainDisplayID {
            sources[.systemAudio]?.mayLoseCaptureSource = true
        }
        connectedDisplays = connected
        self.mainDisplayID = mainDisplayID
        guard let tracked = sources[.systemAudio], tracked.phase == .recording, let current = systemAudioDisplayID,
              !connected.contains(current) else { return Step() }
        sources[.systemAudio]?.phase = .idle
        sources[.systemAudio]?.changedAt = now
        systemAudioDisplayID = nil
        return Step(events: [RecordingEvent(at: now, event: .systemAudioStopped, audioSource: tracked.name)],
                    actions: [.stop(.systemAudio)])
    }

    /// The system audio's stream captures this display, read as it started.
    public mutating func systemAudioCaptures(displayID: UInt32) {
        guard sources[.systemAudio]?.phase == .recording else { return }
        systemAudioDisplayID = displayID
    }

    /// The error of a capture lost again with no change of the devices or displays.
    public static func sourceLostAgain(_ id: SourceID) -> String {
        id == .systemAudio
            ? "ScreenCaptureKit lost the system audio's display again without a display change"
            : "AVFoundation lost the audio input again without a change of the audio devices"
    }

    /// A file of the source started: its restart delay starts over.
    public mutating func fileStarted(_ id: SourceID) {
        sources[id]?.restartDelay = firstRestartDelay
    }

    /// A capture ended by itself.
    public mutating func captureEnded(_ id: SourceID, _ end: CaptureEnd, at now: Int64) -> Step {
        guard let tracked = sources[id], tracked.phase == .recording else { return Step() }
        if id == .systemAudio { systemAudioDisplayID = nil }
        var step = Step()
        switch end {
        case .disconnected where !tracked.mayLoseCaptureSource && tracked.isPresent && tracked.isWanted:
            // Lost again with no notice that it went: a failure, as for a display.
            var failed = RecordingEvent(at: now, event: id == .systemAudio ? .systemAudioFailed : .audioInputFailed, audioSource: tracked.name)
            failed.error = Self.sourceLostAgain(id)
            step.events.append(failed)
            scheduleRestart(id, at: now)
        case .disconnected:
            sources[id]?.mayLoseCaptureSource = false
            step.events.append(RecordingEvent(
                at: now, event: id == .systemAudio ? .systemAudioStopped : .audioInputDisconnected, audioSource: tracked.name))
            if id == .systemAudio {
                // The display went: the stream starts again on the main display.
                sources[id]?.phase = .idle
                sources[id]?.changedAt = now
            } else {
                // Gone from the list soon; still listed, it is tried again
                // with the back-off, without a failure.
                sources[id]?.disconnectTold = true
                scheduleRestart(id, at: now)
            }
        case .captureFailed(let error):
            var failed = RecordingEvent(at: now, event: id == .systemAudio ? .systemAudioFailed : .audioInputFailed, audioSource: tracked.name)
            failed.error = error
            step.events.append(failed)
            scheduleRestart(id, at: now)
        case .writerFailed(let error):
            var failed = RecordingEvent(at: now, event: .audioFileWriterFailed, audioSource: tracked.name)
            failed.error = error
            step.events.append(failed)
            scheduleRestart(id, at: now)
        case .writerFellBehind:
            step.events.append(RecordingEvent(at: now, event: .audioFileWriterFellBehind, audioSource: tracked.name))
            scheduleRestart(id, at: now)
        case .diskFull:
            step.events.append(RecordingEvent(at: now, event: .diskFull, audioSource: tracked.name))
            sources[id]?.phase = .waitingForRoom
        }
        return step
    }

    /// What is due at `now`: sources wanted, present and settled start.
    public mutating func due(at now: Int64) -> Step {
        guard !isAsleep else { return Step() }
        var step = Step()
        for (id, tracked) in sources.sorted(by: { $0.key < $1.key }) where tracked.isWanted {
            guard isStartable(id, tracked, at: now) else { continue }
            switch id {
            case .input(let uid):
                guard tracked.isPresent else { continue }
                step.actions.append(.startInput(uid: uid, name: tracked.name))
            case .systemAudio:
                // A display to capture is known; the stream reads the main one as it starts.
                guard mainDisplayID != nil else { continue }
                if tracked.wasRecorded {
                    step.events.append(RecordingEvent(at: now, event: .systemAudioStarted, audioSource: tracked.name))
                }
                systemAudioDisplayID = nil
                step.actions.append(.startSystemAudio)
            }
            sources[id]?.phase = .recording
            sources[id]?.wasRecorded = true
            sources[id]?.disconnectTold = false
        }
        return step
    }

    private func isStartable(_ id: SourceID, _ tracked: Tracked, at now: Int64) -> Bool {
        switch tracked.phase {
        case .idle: now - tracked.changedAt >= settleTime.nanoseconds
        case .waitingToRestart(let notBefore): notBefore <= now
        case .recording, .waitingForRoom: false
        }
    }

    /// The next time `due(at:)` may have something to do, if any.
    public func nextDueTime() -> Int64? {
        guard !isAsleep else { return nil }
        return sources.compactMap { id, tracked -> Int64? in
            guard tracked.isWanted, id == .systemAudio ? mainDisplayID != nil : tracked.isPresent else { return nil }
            return switch tracked.phase {
            case .idle: tracked.changedAt + settleTime.nanoseconds
            case .waitingToRestart(let notBefore): notBefore
            case .recording, .waitingForRoom: nil
            }
        }.min()
    }

    /// There is room on the disk again: sources stopped by a full disk start again.
    public mutating func roomAgain() {
        for (id, tracked) in sources where tracked.phase == .waitingForRoom { sources[id]?.phase = .idle }
    }

    public var isWaitingForRoom: Bool { sources.values.contains { $0.phase == .waitingForRoom } }

    /// At sleep every audio file ends.
    public mutating func sleep() -> [Action] {
        isAsleep = true
        return stopEverything()
    }

    /// At wake the sources start again after the settle time.
    public mutating func wake(_ inputs: [AudioInputInfo], at now: Int64) -> Step {
        isAsleep = false
        var step = observe(inputs, at: now)
        for id in sources.keys where sources[id]?.phase == .idle { sources[id]?.changedAt = now }
        step.append(due(at: now))
        return step
    }

    /// At Stop every audio file ends.
    public mutating func stopAll() -> [Action] {
        isAsleep = true
        return stopEverything()
    }

    private mutating func stopEverything() -> [Action] {
        var actions: [Action] = []
        for (id, tracked) in sources.sorted(by: { $0.key < $1.key }) {
            if tracked.phase == .recording { actions.append(.stop(id)) }
            if tracked.phase != .waitingForRoom { sources[id]?.phase = .idle }
        }
        systemAudioDisplayID = nil
        return actions
    }

    private mutating func scheduleRestart(_ id: SourceID, at now: Int64) {
        guard let delay = sources[id]?.restartDelay else { return }
        sources[id]?.phase = .waitingToRestart(notBefore: now + delay.nanoseconds)
        sources[id]?.restartDelay = min(delay * 2, longestRestartDelay)
    }

    private func displayName(_ uid: String, fallback: String) -> String {
        sources[.input(uid)]?.name ?? RecordingNames.fileNamePart(fallback)
    }

    /// Every audio source the recording records or recorded, as the status window shows it.
    public struct Source: Equatable, Sendable {
        public enum State: Equatable, Sendable {
            case recording
            case waiting
            case failedRetrying
            case diskFull
            case disconnected
            case notRecorded
            case asleep
        }

        public var id: SourceID
        public var name: String
        public var state: State
    }

    /// The audio inputs by name, then the system audio.
    public var sourcesShown: [Source] {
        sources.filter { $0.value.wasRecorded || $0.value.isWanted }.map { id, tracked in
            let state: Source.State = switch tracked.phase {
            case .recording: .recording
            case .waitingToRestart where !tracked.isPresent: .disconnected
            case .waitingToRestart: .failedRetrying
            case .waitingForRoom: .diskFull
            case .idle where isAsleep: .asleep
            case .idle where !tracked.isPresent: .disconnected
            case .idle where !tracked.isWanted: .notRecorded
            case .idle: .waiting
            }
            return Source(id: id, name: tracked.name, state: state)
        }
        .sorted { ($0.id == .systemAudio ? 1 : 0, $0.name) < ($1.id == .systemAudio ? 1 : 0, $1.name) }
    }
}
