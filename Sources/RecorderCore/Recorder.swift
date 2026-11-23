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

/// The devices a recording reads and opens, and the Camera permission:
/// `system` in every recording; `RecorderTests` stands in for them.
struct RecorderDevices: Sendable {
    var screens: @MainActor @Sendable () throws(DeviceReadError) -> [ConnectedScreen]
    var audioInputs: @Sendable () throws -> [AudioInputInfo]
    var audioInputSource: @Sendable (_ uid: String) -> any AudioBufferSource
    /// An audio input's input volume, nil when it has none (D69).
    var inputVolume: @Sendable (_ uid: String, _ name: String) -> (any InputVolumeControl)?
    var cameras: @Sendable () -> [CameraInfo]
    /// `format` nil: keep the format the camera runs in, as another app uses it.
    var cameraSource: @Sendable (_ uniqueID: String, _ format: CameraFormat?, _ frameSize: FrameSize) -> any CameraFrameSource
    /// Read without asking.
    var cameraPermission: @Sendable () -> CameraPermission
    /// Asks if never asked: macOS shows its prompt.
    var requestCameraPermission: @Sendable () async -> Bool
    /// Follows the audio devices' changes, calling `changed` at each.
    var watchAudioInputs: @MainActor @Sendable (_ changed: @escaping @MainActor @Sendable () -> Void) throws(DeviceReadError) -> AudioInputWatch =
        { changed throws(DeviceReadError) in try AudioInputWatch(changed: changed) }

    static let system = RecorderDevices(
        screens: connectedScreens,
        audioInputs: { try currentAudioInputs() },
        audioInputSource: { MicrophoneSource(uid: $0) },
        inputVolume: { CoreAudioInputVolume(uid: $0, name: $1) },
        cameras: currentCameras,
        cameraSource: { CameraSource(uniqueID: $0, format: $1, frameSize: $2) },
        cameraPermission: readCameraPermission,
        requestCameraPermission: askForCameraPermission)
}

/// One recording: claims its recording folder, keeps its recording
/// manifest, keeps the Mac awake, follows the screens as they come, go
/// and change, with one screen capture per screen file, the cameras, with
/// one camera capture per camera file (D74), and the audio
/// sources, with one audio capture per source, their level meters and the
/// audio inputs' input volume, and its guide tracks.
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
    /// Whether the recording may record a camera: the camera mode records
    /// some and the recording resolution records video. Without, it never
    /// lists a camera or asks for the Camera permission.
    private let readsCameras: Bool
    private(set) var cameraTracker: CameraTracker
    /// The running capture of each camera, by its unique ID, with its number among all captures of the recording.
    private var cameraCaptures: [String: (Int, CameraCapture)] = [:]
    private var cameraDueTask: Task<Void, Never>?
    /// The Camera permission was asked for while recording; it is asked once.
    private var cameraPermissionRequested = false
    /// The cameras the camera mode would record while the Camera permission is denied, for the status window.
    private var camerasWithoutPermission: [CameraInfo] = []
    /// The screens and audio inputs as last read, for the status window's details.
    private var screensRead: [ConnectedScreen] = []
    /// The audio inputs' latest sound and the lags counted so far per audio file, for their delays (D77).
    let audioDelays = AudioDelayFeed()
    private var delayLags = AudioDelay.Lags()
    /// The camera captures whose end was reported to the camera tracker.
    private var cameraCapturesGone: Set<Int> = []
    private var delayTask: Task<Void, Never>?
    private var guideTrackMembership = GuideTrackMembership()
    private var audioInputsRead: [AudioInputInfo] = []
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
    private var cameraWatch: CameraWatch?
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
    /// Internal, so a test can see which sources a guide track mixes.
    let guides: GuideTrackFeed
    private var clockDriftDetailSchedule = ClockDriftDetailSchedule()
    /// Nil when it could not be created: that is a problem, and the recording goes on.
    private var recordingLog: RecordingLog?
    private var cpu = CPUUsage()
    private var cpuTask: Task<Void, Never>?
    private let devices: RecorderDevices
    private let cameraFrameWatch: CameraFrameWatch
    /// The input volume of each audio input with a running capture, by its UID (D69).
    private var inputVolumes: [String: InputVolumeFollow] = [:]
    private var inputVolumeTask: Task<Void, Never>?

    /// An audio input's input volume while its capture runs: read when Core
    /// Audio reports a change and every `inputVolumeReadInterval`, and told
    /// once it held still (`InputVolumeChanges`).
    private struct InputVolumeFollow {
        let control: any InputVolumeControl
        let name: String
        /// The number of the capture it follows, among all audio captures.
        let captureNumber: Int
        var changes: InputVolumeChanges
        /// As read last; nil until one could be read.
        var latest: Double?
        var dueTask: Task<Void, Never>?
    }

    /// Starts a recording into a new recording folder in the settings' output
    /// folder; the recording log starts with the ready check's facts.
    public convenience init(
        settings: Settings, homeFolder: URL, app: String, readyCheckFacts: ReadyCheckFacts, observer: any RecorderObserver
    ) throws(RecorderStartError) {
        try self.init(
            settings: settings, homeFolder: homeFolder, app: app, readyCheckFacts: readyCheckFacts, observer: observer,
            devices: .system)
    }

    init(
        settings: Settings, homeFolder: URL, app: String, readyCheckFacts: ReadyCheckFacts, observer: any RecorderObserver,
        devices: RecorderDevices, cameraFrameWatch: CameraFrameWatch = CameraFrameWatch()
    ) throws(RecorderStartError) {
        self.devices = devices
        self.cameraFrameWatch = cameraFrameWatch
        let readsScreens = ReadyCheck.needsScreenRecording(settings)
        let screens: [ConnectedScreen]
        do {
            screens = readsScreens ? try devices.screens() : []
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
        screensRead = screens
        self.readsScreens = readsScreens
        readsCameras = settings.effectiveCameraMode != .none && settings.effectiveResolution.recordsScreens
        cameraTracker = CameraTracker(settings: settings)
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
        if readsCameras { applyCameras(cameraTracker.begin(readCameras(), at: context.now())) }
        applyAudio(audioTracker.begin(
            inputs: readAudioInputs() ?? [], mainDisplayID: screens.first(where: \.isMain)?.displayID,
            screens: Set(screens.map(\.displayID)), at: context.now()))
        freeSpaceTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: RecorderValues.freeSpaceCheckInterval)
                self?.checkFreeSpace()
            }
        }
        delayTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: AudioDelay.interval)
                guard !Task.isCancelled else { return }
                await self?.measureAudioDelays()
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

    /// The status window's problem lines, read now (D78).
    public func problemLines() -> [ProblemLine] { problemsTold.lines(now: context.now()) }

    /// `msr record` could not show its Dock icon: a problem; the recording goes on.
    public func dockIconNotShown() {
        tell("The Dock icon cannot be shown", error: "macOS refused the regular activation policy; stop with Ctrl-C",
             kind: .dockIconNotShown)
    }

    /// The status window's table, line and CPU use, read now: each file's
    /// size on disk and the free space in the recording folder.
    public func status() -> (rows: [RecordingStatusTable.Row], line: String, cpu: String?) {
        let clockDrift = Dictionary(uniqueKeysWithValues: clockDriftShown().map { ($0.source.id, $0.status) })
        let names = manifest.files.map(\.name) + manifest.cameraFiles.map(\.name) + manifest.audioFiles.map(\.name)
        let sizes = names.map { name in
            (name, (try? FileManager.default.attributesOfItem(atPath: folder.appending(path: name).path(percentEncoded: false)))?[.size] as? Int64)
        }
        let bytes = Dictionary(sizes.compactMap { name, size in size.map { (name, $0) } }, uniquingKeysWith: { $1 })
        let bytesWritten: Int64? = sizes.contains { $0.1 == nil } ? nil : bytes.values.reduce(0, +)
        let free = (try? volumeFreeBytes(of: folder)) ?? nil
        return (
            statusDetails(screenRows: RecordingStatusTable.rows(sources: tracker.sources, files: manifest.files, bytes: bytes))
                + statusDetails(cameraRows: RecordingStatusTable.cameraRows(
                    sources: cameraTracker.sources, files: manifest.cameraFiles, bytes: bytes))
                + zip(RecordingStatusTable.cameraRowsWithoutPermission(camerasWithoutPermission), camerasWithoutPermission).map { row, camera in
                    var row = row
                    row.details = SourceDetails.camera(label: row.source.text, camera, settings: settings)
                    return row
                }
                + statusDetails(audioRows: RecordingStatusTable.audioRows(
                    sources: audioTracker.sourcesShown, files: manifest.audioFiles, bytes: bytes, clockDrift: clockDrift),
                    clockDrift: clockDrift),
            RecordingStatusTable.line(
                elapsedSeconds: elapsedSeconds, bytesWritten: bytesWritten, files: names.count,
                freeBytes: free),
            cpu.text)
    }

    /// The screen rows with their details: the screen as last read, the running file's lateness.
    private func statusDetails(screenRows rows: [RecordingStatusTable.Row]) -> [RecordingStatusTable.Row] {
        zip(rows, tracker.sources).map { row, source in
            var row = row
            let recordsAt: FrameSize? = if case .recording(let size) = source.state { size } else { nil }
            let details = screensRead.first { $0.uuid == source.uuid }.map { screen in
                SourceDetails.screen(
                    label: row.source.text, looksLike: screen.pointSize, drawnAt: nil, recordsAt: recordsAt, refreshRate: nil,
                    displayID: screen.displayID, isMain: screen.isMain)
            } ?? row.source.text
            row.details = ([details] + SourceDetails.live(lateness: captures[source.uuid]?.1.lateness())).joined(separator: "\n")
            return row
        }
    }

    /// The camera rows with their details: the camera as last read, the running file's lateness and its stall.
    private func statusDetails(cameraRows rows: [RecordingStatusTable.Row]) -> [RecordingStatusTable.Row] {
        zip(rows, cameraTracker.sources).map { row, source in
            var row = row
            let details = cameraTracker.recordedReading(of: source.uniqueID).map {
                SourceDetails.camera(label: row.source.text, $0, settings: settings)
            } ?? row.source.text
            let isStalled: Bool = if case .stalled = source.state { true } else { false }
            let live = SourceDetails.live(lateness: cameraCaptures[source.uniqueID]?.1.lateness(), isStalled: isStalled)
            row.details = ([details] + live).joined(separator: "\n")
            return row
        }
    }

    /// The audio rows with their details: the input as last read, its input volume as followed, the clock drift.
    private func statusDetails(
        audioRows rows: [RecordingStatusTable.Row], clockDrift: [AudioTracker.SourceID: ClockDriftCorrection.Status]
    ) -> [RecordingStatusTable.Row] {
        rows.map { row in
            var row = row
            guard let id = row.audioSource else { return row }
            let details: String = switch id {
            case .systemAudio: SourceDetails.systemAudio(label: row.source.text)
            case .input(let uid):
                audioInputsRead.first { $0.uid == uid }.map { input in
                    var input = input
                    if let follow = inputVolumes[uid] {
                        input.inputVolume = InputVolumeReading(value: follow.latest, isSettable: follow.control.isSettable)
                    }
                    return SourceDetails.audioInput(label: row.source.text, input)
                } ?? row.source.text
            }
            row.details = ([details] + SourceDetails.live(clockDrift: clockDrift[id])).joined(separator: "\n")
            return row
        }
    }

    /// The level meter of each audio source with a running capture, read
    /// now, and the input volume of each audio input whose volume can be set (D69).
    public func meters() -> (levels: [AudioTracker.SourceID: AudioLevel], inputVolumes: [AudioTracker.SourceID: Double]) {
        let now = context.now()
        let levels = audioCaptures.mapValues { $0.1.readLevel(at: now) }
        let volumes = inputVolumes.compactMap { uid, follow in
            follow.control.isSettable ? follow.latest.map { (AudioTracker.SourceID.input(uid), $0) } : nil
        }
        return (levels, Dictionary(uniqueKeysWithValues: volumes))
    }

    /// Sets an audio input's own input volume, 0 to 1, for every app on the
    /// Mac (D69); the change is told like any other once it held still. One
    /// that cannot be set is a problem.
    public func setInputVolume(_ id: AudioTracker.SourceID, to volume: Double) {
        guard case .input(let uid) = id, let follow = inputVolumes[uid], follow.control.isSettable else { return }
        do throws(InputVolumeError) {
            try follow.control.set(volume)
            problemsTold.cleared(.inputVolumeNotSet(follow.name), at: context.now())
        } catch {
            tell("The input volume of \(follow.name) cannot be set", error: ErrorDetail(message: error.description),
                 kind: .inputVolumeNotSet(follow.name))
        }
        readInputVolume(uid)
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
            cameraDueTask?.cancel()
            audioDueTask?.cancel()
            freeSpaceTask?.cancel()
            cpuTask?.cancel()
            delayTask?.cancel()
            stopReadingInputVolumes()
            sampleCPU()
            unregisterForChanges()
            for action in tracker.stopAll() { perform(action) }
            for action in cameraTracker.stopAll() { performCamera(action) }
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
            if finalManifestWritten { await writeTimelineFile() }
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
        if readsCameras { cameraWatch = CameraWatch { [weak self] in self?.camerasChanged() } }
        do {
            audioWatch = try devices.watchAudioInputs { [weak self] in self?.audioInputsChanged() }
        } catch {
            tell("Changes of the audio inputs cannot be followed", error: ErrorDetail(error), kind: .audioInputChangesNotFollowed)
        }
    }

    private func unregisterForChanges() {
        if readsScreens {
            CGDisplayRemoveReconfigurationCallback(screenReconfigured, Unmanaged.passUnretained(self).toOpaque())
        }
        for token in notificationTokens { NSWorkspace.shared.notificationCenter.removeObserver(token) }
        notificationTokens = []
        cameraWatch?.cancel()
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
            let inputs = try devices.audioInputs()
            audioInputsRead = inputs
            problemsTold.cleared(.audioInputsNotRead, at: context.now())
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
            let screens = try devices.screens()
            screensRead = screens
            RecorderLog.detail("screens: \(DetailLine.screens(screens))", category: "recorder")
            problemsTold.cleared(.screensNotRead, at: context.now())
            return screens
        } catch {
            tell("The screens cannot be read", error: ErrorDetail(error), kind: .screensNotRead)
            return nil
        }
    }

    func willSleep() {
        guard !isStopped else { return }
        apply(tracker.sleep(at: context.now()))
        for action in cameraTracker.sleep() { performCamera(action) }
        cameraDueTask?.cancel()
        for action in audioTracker.sleep() { performAudio(action) }
        audioDueTask?.cancel()
    }

    func didWake() {
        guard !isStopped else { return }
        context.rereadClocks()
        if readsCameras { applyCameras(cameraTracker.wake(readCameras(), at: context.now())) }
        guard readsScreens else {
            apply(tracker.wake([], at: context.now()))
            applyAudio(audioTracker.wake(readAudioInputs() ?? [], at: context.now()))
            return
        }
        guard let screens = readScreens() else {
            apply(tracker.wakeUnread(at: context.now()))
            // The audio's wake does not depend on the screens, only the system audio's main screen does.
            applyAudio(audioTracker.wake(readAudioInputs() ?? [], at: context.now()))
            return
        }
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
        for screen in tracker.sources where screen.state == .disconnected {
            problemsTold.cleared(.screenNotCaptured(screen.uuid), at: context.now(), ending: .disconnected)
        }
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
                    Task { @MainActor in self?.captureEnded(uuid: uuid, captureNumber: captureNumber, screen: name, number: number, reason: reason, file: file) }
                })
            captures[uuid] = (captureNumber, capture)
            capture.start()
            if tracker.showsAnotherScreensPicture == false { observer?.recorder(self, screenShowsAnotherScreensPicture: nil) }
        case .stop(let uuid, _):
            guard let (captureNumber, capture) = captures.removeValue(forKey: uuid) else { return }
            stopInProgress { [weak self] in
                let file = await capture.stop()
                self?.fileEnded(file, captureNumber: captureNumber, screen: capture.name, number: capture.number, uuid: uuid, reason: nil)
            }
        }
    }

    /// The manifest lists a file from its start; a start reported after
    /// the file's end changes nothing.
    private func fileStarted(_ file: RecordingManifest.ScreenFile, uuid: String) {
        RecorderLog.detail("file started: \(file.name)", category: "recorder")
        tracker.fileStarted(uuid)
        problemsTold.cleared(.screenNotCaptured(uuid), at: context.now())
        guard !manifest.files.contains(where: { $0.name == file.name }) else { return }
        manifest.files.append(file)
        try? writeManifest()
    }

    /// A screen file ended, or a capture without one; its end carries its
    /// entry, so the file is listed even when its start was not reported
    /// yet. Its event and problem are recorded once per capture, also when
    /// the capture ended by itself while the recorder stopped it.
    private func fileEnded(
        _ end: VideoFileEnd<RecordingManifest.ScreenFile>?, captureNumber: Int, screen: String, number: Int, uuid: String,
        reason: VideoStreamEnd?
    ) {
        let newer = end.flatMap { end in manifest.files.filter { $0.screenUUID == uuid && $0.start > end.file.start }.map(\.start).min() }
        videoFileEnded(
            end, captureNumber: captureNumber, source: screen, label: "\(number) \(screen)", reason: reason,
            notCaptured: .screenNotCaptured(uuid), newerFileStart: newer)
    }

    private func videoFileEnded(
        _ end: VideoFileEnd<RecordingManifest.CameraFile>?, captureNumber: Int, source: String, reason: VideoStreamEnd?, uniqueID: String
    ) {
        let newer = end.flatMap { end in
            manifest.cameraFiles.filter { $0.cameraUniqueID == uniqueID && $0.start > end.file.start }.map(\.start).min()
        }
        videoFileEnded(
            end, captureNumber: captureNumber, source: source, label: cameraLabel(uniqueID, name: source), reason: reason,
            notCaptured: .cameraNotCaptured(uniqueID), newerFileStart: newer)
    }

    /// A screen file or a camera file ended, as `fileEnded` says; `source` is the screen's or the camera's name,
    /// `notCaptured` its kind of a failure; `newerFileStart`, a newer file of the source that started already:
    /// a failure of this one is over when told (D78).
    private func videoFileEnded<File>(
        _ end: VideoFileEnd<File>?, captureNumber: Int, source: String, label: String, reason: VideoStreamEnd?, notCaptured: ProblemKind,
        newerFileStart: Double?
    ) {
        let before = manifest
        let report = endReports.record(
            captureNumber: captureNumber, reason: reason, end: end, source: source, at: context.now(), into: &manifest)
        if manifest != before { try? writeManifest() }
        told(Array(manifest.events.dropFirst(before.events.count)))
        if let report, let problem = report.problem {
            let kind = report.problemKind(notCaptured: notCaptured)
            let over = gone(kind) ?? newerFileStart.map { (Int64(($0 * 1_000_000_000).rounded()), .recovered) }
            problemsTold.show(problem, kind: kind, source: label, endedAt: over?.at, ending: over?.ending ?? .recovered)
            told(problem, ofAnEvent: report.event != nil)
        }
        if let report, let lost = report.lostProblem {
            problemsTold.show(lost, kind: report.lostKind)
            told(lost)
        }
        // Both end paths may report the same end: said once.
        if let end, manifest[keyPath: File.manifestFiles] != before[keyPath: File.manifestFiles] {
            RecorderLog.detail("file ended: \(end.file.name), \(end.file.state.rawValue)", category: "recorder")
        }
    }

    private func captureEnded(
        uuid: String, captureNumber: Int, screen: String, number: Int, reason: VideoStreamEnd,
        file: VideoFileEnd<RecordingManifest.ScreenFile>?
    ) {
        fileEnded(file, captureNumber: captureNumber, screen: screen, number: number, uuid: uuid, reason: reason)
        // One the recorder already stopped, or replaced, changes nothing more.
        guard !isStopped, let (current, capture) = captures[uuid], current == captureNumber else { return }
        captures[uuid] = nil
        if reason == .showsAnotherScreen { observer?.recorder(self, screenShowsAnotherScreensPicture: capture.name) }
        let screens = readScreens() ?? []
        let step = tracker.streamEnded(uuid, reason, connected: screens, at: context.now())
        context.update(screens, lastScreenChange: tracker.lastScreenChange)
        apply(step)
        screensForAudio(screens)
        // A screen file ended by a failure is told at the failure's time (D47); a file whose writer also
        // reported an error is a second problem, the file's (`fileEnded`); a screen that
        // stays listed but cannot be captured is never left unrecorded silently (N-A).
        for failure in step.events where failure.event.isFailure {
            var problem = failure.problem
            if reason == .captureSourceGone, failure.event == .screenStreamFailed {
                problem = RecordingProblem(
                    atSeconds: failure.at, problem: "Screen \(screen) cannot be captured", error: ScreenTracker.captureSourceGoneAgain)
            }
            let over = gone(.screenNotCaptured(uuid))
            tell(problem, kind: .screenNotCaptured(uuid), source: "\(number) \(screen)", endedAt: over?.at,
                 ending: over?.ending ?? .recovered, ofAnEvent: true)
        }
    }

    // MARK: Cameras

    /// The cameras for the tracker. When one of them is to be recorded,
    /// the Camera permission decides: never asked, it is asked for now and
    /// the cameras are read again at the answer; denied, the problem is
    /// told once. Without it the tracker sees no camera.
    private func readCameras() -> [CameraInfo] {
        var cameras: [CameraInfo] = []
        let readTook = ContinuousClock().measure { cameras = devices.cameras() }
        RecorderLog.detail("cameras, read in \(DetailLine.milliseconds(readTook)): \(DetailLine.cameras(cameras, resolution: settings.effectiveResolution, limitCameras: settings.limitCameras))", category: "recorder")
        camerasWithoutPermission = []
        guard cameras.contains(where: { CameraTracker.records($0, settings: settings) }) else { return cameras }
        switch devices.cameraPermission() {
        case .granted:
            problemsTold.cleared(.cameraPermissionMissing, at: context.now())
            return cameras
        case .notAsked:
            if !cameraPermissionRequested {
                cameraPermissionRequested = true
                let request = devices.requestCameraPermission
                Task { [weak self] in
                    _ = await request()
                    self?.camerasChanged()
                }
            }
            return []
        case .denied:
            camerasWithoutPermission = cameras.filter { CameraTracker.records($0, settings: settings) }
            tell("The Camera permission is missing",
                 error: "no camera is recorded; allow it in System Settings › Privacy & Security › Camera",
                 kind: .cameraPermissionMissing)
            return []
        }
    }

    /// AVFoundation reported a camera connected, disconnected, suspended or resumed, or the Camera permission was answered.
    func camerasChanged() {
        guard readsCameras, !isStopped else { return }
        applyCameras(cameraTracker.observe(readCameras(), at: context.now()))
    }

    /// Records the camera events, carries out the actions, and waits for what is due next.
    private func applyCameras(_ step: CameraTracker.Step) {
        guard !isStopped else { return }
        for camera in cameraTracker.sources where camera.state == .disconnected {
            problemsTold.cleared(.cameraNotCaptured(camera.uniqueID), at: context.now(), ending: .disconnected)
            problemsTold.cleared(.cameraStalled(camera.uniqueID), at: context.now(), ending: .disconnected)
        }
        manifest.events += step.events
        if !step.events.isEmpty { try? writeManifest() }
        told(step.events)
        for action in step.actions { performCamera(action) }
        let due = cameraTracker.due(at: context.now())
        if !due.actions.isEmpty || !due.events.isEmpty {
            applyCameras(due)
            return
        }
        cameraDueTask?.cancel()
        guard let next = cameraTracker.nextDueTime() else { return }
        let wait = max(0, next - context.now())
        cameraDueTask = Task { [weak self] in
            try? await Task.sleep(for: .nanoseconds(wait))
            guard !Task.isCancelled, let self else { return }
            self.applyCameras(self.cameraTracker.due(at: self.context.now()))
        }
    }

    private func performCamera(_ action: CameraTracker.Action) {
        RecorderLog.detail(
            DetailLine.cameraAction(action, names: cameraCaptures.mapValues { "Camera \($0.1.number) \($0.1.name)" }),
            category: "recorder")
        switch action {
        case .start(let uniqueID, let format, let setsFormat, let frameSize, let number, let name, let isContinuity):
            captureCount += 1
            let captureNumber = captureCount
            let capture = CameraCapture(
                uniqueID: uniqueID, number: number, name: name, frameSize: frameSize, isContinuity: isContinuity,
                source: devices.cameraSource(uniqueID, setsFormat ? format : nil, frameSize), context: context, guides: guides,
                frameWatch: cameraFrameWatch,
                onFileStarted: { [weak self] file in
                    Task { @MainActor in self?.cameraFileStarted(file, uniqueID: uniqueID) }
                },
                onStalled: { [weak self] in
                    Task { @MainActor in self?.cameraStalled(uniqueID: uniqueID, captureNumber: captureNumber) }
                },
                onStallEnded: { [weak self] length in
                    Task { @MainActor in self?.cameraStallEnded(uniqueID: uniqueID, captureNumber: captureNumber, length: length) }
                },
                onFormatTakenOver: { [weak self] in
                    Task { @MainActor in self?.cameraFormatTakenOver(uniqueID: uniqueID, captureNumber: captureNumber) }
                },
                checksOrientation: setsFormat && cameraTracker.recordedReading(of: uniqueID)?.otherOrientation(of: format) != nil,
                onPictureInOtherOrientation: { [weak self] beforeItsFile in
                    Task { @MainActor in
                        self?.cameraPictureInOtherOrientation(uniqueID: uniqueID, captureNumber: captureNumber, beforeItsFile: beforeItsFile)
                    }
                },
                onEnded: { [weak self] reason, file in
                    Task { @MainActor in
                        self?.cameraCaptureEnded(uniqueID: uniqueID, captureNumber: captureNumber, camera: name, reason: reason, file: file)
                    }
                })
            cameraCaptures[uniqueID] = (captureNumber, capture)
            capture.start()
        case .stop(let uniqueID):
            guard let (captureNumber, capture) = cameraCaptures.removeValue(forKey: uniqueID) else { return }
            problemsTold.cleared(.cameraStalled(uniqueID), at: context.now(), ending: .stopped)
            stopInProgress { [weak self] in
                let file = await capture.stop()
                guard let self else { return }
                let readAgain = cameraCaptureGone(uniqueID, captureNumber: captureNumber)
                videoFileEnded(file, captureNumber: captureNumber, source: capture.name, reason: nil, uniqueID: uniqueID)
                if readAgain { camerasChanged() }
            }
        }
    }

    /// As a screen file's start (`fileStarted`).
    private func cameraFileStarted(_ file: RecordingManifest.CameraFile, uniqueID: String) {
        RecorderLog.detail("file started: \(file.name)", category: "recorder")
        cameraTracker.fileStarted(uniqueID)
        problemsTold.cleared(.cameraNotCaptured(uniqueID), at: context.now())
        problemsTold.cleared(.cameraStalled(uniqueID), at: context.now())
        guard !manifest.cameraFiles.contains(where: { $0.name == file.name }) else { return }
        manifest.cameraFiles.append(file)
        try? writeManifest()
    }

    /// A stall of the running capture: its event, and the problem told once per stall.
    private func cameraStalled(uniqueID: String, captureNumber: Int) {
        guard !isStopped, cameraCaptures[uniqueID]?.0 == captureNumber else { return }
        let step = cameraTracker.stalled(uniqueID, at: context.now())
        applyCameras(step)
        for stalled in step.events { tell(stalled.problem, kind: .cameraStalled(uniqueID), source: stalled.camera.map { cameraLabel(uniqueID, name: $0) },
                                                ofAnEvent: true) }
    }

    private func cameraStallEnded(uniqueID: String, captureNumber: Int, length: Int64) {
        guard !isStopped, cameraCaptures[uniqueID]?.0 == captureNumber else { return }
        problemsTold.cleared(.cameraStalled(uniqueID), at: context.now(), length: length)
        applyCameras(cameraTracker.stallEnded(uniqueID, length: length, at: context.now()))
    }

    /// Another app changed the format of the running capture's camera: read
    /// the cameras for its format, the new file following after the settle time.
    private func cameraFormatTakenOver(uniqueID: String, captureNumber: Int) {
        guard !isStopped, cameraCaptures[uniqueID]?.0 == captureNumber else { return }
        cameraTracker.formatTakenOver(uniqueID, at: context.now())
        camerasChanged()
    }

    /// The running capture's picture is boxed in the other orientation: the camera turns (D76).
    private func cameraPictureInOtherOrientation(uniqueID: String, captureNumber: Int, beforeItsFile: Bool) {
        guard !isStopped, cameraCaptures[uniqueID]?.0 == captureNumber else { return }
        applyCameras(cameraTracker.pictureInOtherOrientation(uniqueID, beforeItsFile: beforeItsFile, at: context.now()))
    }

    /// Now and `.disconnected` when the source of a failure `kind` is gone: its line ends at once (D78).
    private func gone(_ kind: ProblemKind) -> (at: Int64, ending: ProblemsTold.Ending)? {
        let isGone = switch kind {
        case .screenNotCaptured(let uuid): tracker.sources.first { $0.uuid == uuid }?.state == .disconnected
        case .cameraNotCaptured(let uniqueID): cameraTracker.sources.first { $0.uniqueID == uniqueID }?.state == .disconnected
        default: false
        }
        return isGone ? (context.now(), .disconnected) : nil
    }

    /// A camera capture is over, reported once though both end paths may report it: its camera's
    /// readings count another app's use again (D74, D76). True when no capture of ours is left: the
    /// caller that got it reads the cameras again, as a reading meanwhile was not taken.
    private func cameraCaptureGone(_ uniqueID: String, captureNumber: Int) -> Bool {
        cameraCapturesGone.insert(captureNumber).inserted && cameraTracker.captureEnded(uniqueID)
    }

    /// A camera's source in its problem lines, with its number as its files have it: `2 BRIO`.
    private func cameraLabel(_ uniqueID: String, name: String) -> String {
        cameraTracker.sources.first { $0.uniqueID == uniqueID }?.number.map { "\($0) \(name)" } ?? name
    }

    /// As a screen capture's end by itself (`captureEnded`). Internal, so a test can deliver a late end
    /// report of a capture, as the stand-in cameras cannot fail a file's writer.
    func cameraCaptureEnded(
        uniqueID: String, captureNumber: Int, camera: String, reason: VideoStreamEnd, file: VideoFileEnd<RecordingManifest.CameraFile>?
    ) {
        let readAgain = cameraCaptureGone(uniqueID, captureNumber: captureNumber)
        videoFileEnded(file, captureNumber: captureNumber, source: camera, reason: reason, uniqueID: uniqueID)
        guard !isStopped, let (current, _) = cameraCaptures[uniqueID], current == captureNumber else {
            // A capture the recorder stops: reported here first, the stop path no longer reads the cameras.
            if readAgain { camerasChanged() }
            return
        }
        cameraCaptures[uniqueID] = nil
        // No second read: `streamEnded` observes this fresh reading, taken once our capture no longer counts.
        let step = cameraTracker.streamEnded(uniqueID, reason, connected: readCameras(), at: context.now())
        applyCameras(step)
        problemsTold.cleared(.cameraStalled(uniqueID), at: context.now(), ending: .stopped)
        for failure in step.events where failure.event.isFailure {
            var problem = failure.problem
            if reason == .captureSourceGone, failure.event == .cameraStreamFailed {
                problem = RecordingProblem(
                    atSeconds: failure.at, problem: "Camera \(camera) cannot be captured", error: CameraTracker.captureSourceGoneAgain)
            }
            let over = gone(.cameraNotCaptured(uniqueID))
            tell(problem, kind: .cameraNotCaptured(uniqueID), source: cameraLabel(uniqueID, name: camera), endedAt: over?.at, ending: over?.ending ?? .recovered,
                 ofAnEvent: true)
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
            startAudio(.input(uid), sourceNumber: sourceNumber, name: name, source: devices.audioInputSource(uid))
        case .startSystemAudio:
            let number = audioCaptureCount + 1
            startAudio(.systemAudio, sourceNumber: 0, name: AudioFileDescription.systemAudioName, source: SystemAudioSource { [weak self] displayID in
                Task { @MainActor in self?.systemAudioCaptures(displayID: displayID, number: number) }
            })
        case .stop(let id):
            guard let (number, capture) = audioCaptures.removeValue(forKey: id) else { return }
            unfollowInputVolume(id, captureNumber: number)
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
            noAudio: { isNoAudio in post(.noAudio(id, number: number, isNoAudio)) },
            ended: { reason in post(.ended(id, number: number, name: name, reason)) })
        var control: (any InputVolumeControl)?
        if case .input(let uid) = id {
            control = devices.inputVolume(uid, name)
            followInputVolume(uid, name: name, control: control, captureNumber: number)
        }
        let capture = AudioCapture(
            id: id, number: sourceNumber, name: name, source: source, context: context, guides: guides, reports: reports,
            inputVolume: { [control] in control?.read() }, delays: audioDelays)
        audioCaptures[id] = (number, capture)
        capture.start()
    }

    // MARK: Audio delay

    /// Measures each audio input file being written against the reference
    /// microphone over their latest common window, off the main thread, and
    /// keeps the counted windows' lags; a file's delay is their median, normalized (D77). Nothing after Stop.
    func measureAudioDelays() async {
        guard !isStopped else { return }
        let writing = manifest.audioFiles.filter { $0.end == nil && $0.audioSourceUID != nil }
        guard let reference = delayReference(among: Set(writing.compactMap(\.audioSourceUID))),
              let referenceEnd = audioDelays.endIndex(of: reference) else { return }
        let count = AudioDelay.windowSeconds * AudioDelay.sampleRate
        let jobs = writing.compactMap { file -> (file: String, reference: [Float], other: [Float])? in
            guard let uid = file.audioSourceUID, uid != reference, let end = audioDelays.endIndex(of: uid).map({ min($0, referenceEnd) }),
                  Double(end - Int64(count)) / Double(AudioDelay.sampleRate) >= file.start,
                  let other = audioDelays.window(of: uid, endingAt: end, count: count),
                  let referenceWindow = audioDelays.window(of: reference, endingAt: end, count: count) else { return nil }
            return (file.name, referenceWindow, other)
        }
        guard !jobs.isEmpty else { return }
        let windows = await Task.detached(priority: .utility) {
            jobs.map { ($0.file, AudioDelay.window(reference: $0.reference, other: $0.other)) }
        }.value
        guard !isStopped, let referenceFile = writing.first(where: { $0.audioSourceUID == reference })?.name else { return }
        let before = manifest.audioFiles.map(\.measuredDelay)
        for case let (file, window?) in windows where window.counts {
            RecorderLog.detail("\(file): lag \(AudioDelay.text(window.lag)), clarity \(Int(window.clarity.rounded()))", category: "recorder")
            // Against another reference's file its delay no longer holds: the one time a measured value goes back to null.
            if let measuredAgainst = delayLags.reference(of: file), measuredAgainst != referenceFile {
                _ = manifest.audioDelayMeasured(nil, file: file)
            }
            delayLags.add(window.lag, file: file, reference: referenceFile)
            guideTrackMembership.add(window.lag, file: file, reference: referenceFile)
        }
        let membership = guideTrackMembership.update(writing: Set(writing.map(\.name)), reference: referenceFile)
        for (file, offset) in membership.leaving.sorted(by: { $0.key < $1.key }) { leaveTheGuideTrack(file: file, offset: offset) }
        for file in membership.rejoining.sorted() { rejoinTheGuideTrack(file: file) }
        var delays = delayLags.delays(reference: referenceFile)
        // The reference's file once shifted keeps a value: 0 when it is the earliest again.
        if delays[referenceFile] == nil, manifest.audioFiles.first(where: { $0.name == referenceFile })?.measuredDelay != nil {
            delays[referenceFile] = 0
        }
        for (file, delay) in delays { _ = manifest.audioDelayMeasured(delay, file: file) }
        if manifest.audioFiles.map(\.measuredDelay) != before { try? writeManifest() }
    }

    /// An audio input's file out of sync with the staying group leaves the "Audio inputs" guide track, its own
    /// file unchanged; its event and problem once its capture took it out (D79). By design: no Dock bounce,
    /// badge or count. Internal, so a test can ask for a leave its capture does not carry out.
    func leaveTheGuideTrack(file name: String, offset: Double) {
        guard let file = manifest.audioFiles.first(where: { $0.name == name }), let uid = file.audioSourceUID,
              audioCaptures[.input(uid)]?.1.leaveTheGuideTrack(file: name) == true else { return }
        var event = RecordingEvent(at: context.now(), event: .audioInputLeftTheGuideTrack, audioSource: file.audioSource)
        event.offset = (offset * 10_000).rounded() / 10_000
        guard manifest.record([event]) else { return }
        try? writeManifest()
        told([event])
        let number = audioTracker.sourcesShown.first { $0.id == .input(uid) }?.number
        let problem = RecordingProblem(
            atSeconds: event.at, problem: event.problem.problem,
            error: ErrorDetail(message: event.event.rawValue, underlying: [ErrorDetail(message: AudioDelay.text(offset))]))
        tell(problem, kind: .audioInputOutOfTheGuideTrack(uid), source: number.map { "Audio \($0) \(file.audioSource)" } ?? file.audioSource,
             note: AudioDelay.text(offset), ofAnEvent: true, notifies: false)
    }

    /// A file that left the guide track rejoins it; its line turns to the past (D79).
    private func rejoinTheGuideTrack(file name: String) {
        guard let file = manifest.audioFiles.first(where: { $0.name == name }), let uid = file.audioSourceUID,
              audioCaptures[.input(uid)]?.1.rejoinTheGuideTrack(file: name) == true else { return }
        problemsTold.cleared(.audioInputOutOfTheGuideTrack(uid), at: context.now())
    }

    /// The default microphone when it is recorded, else the recorded audio input with the lowest number (D77).
    private func delayReference(among recorded: Set<String>) -> String? {
        if let defaultMicrophone = audioInputsRead.first(where: \.isDefault)?.uid, recorded.contains(defaultMicrophone) {
            return defaultMicrophone
        }
        return audioTracker.sourcesShown.compactMap { source -> (Int, String)? in
            guard case .input(let uid) = source.id, recorded.contains(uid) else { return nil }
            return (source.number, uid)
        }.min { $0.0 < $1.0 }?.1
    }

    // MARK: Input volume

    /// Follows an audio input's input volume while its capture runs; an
    /// input without one has none to follow.
    private func followInputVolume(_ uid: String, name: String, control: (any InputVolumeControl)?, captureNumber: Int) {
        if let followed = inputVolumes[uid] { unfollowInputVolume(.input(uid), captureNumber: followed.captureNumber) }
        guard let control else { return }
        let volume = control.read()
        inputVolumes[uid] = InputVolumeFollow(
            control: control, name: name, captureNumber: captureNumber, changes: InputVolumeChanges(volume: volume),
            latest: volume)
        startReadingInputVolumes()
        do throws(InputVolumeError) {
            try control.watch { [weak self] in
                Task { @MainActor in self?.readInputVolume(uid) }
            }
            problemsTold.cleared(.inputVolumeNotFollowed(name), at: context.now())
        } catch {
            tell("Changes of the input volume of \(name) cannot be followed", error: ErrorDetail(message: error.description),
                 kind: .inputVolumeNotFollowed(name))
        }
    }

    /// The followed volumes are read every `inputVolumeReadInterval` from the
    /// first follow to the last unfollow: a knob may not reach Core Audio's listener.
    private func startReadingInputVolumes() {
        guard inputVolumeTask == nil, !isStopped else { return }
        inputVolumeTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: RecorderValues.inputVolumeReadInterval)
                guard let self else { return }
                for uid in inputVolumes.keys { readInputVolume(uid) }
            }
        }
    }

    private func stopReadingInputVolumes() {
        inputVolumeTask?.cancel()
        inputVolumeTask = nil
    }

    /// The capture ended: a change not told yet is told now.
    private func unfollowInputVolume(_ id: AudioTracker.SourceID, captureNumber: Int) {
        guard case .input(let uid) = id, let follow = inputVolumes[uid], follow.captureNumber == captureNumber else { return }
        inputVolumes[uid] = nil
        if inputVolumes.isEmpty { stopReadingInputVolumes() }
        follow.control.cancel()
        follow.dueTask?.cancel()
        var changes = follow.changes
        if let event = changes.flush(audioSource: follow.name) { audioEvent(event) }
    }

    private func readInputVolume(_ uid: String) {
        guard var follow = inputVolumes[uid], let volume = follow.control.read() else { return }
        follow.latest = volume
        follow.changes.observe(volume, at: context.now())
        follow.dueTask?.cancel()
        follow.dueTask = follow.changes.nextDueTime().map { due in
            let wait = max(0, due - context.now())
            return Task { [weak self] in
                try? await Task.sleep(for: .nanoseconds(wait))
                guard !Task.isCancelled else { return }
                self?.inputVolumeDue(uid)
            }
        }
        inputVolumes[uid] = follow
    }

    private func inputVolumeDue(_ uid: String) {
        guard var follow = inputVolumes[uid], let event = follow.changes.due(at: context.now(), audioSource: follow.name) else { return }
        follow.dueTask = nil
        inputVolumes[uid] = follow
        audioEvent(event)
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
            case .noAudio(let id, let number, let isNoAudio):
                // Only its running capture's: one that ended says nothing more.
                if audioCaptures[id]?.0 == number { audioTracker.noAudio(id, isNoAudio) }
            case .ended(let id, let number, let name, let reason):
                audioCaptureEnded(id, number: number, name: name, reason: reason)
            }
        }
    }

    private func audioFileStarted(_ file: RecordingManifest.AudioFile, id: AudioTracker.SourceID, name: String) {
        guard manifest.state != .finalized else { return }
        RecorderLog.detail("file started: \(file.name)", category: "recorder")
        let started = audioTracker.fileStarted(id, at: Int64((file.start * 1_000_000_000).rounded()))
        problemsTold.cleared(.audioSourceFailed(name), at: context.now())
        // A failed file of the source is over once a new one starts (D78).
        for earlier in manifest.audioFiles where earlier.audioSourceUID == file.audioSourceUID {
            problemsTold.cleared(.audioFileFailed(earlier.name), at: context.now())
        }
        let listed = manifest.audioFileStarted(file)
        if !started.isEmpty { _ = manifest.record(started) }
        if listed || !started.isEmpty { try? writeManifest() }
        told(started)
    }

    /// Internal, so a test can deliver a failed file's end, as the stand-in audio sources cannot fail a writer.
    func audioFileEnded(_ end: AudioFileEnd) {
        guard manifest.audioFileEnded(end.file) else { return }
        if let uid = end.file.audioSourceUID { problemsTold.cleared(.audioInputOutOfTheGuideTrack(uid), at: context.now()) }
        RecorderLog.detail("file ended: \(end.file.name), \(end.file.state.rawValue)", category: "recorder")
        _ = manifest.record(end.events)
        try? writeManifest()
        told(end.events)
        // At the file's end, so a lost end (`audio file writer fell behind`) is told once (D47).
        if end.error != nil || !end.events.isEmpty {
            let at = Int64((end.failureSeconds * 1_000_000_000).rounded())
            let newer = manifest.audioFiles
                .filter { $0.audioSourceUID == end.file.audioSourceUID && $0.start > end.file.start }
                .map { Int64(($0.start * 1_000_000_000).rounded()) }.min()
            tell(RecordingProblem(at: at, problem: "Audio file \(end.file.name)",
                                  error: end.error?.detail ?? "its writer fell behind"),
                 kind: .audioFileFailed(end.file.name), endedAt: newer, ofAnEvent: end.toldByAnEvent)
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
        unfollowInputVolume(id, captureNumber: number)
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
            guard let bytes = try volumeFreeBytes(of: folder) else {
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
        problemsTold.cleared(.freeSpaceNotRead, at: context.now())
        let threshold = lowDiskWarningBytes()
        let isLow = Double(free) < threshold
        if !isLow { problemsTold.cleared(.diskFull, at: context.now()) }
        if isLow != isLowOnDisk {
            isLowOnDisk = isLow
            observer?.recorder(self, lowDiskSpace: isLow)
        }
        if tracker.isWaitingForRoom, !isLow {
            tracker.roomAgain()
            apply(ScreenTracker.Step())
        }
        if cameraTracker.isWaitingForRoom, !isLow {
            cameraTracker.roomAgain()
            applyCameras(CameraTracker.Step())
        }
        if audioTracker.isWaitingForRoom, !isLow {
            audioTracker.roomAgain()
            applyAudio(AudioTracker.Step())
        }
    }

    /// The low disk warning threshold: `lowDiskWarningMinutes` of every
    /// screen's newest screen file, every camera's newest camera file and every audio source's newest audio
    /// file at the encoding rate.
    private func lowDiskWarningBytes() -> Double {
        var newestFrameSize: [String: FrameSize] = [:]
        for file in manifest.files {
            newestFrameSize[file.screenUUID] = FrameSize(width: file.frameSize[0], height: file.frameSize[1])
        }
        for file in manifest.cameraFiles {
            newestFrameSize[file.cameraUniqueID] = FrameSize(width: file.frameSize[0], height: file.frameSize[1])
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
            $0 + DiskEstimate.videoFileBytesPerHour(frameSize: $1, settings: settings)
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
            problemsTold.cleared(.recordingLogNotWritten, at: context.now())
            return
        }
        tell("Cannot write the recording log \(RecordingNames.recordingLog)", error: failure, kind: .recordingLogNotWritten)
    }

    private func writeManifest() throws {
        do {
            try manifest.jsonData().write(to: folder.appending(path: RecordingNames.manifest), options: .atomic)
            problemsTold.cleared(.manifestNotWritten, at: context.now())
        } catch {
            tell("Cannot write the recording manifest", error: ErrorDetail(error), kind: .manifestNotWritten)
            throw error
        }
    }

    /// The timeline file (D68), from the final manifest on disk. Its failure leaves the recording as it is:
    /// told like every problem after the end, which the recording log, closed by then, does not hold.
    private func writeTimelineFile() async {
        do {
            try await TimelineFile.write(in: folder)
        } catch {
            tell("Cannot write the timeline file", error: ErrorDetail(error), kind: .timelineFileNotWritten)
        }
    }

    /// A problem for the person and the manifest's `problems`, the manifest
    /// written at once (`ProblemsTold`); one that repeats is told once until
    /// it clears. `ofAnEvent`: a failure event's line tells it on standard error (D65).
    private func tell(_ problem: String, error: ErrorDetail?, kind: ProblemKind, at time: Int64? = nil, ofAnEvent: Bool = false) {
        tell(RecordingProblem(at: time ?? context.now(), problem: problem, error: error), kind: kind, ofAnEvent: ofAnEvent)
    }

    private func tell(
        _ problem: RecordingProblem, kind: ProblemKind, source: String? = nil, note: String? = nil, endedAt: Int64? = nil,
        ending: ProblemsTold.Ending = .recovered, ofAnEvent: Bool = false, notifies: Bool = true
    ) {
        switch problemsTold.add(problem, kind: kind, source: source, note: note, endedAt: endedAt, ending: ending, to: &manifest) {
        case .tell(let writesManifest):
            if writesManifest { try? writeManifest() }
            told(problem, ofAnEvent: ofAnEvent, notifies: notifies)
        case .alreadyTold:
            break
        case .afterTheEnd:
            // Such as the final manifest that cannot be written, or a late report of the recording log.
            RecorderLog.error("at \(problem.at)s, after the end: \(problem.text)", category: "recorder")
            StandardErrorWriter.shared.write("Problem at the end: \(problem.text)\n")
        }
    }

    /// To the logs and, if it `notifies`, the observer: the Dock, the badge and the count (D79).
    private func told(_ problem: RecordingProblem, ofAnEvent: Bool = false, notifies: Bool = true) {
        RecorderLog.error("at \(problem.at)s: \(problem.text)", category: "recorder")
        recordingLog?.problem(problem)
        if notifies { observer?.recorder(self, problem: problem, ofAnEvent: ofAnEvent) }
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
