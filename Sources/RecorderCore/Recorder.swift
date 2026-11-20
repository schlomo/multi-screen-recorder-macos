import AppKit
import CoreGraphics
import Foundation
import RecorderLogic

/// What the person is told while recording: the Dock badge and, for
/// `msr record`, standard error.
@MainActor
public protocol RecorderObserver: AnyObject {
    /// Free space below the low disk warning threshold, or back above it.
    func recorder(_ recorder: Recorder, lowDiskSpace: Bool)
    /// A screen's file ended because it showed another screen's picture,
    /// or (nil) no screen is in that state any more.
    func recorder(_ recorder: Recorder, screenShowsAnotherScreensPicture screen: String?)
    /// A problem, also listed in the recording manifest's `problems`;
    /// `ofAnEvent` when an event's line tells the same failure (D65).
    func recorder(_ recorder: Recorder, problem: RecordingProblem, ofAnEvent: Bool)
    /// An event of the recording manifest, as one line (`EventLine`), or
    /// the count of a failure's repeats; a repeat itself is not passed on
    /// (`RepeatedFailures`, D65). `isFailure` for a failure and a count.
    func recorder(_ recorder: Recorder, eventLine: String, isFailure: Bool)
}

public struct RecorderStartError: ErrorWithDetail, CustomStringConvertible {
    public let detail: ErrorDetail

    init(_ message: String, underlying error: any Error) {
        detail = ErrorDetail(message: message, underlying: error)
    }

    public var description: String { detail.text }
}

/// One recording: claims its recording folder, keeps its recording
/// manifest, keeps the Mac awake, follows the screens as they come, go
/// and change, with one screen capture per screen file, and the audio
/// sources, with one audio capture per source, and its guide tracks.
/// Needs the AppKit event loop: macOS reports screen changes only to a
/// process running `NSApplication.run()`.
@MainActor
public final class Recorder {
    public let folder: URL
    private let context: RecordingContext
    private let settings: Settings
    /// Whether the recording reads the screens: for screen files and for the
    /// system audio, which follows the main screen. Audio only without the
    /// system audio never reads them, so no screen fails a microphone recording.
    private let readsScreens: Bool
    private weak var observer: (any RecorderObserver)?
    private var manifest: RecordingManifest
    private var tracker: ScreenTracker
    /// The running capture of each screen, with its number among all captures of the recording.
    private var captures: [String: (Int, ScreenCapture)] = [:]
    private var captureCount = 0
    private var endReports = CaptureEndReports()
    private var problemsTold = ProblemsTold()
    private var repeats = RepeatedFailures()
    private var finalManifestWritten = true
    /// Stops in progress, so Stop waits for every file; each leaves when done.
    private var stopping: [Int: Task<Void, Never>] = [:]
    private var stopCount = 0
    private var dueTask: Task<Void, Never>?
    private var freeSpaceTask: Task<Void, Never>?
    private var activity: (any NSObjectProtocol)?
    private var notificationTokens: [any NSObjectProtocol] = []
    private var isLowOnDisk = false
    private var isStopped = false
    private var screenChangePending = false
    private var audioTracker: AudioTracker
    /// The running capture of each audio source, with its number among all audio captures.
    private var audioCaptures: [AudioTracker.SourceID: (Int, AudioCapture)] = [:]
    private var audioCaptureCount = 0
    private var audioDueTask: Task<Void, Never>?
    private var audioWatch: AudioInputWatch?
    private let audioReports = AudioReportInbox()
    /// The latest clock drift correction status of each audio capture, by its number among all audio captures.
    private var audioClockDrift: [AudioTracker.SourceID: (number: Int, status: ClockDriftCorrection.Status)] = [:]
    private let guides: GuideTrackFeed
    private var clockDriftDetailSchedule = ClockDriftDetailSchedule()
    /// Nil when it could not be created: that is a problem, and the recording goes on.
    private var recordingLog: RecordingLog?
    private var cpu = CPUUsage()
    private var cpuTask: Task<Void, Never>?

    /// Starts a recording into a new recording folder in the settings' output
    /// folder; the recording log starts with the ready check's facts.
    public init(
        settings: Settings, homeFolder: URL, app: String, readyCheckFacts: ReadyCheckFacts, observer: any RecorderObserver
    ) throws(RecorderStartError) {
        let readsScreens = ReadyCheck.needsScreenRecording(settings)
        let screens: [ConnectedScreen]
        do {
            screens = readsScreens ? try connectedScreens() : []
        } catch {
            throw RecorderStartError("The screens cannot be read", underlying: error)
        }
        let reading = readClocks()
        let started = Date()
        let timeZone = TimeZone.current
        let outputFolder = settings.outputFolderURL(homeFolder: homeFolder)
        folder = outputFolder.appending(
            path: RecordingNames.recordingFolder(start: started, timeZone: timeZone), directoryHint: .isDirectory)
        do {
            // Claims the folder: refused if it already exists (D20).
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        } catch {
            throw RecorderStartError("Cannot create the recording folder \(folder.path(percentEncoded: false))", underlying: error)
        }
        context = RecordingContext(folder: folder, started: started, timeZone: timeZone, clock: SharedClock(reading: reading), app: app)
        self.settings = settings
        self.readsScreens = readsScreens
        self.observer = observer
        manifest = RecordingManifest(app: app, started: started, timeZone: timeZone, settings: settings)
        tracker = ScreenTracker(resolution: settings.effectiveResolution)
        audioTracker = AudioTracker(settings: settings)
        guides = GuideTrackFeed(tracks: GuideTrack.tracks(for: settings), now: { [context] in context.now() })
        do {
            try writeManifest()
        } catch {
            // Nothing was recorded: the start leaves nothing behind.
            try? FileManager.default.removeItem(at: folder.appending(path: RecordingNames.manifest))
            try? FileManager.default.removeItem(at: folder)
            throw RecorderStartError("Cannot start the recording in \(folder.path(percentEncoded: false))", underlying: error)
        }
        activity = ProcessInfo.processInfo.beginActivity(
            options: [.idleSystemSleepDisabled, .idleDisplaySleepDisabled, .userInitiated],
            reason: "Multi Screen Recorder is recording")
        let context = context
        startRecordingLog(app: app, readyCheckFacts: readyCheckFacts)
        registerForChanges()
        context.update(screens, lastScreenChange: nil)
        guides.start()
        apply(tracker.begin(screens, at: context.now()))
        applyAudio(audioTracker.begin(
            inputs: readAudioInputs() ?? [], mainDisplayID: screens.first(where: \.isMain)?.displayID,
            screens: Set(screens.map(\.displayID)), at: context.now()))
        freeSpaceTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: RecorderValues.freeSpaceCheckInterval)
                self?.checkFreeSpace()
            }
        }
        sampleCPU()
        cpuTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: RecorderValues.cpuSampleInterval)
                self?.sampleCPU()
                self?.logClockDriftBlock()
                self?.recordingLog?.flushIfDue()
            }
        }
    }

    private func clockDriftShown() -> [(source: AudioTracker.Source, status: ClockDriftCorrection.Status)] {
        ClockDriftShown.sources(
            shown: audioTracker.sourcesShown, reports: audioClockDrift, running: audioCaptures.mapValues(\.0))
    }

    /// Every 10 s the clock drift lines of all audio sources being recorded, together in number order.
    private func logClockDriftBlock() {
        guard clockDriftDetailSchedule.due(at: context.now()) else { return }
        let sources = clockDriftShown().map { (number: $0.source.number, label: $0.source.label, status: $0.status) }
        for line in DetailLine.clockDriftBlock(sources) { RecorderLog.detail(line, category: "recorder") }
    }

    private func sampleCPU() {
        guard let seconds = processCPUSeconds() else { return }
        cpu.sample(cpuSeconds: seconds, at: Double(context.now()) / 1_000_000_000)
    }

    /// Seconds since the recording started, on the shared clock.
    public var elapsedSeconds: Double { Double(context.now()) / 1_000_000_000 }

    /// `msr record` could not show its Dock icon: a problem; the recording goes on.
    public func dockIconNotShown() {
        tell("The Dock icon cannot be shown", error: "macOS refused the regular activation policy; stop with Ctrl-C",
             kind: .dockIconNotShown)
    }

    /// The status window's table, line and CPU use, read now: each file's
    /// size on disk and the free space in the recording folder.
    public func status() -> (rows: [RecordingStatusTable.Row], line: String, cpu: String?) {
        let clockDrift = Dictionary(uniqueKeysWithValues: clockDriftShown().map { ($0.source.id, $0.status) })
        let names = manifest.files.map(\.name) + manifest.audioFiles.map(\.name)
        let sizes = names.map { name in
            (name, (try? FileManager.default.attributesOfItem(atPath: folder.appending(path: name).path(percentEncoded: false)))?[.size] as? Int64)
        }
        let bytes = Dictionary(sizes.compactMap { name, size in size.map { (name, $0) } }, uniquingKeysWith: { $1 })
        let bytesWritten: Int64? = sizes.contains { $0.1 == nil } ? nil : bytes.values.reduce(0, +)
        let free = (try? folder.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]))?
            .volumeAvailableCapacityForImportantUsage
        return (
            RecordingStatusTable.rows(sources: tracker.sources, files: manifest.files, bytes: bytes)
                + RecordingStatusTable.audioRows(
                    sources: audioTracker.sourcesShown, files: manifest.audioFiles, bytes: bytes, clockDrift: clockDrift),
            RecordingStatusTable.line(
                elapsedSeconds: elapsedSeconds, bytesWritten: bytesWritten, files: names.count,
                freeBytes: free),
            cpu.text)
    }

    /// Runs a capture's stop; Stop waits for it until it is done.
    private func stopInProgress(_ work: @escaping @MainActor () async -> Void) {
        stopCount += 1
        let key = stopCount
        stopping[key] = Task { [weak self] in
            await work()
            self?.stopping[key] = nil
        }
    }

    /// Every stop in progress, also one that starts while waiting, is done.
    private func waitForStops() async {
        while let task = stopping.values.first { await task.value }
    }

    /// Ends every screen file and finalizes the recording manifest.
    public func stop() async -> RecordingSummary {
        if !isStopped {
            isStopped = true
            dueTask?.cancel()
            audioDueTask?.cancel()
            freeSpaceTask?.cancel()
            cpuTask?.cancel()
            sampleCPU()
            unregisterForChanges()
            for action in tracker.stopAll() { perform(action) }
            // The audio sources stop after the screen files' last mix, so
            // their guide tracks hold the sound up to the video's end (D51).
            await waitForStops()
            for action in audioTracker.stopAll() { performAudio(action) }
            await waitForStops()
            takeAudioReports()
            for line in repeats.stop(at: elapsedSeconds, started: context.started, timeZone: context.timeZone) {
                observer?.recorder(self, eventLine: line, isFailure: true)
            }
            guides.stop()
            // The recording log ends before the manifest is finalized, so its
            // failure is a problem in the final manifest (D64).
            RecorderLog.detail("finalizing the recording manifest", category: "recorder")
            RecorderLog.recording(since: nil, log: nil)
            let logFailure = recordingLog?.close()
            if let logFailure {
                tell("Cannot write the recording log \(RecordingNames.recordingLog)", error: logFailure, kind: .recordingLogNotWritten)
            }
            manifest.finalize(
                ended: Date(), timeZone: context.timeZone, cpu: cpu.manifestEntry, recordingLogWritten: logFailure == nil)
            do {
                try writeManifest()
            } catch {
                // Told by `writeManifest`; the file on disk keeps no `ended`.
                finalManifestWritten = false
            }
            if let activity { ProcessInfo.processInfo.endActivity(activity) }
            activity = nil
        }
        return RecordingSummary(
            manifest: manifest, recordingFolder: folder.path(percentEncoded: false), seconds: elapsedSeconds,
            manifestWritten: finalManifestWritten)
    }

    // MARK: Screen changes

    private func registerForChanges() {
        if readsScreens {
            CGDisplayRegisterReconfigurationCallback(screenReconfigured, Unmanaged.passUnretained(self).toOpaque())
        }
        let center = NSWorkspace.shared.notificationCenter
        notificationTokens = [
            center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.willSleep() }
            },
            center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.didWake() }
            },
        ]
        do {
            audioWatch = try AudioInputWatch { [weak self] in self?.audioInputsChanged() }
        } catch {
            tell("Changes of the audio inputs cannot be followed", error: ErrorDetail(error), kind: .audioInputsNotRead)
        }
    }

    private func unregisterForChanges() {
        if readsScreens {
            CGDisplayRemoveReconfigurationCallback(screenReconfigured, Unmanaged.passUnretained(self).toOpaque())
        }
        for token in notificationTokens { NSWorkspace.shared.notificationCenter.removeObserver(token) }
        notificationTokens = []
        audioWatch?.cancel()
        audioWatch = nil
    }

    /// macOS reported a screen change: read the screens on the next pass of the main loop, once for a burst.
    fileprivate func screensReconfigured() {
        guard !screenChangePending, !isStopped else { return }
        screenChangePending = true
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                self.screenChangePending = false
                guard !self.isStopped, let screens = self.readScreens() else { return }
                let now = self.context.now()
                let step = self.tracker.observe(screens, at: now)
                self.context.update(screens, lastScreenChange: self.tracker.lastScreenChange)
                self.apply(step)
                self.screensForAudio(screens)
            }
        }
    }

    /// The system audio's stream follows the main screen.
    private func screensForAudio(_ screens: [ConnectedScreen]) {
        applyAudio(audioTracker.observeScreens(
            mainDisplayID: screens.first(where: \.isMain)?.displayID, connected: Set(screens.map(\.displayID)),
            at: context.now()))
    }

    private func readAudioInputs() -> [AudioInputInfo]? {
        do {
            let inputs = try currentAudioInputs()
            problemsTold.cleared(.audioInputsNotRead)
            return inputs
        } catch {
            tell("The audio inputs cannot be read", error: ErrorDetail(error), kind: .audioInputsNotRead)
            return nil
        }
    }

    private func audioInputsChanged() {
        guard !isStopped, let inputs = readAudioInputs() else { return }
        applyAudio(audioTracker.observe(inputs, at: context.now()))
    }

    private func readScreens() -> [ConnectedScreen]? {
        do {
            let screens = try connectedScreens()
            RecorderLog.detail("screens: \(DetailLine.screens(screens))", category: "recorder")
            problemsTold.cleared(.screensNotRead)
            return screens
        } catch {
            tell("The screens cannot be read", error: ErrorDetail(error), kind: .screensNotRead)
            return nil
        }
    }

    private func willSleep() {
        guard !isStopped else { return }
        apply(tracker.sleep(at: context.now()))
        for action in audioTracker.sleep() { performAudio(action) }
        audioDueTask?.cancel()
    }

    private func didWake() {
        guard !isStopped else { return }
        context.rereadClocks()
        guard readsScreens else {
            apply(tracker.wake([], at: context.now()))
            applyAudio(audioTracker.wake(readAudioInputs() ?? [], at: context.now()))
            return
        }
        guard let screens = readScreens() else { return }
        let step = tracker.wake(screens, at: context.now())
        context.update(screens, lastScreenChange: tracker.lastScreenChange)
        apply(step)
        screensForAudio(screens)
        applyAudio(audioTracker.wake(readAudioInputs() ?? [], at: context.now()))
    }

    // MARK: Actions

    /// Records the events, carries out the actions, and waits for what is due next.
    private func apply(_ step: ScreenTracker.Step) {
        guard !isStopped else { return }
        manifest.events += step.events
        if !step.events.isEmpty { try? writeManifest() }
        told(step.events)
        for action in step.actions { perform(action) }
        let due = tracker.due(at: context.now())
        if !due.actions.isEmpty || !due.events.isEmpty {
            apply(due)
            return
        }
        scheduleDue()
    }

    private func scheduleDue() {
        dueTask?.cancel()
        guard let next = tracker.nextDueTime() else { return }
        let wait = max(0, next - context.now())
        dueTask = Task { [weak self] in
            try? await Task.sleep(for: .nanoseconds(wait))
            guard !Task.isCancelled, let self else { return }
            self.apply(self.tracker.due(at: self.context.now()))
        }
    }

    private func perform(_ action: ScreenTracker.Action) {
        RecorderLog.detail(
            DetailLine.action(action, names: captures.mapValues { "Screen \($0.1.number) \($0.1.name)" }), category: "recorder")
        switch action {
        case .start(let uuid, let displayID, let frameSize, let number, let name):
            captureCount += 1
            let captureNumber = captureCount
            let capture = ScreenCapture(
                uuid: uuid, displayID: displayID, number: number, name: name, frameSize: frameSize, context: context,
                guides: guides,
                onFileStarted: { [weak self] file in
                    Task { @MainActor in self?.fileStarted(file, uuid: uuid) }
                },
                onEnded: { [weak self] reason, file in
                    Task { @MainActor in self?.captureEnded(uuid: uuid, captureNumber: captureNumber, screen: name, reason: reason, file: file) }
                })
            captures[uuid] = (captureNumber, capture)
            capture.start()
            if tracker.showsAnotherScreensPicture == false { observer?.recorder(self, screenShowsAnotherScreensPicture: nil) }
        case .stop(let uuid, _):
            guard let (captureNumber, capture) = captures.removeValue(forKey: uuid) else { return }
            stopInProgress { [weak self] in
                let file = await capture.stop()
                self?.fileEnded(file, captureNumber: captureNumber, screen: capture.name, reason: nil)
            }
        }
    }

    /// The manifest lists a file from its start; a start reported after
    /// the file's end changes nothing.
    private func fileStarted(_ file: RecordingManifest.ScreenFile, uuid: String) {
        RecorderLog.detail("file started: \(file.name)", category: "recorder")
        tracker.fileStarted(uuid)
        problemsTold.cleared(.screenNotCaptured(uuid))
        guard !manifest.files.contains(where: { $0.name == file.name }) else { return }
        manifest.files.append(file)
        try? writeManifest()
    }

    /// A screen file ended, or a capture without one; its end carries its
    /// entry, so the file is listed even when its start was not reported
    /// yet. Its event and problem are recorded once per capture, also when
    /// the capture ended by itself while the recorder stopped it.
    private func fileEnded(_ end: ScreenFileEnd?, captureNumber: Int, screen: String, reason: ScreenTracker.StreamEnd?) {
        let before = manifest
        let report = endReports.record(
            captureNumber: captureNumber, reason: reason, end: end, screen: screen, at: context.now(), into: &manifest)
        if manifest != before { try? writeManifest() }
        told(Array(manifest.events.dropFirst(before.events.count)))
        if let problem = report?.problem { told(problem, ofAnEvent: report?.event != nil) }
        if let lost = report?.lostProblem { told(lost) }
        // Both end paths may report the same end: said once.
        if let end, manifest.files != before.files {
            RecorderLog.detail("file ended: \(end.file.name), \(end.file.state.rawValue)", category: "recorder")
        }
    }

    private func captureEnded(
        uuid: String, captureNumber: Int, screen: String, reason: ScreenTracker.StreamEnd, file: ScreenFileEnd?
    ) {
        fileEnded(file, captureNumber: captureNumber, screen: screen, reason: reason)
        // One the recorder already stopped, or replaced, changes nothing more.
        guard !isStopped, let (current, capture) = captures[uuid], current == captureNumber else { return }
        captures[uuid] = nil
        if reason == .showsAnotherScreen { observer?.recorder(self, screenShowsAnotherScreensPicture: capture.name) }
        let screens = readScreens() ?? []
        let step = tracker.streamEnded(uuid, reason, connected: screens, at: context.now())
        context.update(screens, lastScreenChange: tracker.lastScreenChange)
        apply(step)
        screensForAudio(screens)
        // A screen file ended by a failure is told at the failure's time,
        // so the recording manifest lists it once (D47); a screen that
        // stays listed but cannot be captured is never left unrecorded silently (N-A).
        for failure in step.events where failure.event.isFailure {
            var problem = failure.problem
            if reason == .captureSourceGone, failure.event == .screenStreamFailed {
                problem = RecordingProblem(
                    atSeconds: failure.at, problem: "Screen \(screen) cannot be captured", error: ScreenTracker.captureSourceGoneAgain)
            }
            tell(problem, kind: .screenNotCaptured(uuid), ofAnEvent: true)
        }
    }

    // MARK: Audio

    /// Records the audio events, carries out the actions, and waits for what is due next.
    private func applyAudio(_ step: AudioTracker.Step) {
        guard !isStopped else { return }
        manifest.events += step.events
        if !step.events.isEmpty { try? writeManifest() }
        told(step.events)
        for name in step.notRecordable {
            tell("The audio input \(name) cannot be recorded", error: "Core Audio does not give its UID",
                 kind: .audioInputNotRecordable(name))
        }
        for action in step.actions { performAudio(action) }
        let due = audioTracker.due(at: context.now())
        if !due.actions.isEmpty || !due.events.isEmpty {
            applyAudio(due)
            return
        }
        audioDueTask?.cancel()
        guard let next = audioTracker.nextDueTime() else { return }
        let wait = max(0, next - context.now())
        audioDueTask = Task { [weak self] in
            try? await Task.sleep(for: .nanoseconds(wait))
            guard !Task.isCancelled, let self else { return }
            self.applyAudio(self.audioTracker.due(at: self.context.now()))
        }
    }

    private func performAudio(_ action: AudioTracker.Action) {
        RecorderLog.detail("audio: \(action)", category: "recorder")
        switch action {
        case .startInput(let uid, let sourceNumber, let name):
            startAudio(.input(uid), sourceNumber: sourceNumber, name: name, source: MicrophoneSource(uid: uid))
        case .startSystemAudio:
            let number = audioCaptureCount + 1
            startAudio(.systemAudio, sourceNumber: 0, name: AudioFileDescription.systemAudioName, source: SystemAudioSource { [weak self] displayID in
                Task { @MainActor in self?.systemAudioCaptures(displayID: displayID, number: number) }
            })
        case .stop(let id):
            guard let (_, capture) = audioCaptures.removeValue(forKey: id) else { return }
            stopInProgress { await capture.stop() }
        }
    }

    private func systemAudioCaptures(displayID: UInt32, number: Int) {
        guard !isStopped, let (current, _) = audioCaptures[.systemAudio], current == number else { return }
        audioTracker.systemAudioCaptures(displayID: displayID)
    }

    private func startAudio(_ id: AudioTracker.SourceID, sourceNumber: Int, name: String, source: any AudioBufferSource) {
        audioCaptureCount += 1
        let number = audioCaptureCount
        let inbox = audioReports
        let post: @Sendable (AudioReportInbox.Report) -> Void = { [weak self] report in
            inbox.post(report)
            Task { @MainActor in self?.takeAudioReports() }
        }
        let reports = AudioCaptureReports(
            fileStarted: { file in post(.fileStarted(file, id, name: name)) },
            fileEnded: { end in post(.fileEnded(end)) },
            event: { event in post(.event(event)) },
            clockDrift: { status in post(.clockDrift(id, number: number, status)) },
            ended: { reason in post(.ended(id, number: number, name: name, reason)) })
        let capture = AudioCapture(id: id, number: sourceNumber, name: name, source: source, context: context, guides: guides, reports: reports)
        audioCaptures[id] = (number, capture)
        capture.start()
    }

    /// The audio captures' reports, in order, the one route by which they
    /// reach the manifest. Stop takes the rest, every file's end included,
    /// right before it finalizes; after that the manifest changes no more.
    private func takeAudioReports() {
        for report in audioReports.take() {
            switch report {
            case .fileStarted(let file, let id, let name): audioFileStarted(file, id: id, name: name)
            case .fileEnded(let end): audioFileEnded(end)
            case .event(let event): audioEvent(event)
            case .clockDrift(let id, let number, let status): audioClockDrift[id] = (number, status)
            case .ended(let id, let number, let name, let reason):
                audioCaptureEnded(id, number: number, name: name, reason: reason)
            }
        }
    }

    private func audioFileStarted(_ file: RecordingManifest.AudioFile, id: AudioTracker.SourceID, name: String) {
        guard manifest.state != .finalized else { return }
        RecorderLog.detail("file started: \(file.name)", category: "recorder")
        let started = audioTracker.fileStarted(id, at: Int64((file.start * 1_000_000_000).rounded()))
        problemsTold.cleared(.audioSourceFailed(name))
        let listed = manifest.audioFileStarted(file)
        if !started.isEmpty { _ = manifest.record(started) }
        if listed || !started.isEmpty { try? writeManifest() }
        told(started)
    }

    private func audioFileEnded(_ end: AudioFileEnd) {
        guard manifest.audioFileEnded(end.file) else { return }
        RecorderLog.detail("file ended: \(end.file.name), \(end.file.state.rawValue)", category: "recorder")
        _ = manifest.record(end.events)
        try? writeManifest()
        told(end.events)
        // At the file's end, so a lost end (`audio file writer fell behind`) is told once (D47).
        if end.error != nil || !end.events.isEmpty {
            let at = Int64((end.failureSeconds * 1_000_000_000).rounded())
            tell(RecordingProblem(at: at, problem: "Audio file \(end.file.name)",
                                  error: end.error?.detail ?? "its writer fell behind"),
                 kind: .audioFileFailed(end.file.name), ofAnEvent: end.toldByAnEvent)
            if let lost = end.lost {
                tell(RecordingProblem(at: at, problem: "Audio file \(end.file.name)", error: ErrorDetail(message: lost)),
                     kind: .audioFileLost(end.file.name))
            }
        }
    }

    private func audioEvent(_ event: RecordingEvent) {
        guard manifest.record([event]) else { return }
        try? writeManifest()
        told([event])
    }

    private func audioCaptureEnded(
        _ id: AudioTracker.SourceID, number: Int, name: String, reason: AudioTracker.CaptureEnd
    ) {
        guard !isStopped, let (current, _) = audioCaptures[id], current == number else { return }
        audioCaptures[id] = nil
        // Told at the time of the failure's event, so the recording manifest lists it once (D47).
        let now = context.now()
        switch reason {
        case .captureFailed(let error):
            tell(id == .systemAudio ? "The system audio failed" : "The audio input \(name) failed", error: error,
                 kind: .audioSourceFailed(name), at: now, ofAnEvent: true)
        case .writerFailed(let error):
            tell("The audio file of \(name) failed", error: error, kind: .audioSourceFailed(name), at: now, ofAnEvent: true)
        case .writerFellBehind:
            tell("The audio file of \(name) ended", error: "its writer fell behind", kind: .audioSourceFailed(name), at: now,
                 ofAnEvent: true)
        case .diskFull:
            tell("The audio file of \(name) ended", error: "the disk is full", kind: .audioSourceFailed(name), at: now,
                 ofAnEvent: true)
        case .disconnected:
            break
        }
        let step = audioTracker.captureEnded(id, reason, at: now)
        applyAudio(step)
        // A source that stays listed but is lost again and again is never left unrecorded silently.
        if reason == .disconnected, step.events.contains(where: \.event.isFailure) {
            tell(id == .systemAudio ? "The system audio cannot be captured" : "The audio input \(name) cannot be captured",
                 error: AudioTracker.sourceLostAgain(id), kind: .audioSourceFailed(name), at: now, ofAnEvent: true)
        }
    }

    // MARK: Disk

    private func checkFreeSpace() {
        guard !isStopped else { return }
        let free: Int64
        do {
            let values = try folder.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
            guard let bytes = values.volumeAvailableCapacityForImportantUsage else {
                tell("The free space in \(folder.path(percentEncoded: false)) cannot be read",
                     error: "the volume does not report its free space", kind: .freeSpaceNotRead)
                return
            }
            free = bytes
        } catch {
            tell("The free space in \(folder.path(percentEncoded: false)) cannot be read", error: ErrorDetail(error),
                 kind: .freeSpaceNotRead)
            return
        }
        problemsTold.cleared(.freeSpaceNotRead)
        let threshold = lowDiskWarningBytes()
        let isLow = Double(free) < threshold
        if isLow != isLowOnDisk {
            isLowOnDisk = isLow
            observer?.recorder(self, lowDiskSpace: isLow)
        }
        if tracker.isWaitingForRoom, !isLow {
            tracker.roomAgain()
            apply(ScreenTracker.Step())
        }
        if audioTracker.isWaitingForRoom, !isLow {
            audioTracker.roomAgain()
            applyAudio(AudioTracker.Step())
        }
    }

    /// The low disk warning threshold: `lowDiskWarningMinutes` of every
    /// screen's newest screen file and every audio source's newest audio
    /// file at the encoding rate.
    private func lowDiskWarningBytes() -> Double {
        var newestFrameSize: [String: FrameSize] = [:]
        for file in manifest.files {
            newestFrameSize[file.screenUUID] = FrameSize(width: file.frameSize[0], height: file.frameSize[1])
        }
        // By the input's Core Audio UID, the system audio's being nil: two inputs may share a name.
        var newestChannels: [String?: RecordingManifest.AudioFile.Channels] = [:]
        for file in manifest.audioFiles { newestChannels[file.audioSourceUID] = file.channels }
        let audioBytesPerHour = newestChannels.values.reduce(0.0) { total, channels in
            switch channels {
            case .mono(let count): total + DiskEstimate.audioInputFileBytesPerHour(channelCount: count)
            case .stereo: total + DiskEstimate.systemAudioFileBytesPerHour
            }
        }
        let bytesPerHour = newestFrameSize.values.reduce(audioBytesPerHour) {
            $0 + DiskEstimate.screenFileBytesPerHour(frameSize: $1, settings: settings)
        }
        return bytesPerHour * settings.lowDiskWarningMinutes / 60
    }

    // MARK: Manifest and recording log

    /// Creates the recording log and starts it with the starting situation
    /// (`RecordingLogStart`), on disk before the recording starts and only
    /// there: `msr record` printed its table and ready check already. One
    /// that cannot be created or written is a problem, and the recording goes on.
    private func startRecordingLog(app: String, readyCheckFacts: ReadyCheckFacts) {
        let context = context
        defer { RecorderLog.recording(since: { Double(context.now()) / 1_000_000_000 }, log: recordingLog) }
        do {
            let file = try AppendOnlyFile(creating: folder.appending(path: RecordingNames.recordingLog))
            recordingLog = RecordingLog(
                file: file, started: context.started, timeZone: context.timeZone, now: { context.now() },
                writing: { [weak self] failure in
                    Task { @MainActor in self?.recordingLogWriting(failure) }
                })
        } catch {
            recordingLogWriting(ErrorDetail(error))
            return
        }
        do {
            let start = try RecordingLogStart.lines(
                app: app, recordingFolder: folder.lastPathComponent,
                macOS: ProcessInfo.processInfo.operatingSystemVersionString, macModel: macModel(), settings: settings,
                facts: readyCheckFacts)
            for line in start { recordingLog?.detail(line.message, category: line.category) }
        } catch {
            recordingLogWriting(ErrorDetail(message: "the starting situation cannot be written", underlying: error))
        }
        recordingLog?.synchronize()
    }

    private func recordingLogWriting(_ failure: ErrorDetail?) {
        guard let failure else {
            problemsTold.cleared(.recordingLogNotWritten)
            return
        }
        tell("Cannot write the recording log \(RecordingNames.recordingLog)", error: failure, kind: .recordingLogNotWritten)
    }

    private func writeManifest() throws {
        do {
            try manifest.jsonData().write(to: folder.appending(path: RecordingNames.manifest), options: .atomic)
            problemsTold.cleared(.manifestNotWritten)
        } catch {
            tell("Cannot write the recording manifest", error: ErrorDetail(error), kind: .manifestNotWritten)
            throw error
        }
    }

    /// A problem for the person and the manifest's `problems`, the manifest
    /// written at once (`ProblemsTold`); one that repeats is told once until
    /// it clears. `ofAnEvent`: a failure event's line tells it on standard error (D65).
    private func tell(_ problem: String, error: ErrorDetail?, kind: ProblemKind, at time: Int64? = nil, ofAnEvent: Bool = false) {
        tell(RecordingProblem(at: time ?? context.now(), problem: problem, error: error), kind: kind, ofAnEvent: ofAnEvent)
    }

    private func tell(_ problem: RecordingProblem, kind: ProblemKind, ofAnEvent: Bool = false) {
        switch problemsTold.add(problem, kind: kind, to: &manifest) {
        case .tell(let writesManifest):
            if writesManifest { try? writeManifest() }
            told(problem, ofAnEvent: ofAnEvent)
        case .alreadyTold:
            break
        case .afterTheEnd:
            // Such as the final manifest that cannot be written, or a late report of the recording log.
            RecorderLog.error("at \(problem.at)s, after the end: \(problem.text)", category: "recorder")
            StandardErrorWriter.shared.write("Problem at the end: \(problem.text)\n")
        }
    }

    private func told(_ problem: RecordingProblem, ofAnEvent: Bool = false) {
        RecorderLog.error("at \(problem.at)s: \(problem.text)", category: "recorder")
        recordingLog?.problem(problem)
        observer?.recorder(self, problem: problem, ofAnEvent: ofAnEvent)
    }

    /// Events now in the manifest: every one to the logs, to the observer
    /// without the repeats of a failure (D65).
    private func told(_ events: [RecordingEvent]) {
        for event in events {
            repeats.tell(event, started: context.started, timeZone: context.timeZone) { line in
                RecorderLog.notice(line, category: "recorder")
                recordingLog?.event(line)
            } people: { line, isFailure in
                observer?.recorder(self, eventLine: line, isFailure: isFailure)
            }
        }
    }
}

/// Called by macOS on the main thread, under `NSApplication.run()`, for every screen change.
private func screenReconfigured(
    _ screen: CGDirectDisplayID, _ flags: CGDisplayChangeSummaryFlags, _ userInfo: UnsafeMutableRawPointer?
) {
    guard let userInfo, !flags.contains(.beginConfigurationFlag) else { return }
    let recorder = Unmanaged<Recorder>.fromOpaque(userInfo).takeUnretainedValue()
    MainActor.assumeIsolated { recorder.screensReconfigured() }
}
