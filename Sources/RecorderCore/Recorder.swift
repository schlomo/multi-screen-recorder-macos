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
    /// A display's file ended because it showed another display's picture,
    /// or (nil) no display is in that state any more.
    func recorder(_ recorder: Recorder, displayShowsAnotherDisplaysPicture display: String?)
    /// A problem, also listed in the recording manifest's `problems`.
    func recorder(_ recorder: Recorder, problem: RecordingProblem)
    /// An event of the recording manifest, as one line (`EventLine`).
    func recorder(_ recorder: Recorder, eventLine: String)
}

public struct RecorderStartError: Error, CustomStringConvertible {
    public let description: String
}

/// One recording: claims its recording folder, keeps its crash marker and
/// recording manifest, keeps the Mac awake, and follows the displays as
/// they come, go and change, with one display capture per display file.
/// Needs the AppKit event loop: macOS reports display changes only to a
/// process running `NSApplication.run()`.
@MainActor
public final class Recorder {
    public let folder: URL
    private let context: RecordingContext
    private let settings: Settings
    private let markers: CrashMarkers
    private weak var observer: (any RecorderObserver)?
    private var manifest: RecordingManifest
    private var tracker: DisplayTracker
    /// The running capture of each display, with its number among all captures of the recording.
    private var captures: [String: (Int, DisplayCapture)] = [:]
    private var captureCount = 0
    private var endReports = CaptureEndReports()
    private var problemsTold = ProblemsTold()
    /// Stops in progress, so Stop waits for every file.
    private var stopping: [Task<Void, Never>] = []
    private var dueTask: Task<Void, Never>?
    private var freeSpaceTask: Task<Void, Never>?
    private var activity: (any NSObjectProtocol)?
    private var notificationTokens: [any NSObjectProtocol] = []
    private var isLowOnDisk = false
    private var isStopped = false
    private var displayChangePending = false

    /// Starts a recording into a new recording folder in the settings' output folder.
    public init(settings: Settings, homeFolder: URL, app: String, observer: any RecorderObserver) throws(RecorderStartError) {
        let displays: [ConnectedDisplay]
        do {
            displays = try connectedDisplays()
        } catch {
            throw RecorderStartError(description: "The displays cannot be read: \(error)")
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
            throw RecorderStartError(description:
                "Cannot create the recording folder \(folder.path(percentEncoded: false)): \(error.localizedDescription)")
        }
        context = RecordingContext(folder: folder, started: started, timeZone: timeZone, clock: SharedClock(reading: reading), app: app)
        self.settings = settings
        markers = CrashMarkers(homeFolder: homeFolder)
        self.observer = observer
        manifest = RecordingManifest(app: app, started: started, timeZone: timeZone, settings: settings)
        tracker = DisplayTracker(resolution: settings.effectiveResolution)
        do {
            try writeManifest()
            try markers.write(recordingFolder: folder)
        } catch {
            // Nothing was recorded: the start leaves nothing behind.
            try? markers.remove()
            try? FileManager.default.removeItem(at: folder.appending(path: RecordingNames.manifest))
            try? FileManager.default.removeItem(at: folder)
            throw RecorderStartError(description: "Cannot start the recording in \(folder.path(percentEncoded: false)): \(error)")
        }
        activity = ProcessInfo.processInfo.beginActivity(
            options: [.idleSystemSleepDisabled, .idleDisplaySleepDisabled, .userInitiated],
            reason: "Multi Screen Recorder is recording")
        registerForChanges()
        context.update(displays, lastDisplayChange: nil)
        apply(tracker.begin(displays, at: context.now()))
        freeSpaceTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: RecorderValues.freeSpaceCheckInterval)
                self?.checkFreeSpace()
            }
        }
    }

    /// Seconds since the recording started, on the shared clock.
    public var elapsedSeconds: Double { Double(context.now()) / 1_000_000_000 }

    /// The status window's table and line, read now: each file's size on
    /// disk and the free space in the recording folder.
    public func status() -> (rows: [RecordingStatusTable.Row], line: String) {
        let sizes = manifest.files.map { file in
            (file.name, (try? FileManager.default.attributesOfItem(atPath: folder.appending(path: file.name).path(percentEncoded: false)))?[.size] as? Int64)
        }
        let bytes = Dictionary(sizes.compactMap { name, size in size.map { (name, $0) } }, uniquingKeysWith: { $1 })
        let bytesWritten: Int64? = sizes.contains { $0.1 == nil } ? nil : bytes.values.reduce(0, +)
        let free = (try? folder.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]))?
            .volumeAvailableCapacityForImportantUsage
        return (
            RecordingStatusTable.rows(sources: tracker.sources, files: manifest.files, bytes: bytes),
            RecordingStatusTable.line(
                elapsedSeconds: elapsedSeconds, bytesWritten: bytesWritten, files: manifest.files.count,
                freeBytes: free))
    }

    /// Ends every display file, finalizes the recording manifest and removes the crash marker.
    public func stop() async -> RecordingSummary {
        if !isStopped {
            isStopped = true
            dueTask?.cancel()
            freeSpaceTask?.cancel()
            unregisterForChanges()
            for action in tracker.stopAll() { perform(action) }
            for task in stopping { await task.value }
            let ended = Date()
            manifest.finalize(ended: ended, timeZone: context.timeZone)
            try? writeManifest()
            do {
                try markers.remove()
            } catch {
                tell("Cannot remove the crash marker", error: "\(error)", kind: .crashMarkerNotRemoved)
                manifest.finalize(ended: ended, timeZone: context.timeZone)
                try? writeManifest()
            }
            if let activity { ProcessInfo.processInfo.endActivity(activity) }
            activity = nil
        }
        return RecordingSummary(manifest: manifest, recordingFolder: folder.path(percentEncoded: false), seconds: elapsedSeconds)
    }

    // MARK: Display changes

    private func registerForChanges() {
        CGDisplayRegisterReconfigurationCallback(displayReconfigured, Unmanaged.passUnretained(self).toOpaque())
        let center = NSWorkspace.shared.notificationCenter
        notificationTokens = [
            center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.willSleep() }
            },
            center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.didWake() }
            },
        ]
    }

    private func unregisterForChanges() {
        CGDisplayRemoveReconfigurationCallback(displayReconfigured, Unmanaged.passUnretained(self).toOpaque())
        for token in notificationTokens { NSWorkspace.shared.notificationCenter.removeObserver(token) }
        notificationTokens = []
    }

    /// macOS reported a display change: read the displays on the next pass of the main loop, once for a burst.
    fileprivate func displaysReconfigured() {
        guard !displayChangePending, !isStopped else { return }
        displayChangePending = true
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                self.displayChangePending = false
                guard !self.isStopped, let displays = self.readDisplays() else { return }
                let now = self.context.now()
                let step = self.tracker.observe(displays, at: now)
                self.context.update(displays, lastDisplayChange: self.tracker.lastDisplayChange)
                self.apply(step)
            }
        }
    }

    private func readDisplays() -> [ConnectedDisplay]? {
        do {
            let displays = try connectedDisplays()
            RecorderLog.detail("displays: \(displays)", category: "recorder")
            problemsTold.cleared(.displaysNotRead)
            return displays
        } catch {
            tell("The displays cannot be read", error: "\(error)", kind: .displaysNotRead)
            return nil
        }
    }

    private func willSleep() {
        guard !isStopped else { return }
        apply(tracker.sleep(at: context.now()))
    }

    private func didWake() {
        guard !isStopped else { return }
        context.rereadClocks()
        guard let displays = readDisplays() else { return }
        let step = tracker.wake(displays, at: context.now())
        context.update(displays, lastDisplayChange: tracker.lastDisplayChange)
        apply(step)
    }

    // MARK: Actions

    /// Records the events, carries out the actions, and waits for what is due next.
    private func apply(_ step: DisplayTracker.Step) {
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

    private func perform(_ action: DisplayTracker.Action) {
        RecorderLog.detail("\(action)", category: "recorder")
        switch action {
        case .start(let uuid, let displayID, let frameSize, let number, let name):
            captureCount += 1
            let captureNumber = captureCount
            let capture = DisplayCapture(
                uuid: uuid, displayID: displayID, number: number, name: name, frameSize: frameSize, context: context,
                onFileStarted: { [weak self] file in
                    Task { @MainActor in self?.fileStarted(file, uuid: uuid) }
                },
                onEnded: { [weak self] reason, file in
                    Task { @MainActor in self?.captureEnded(uuid: uuid, captureNumber: captureNumber, display: name, reason: reason, file: file) }
                })
            captures[uuid] = (captureNumber, capture)
            capture.start()
            if tracker.showsAnotherDisplaysPicture == false { observer?.recorder(self, displayShowsAnotherDisplaysPicture: nil) }
        case .stop(let uuid, _):
            guard let (captureNumber, capture) = captures.removeValue(forKey: uuid) else { return }
            stopping.append(Task { [weak self] in
                let file = await capture.stop()
                self?.fileEnded(file, captureNumber: captureNumber, display: capture.name, reason: nil)
            })
        }
    }

    /// The manifest lists a file from its start; a start reported after
    /// the file's end changes nothing.
    private func fileStarted(_ file: RecordingManifest.DisplayFile, uuid: String) {
        RecorderLog.detail("file started: \(file.name)", category: "recorder")
        tracker.fileStarted(uuid)
        guard !manifest.files.contains(where: { $0.name == file.name }) else { return }
        manifest.files.append(file)
        try? writeManifest()
    }

    /// A display file ended, or a capture without one; its end carries its
    /// entry, so the file is listed even when its start was not reported
    /// yet. Its event and problem are recorded once per capture, also when
    /// the capture ended by itself while the recorder stopped it.
    private func fileEnded(_ end: DisplayFileEnd?, captureNumber: Int, display: String, reason: DisplayTracker.StreamEnd?) {
        let before = manifest
        let problem = endReports.record(
            captureNumber: captureNumber, reason: reason, end: end, display: display, at: context.now(), into: &manifest)
        if manifest != before { try? writeManifest() }
        told(Array(manifest.events.dropFirst(before.events.count)))
        if let problem { told(problem) }
        if let end { RecorderLog.detail("file ended: \(end.file.name), \(end.file.state.rawValue)", category: "recorder") }
    }

    private func captureEnded(
        uuid: String, captureNumber: Int, display: String, reason: DisplayTracker.StreamEnd, file: DisplayFileEnd?
    ) {
        fileEnded(file, captureNumber: captureNumber, display: display, reason: reason)
        // One the recorder already stopped, or replaced, changes nothing more.
        guard !isStopped, let (current, capture) = captures[uuid], current == captureNumber else { return }
        captures[uuid] = nil
        if reason == .showsAnotherDisplay { observer?.recorder(self, displayShowsAnotherDisplaysPicture: capture.name) }
        let displays = readDisplays() ?? []
        let step = tracker.streamEnded(uuid, reason, connected: displays, at: context.now())
        context.update(displays, lastDisplayChange: tracker.lastDisplayChange)
        apply(step)
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
            tell("The free space in \(folder.path(percentEncoded: false)) cannot be read", error: error.localizedDescription,
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
            apply(DisplayTracker.Step())
        }
    }

    /// The low disk warning threshold: `lowDiskWarningMinutes` of every
    /// display's newest display file at the encoding rate.
    private func lowDiskWarningBytes() -> Double {
        var newestFrameSize: [String: FrameSize] = [:]
        for file in manifest.files {
            newestFrameSize[file.displayUUID] = FrameSize(width: file.frameSize[0], height: file.frameSize[1])
        }
        let bytesPerHour = newestFrameSize.values.reduce(0.0) {
            $0 + DiskEstimate.displayFileBytesPerHour(frameSize: $1, settings: settings)
        }
        return bytesPerHour * settings.lowDiskWarningMinutes / 60
    }

    // MARK: Manifest

    private func writeManifest() throws {
        do {
            try manifest.jsonData().write(to: folder.appending(path: RecordingNames.manifest), options: .atomic)
            problemsTold.cleared(.manifestNotWritten)
        } catch {
            tell("Cannot write the recording manifest", error: error.localizedDescription, kind: .manifestNotWritten)
            throw error
        }
    }

    /// A problem for the person and the manifest's `problems`, the manifest
    /// written at once (`ProblemsTold`); one that repeats is told once until
    /// it clears.
    public func tell(_ problem: String, error: String?, kind: ProblemKind) {
        let problem = RecordingProblem(at: context.now(), problem: problem, error: error)
        guard case .tell(let writesManifest) = problemsTold.add(problem, kind: kind, to: &manifest) else { return }
        if writesManifest { try? writeManifest() }
        told(problem)
    }

    private func told(_ problem: RecordingProblem) {
        RecorderLog.error("at \(problem.at)s: \(problem.text)", category: "recorder")
        observer?.recorder(self, problem: problem)
    }

    /// Events now in the manifest: to the log and the observer.
    private func told(_ events: [RecordingEvent]) {
        for event in events {
            let line = EventLine.text(event, started: context.started, timeZone: context.timeZone)
            RecorderLog.notice(line, category: "recorder")
            observer?.recorder(self, eventLine: line)
        }
    }
}

/// Called by macOS on the main thread, under `NSApplication.run()`, for every display change.
private func displayReconfigured(
    _ display: CGDirectDisplayID, _ flags: CGDisplayChangeSummaryFlags, _ userInfo: UnsafeMutableRawPointer?
) {
    guard let userInfo, !flags.contains(.beginConfigurationFlag) else { return }
    let recorder = Unmanaged<Recorder>.fromOpaque(userInfo).takeUnretainedValue()
    MainActor.assumeIsolated { recorder.displaysReconfigured() }
}
