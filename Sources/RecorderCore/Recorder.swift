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
    /// Something the recording cannot put into its manifest, such as the manifest itself failing to be written.
    func recorder(_ recorder: Recorder, problem: String)
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
        context = RecordingContext(folder: folder, started: started, timeZone: timeZone, clock: SharedClock(reading: reading))
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

    /// Ends every display file, finalizes the recording manifest and removes the crash marker.
    public func stop() async -> RecordingSummary {
        if !isStopped {
            isStopped = true
            dueTask?.cancel()
            freeSpaceTask?.cancel()
            unregisterForChanges()
            for action in tracker.stopAll() { perform(action) }
            for task in stopping { await task.value }
            manifest.state = .finalized
            try? writeManifest()
            do { try markers.remove() } catch { observer?.recorder(self, problem: "Cannot remove the crash marker: \(error)") }
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
            return try connectedDisplays()
        } catch {
            observer?.recorder(self, problem: "The displays cannot be read: \(error)")
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
                    Task { @MainActor in self?.captureEnded(uuid: uuid, captureNumber: captureNumber, reason: reason, file: file) }
                })
            captures[uuid] = (captureNumber, capture)
            capture.start()
            if tracker.showsAnotherDisplaysPicture == false { observer?.recorder(self, displayShowsAnotherDisplaysPicture: nil) }
        case .stop(let uuid, _):
            guard let (_, capture) = captures.removeValue(forKey: uuid) else { return }
            stopping.append(Task { [weak self] in
                let file = await capture.stop()
                self?.fileEnded(file, uuid: uuid, errorHasItsEvent: false)
            })
        }
    }

    /// The manifest lists a file from its start; a start reported after
    /// the file's end changes nothing.
    private func fileStarted(_ file: RecordingManifest.DisplayFile, uuid: String) {
        tracker.fileStarted(uuid)
        guard !manifest.files.contains(where: { $0.name == file.name }) else { return }
        manifest.files.append(file)
        try? writeManifest()
    }

    /// A display file ended; its end carries its entry, so it is listed
    /// even when its start was not reported yet. A writer's error is the
    /// event `display file writer failed`, unless the end's reason already
    /// is one, and a problem for the person.
    private func fileEnded(_ end: DisplayFileEnd?, uuid: String, errorHasItsEvent: Bool) {
        guard let end else { return }
        if let index = manifest.files.firstIndex(where: { $0.name == end.file.name }) {
            manifest.files[index] = end.file
        } else {
            manifest.files.append(end.file)
        }
        if let error = end.error {
            if !errorHasItsEvent {
                var failed = RecordingEvent(at: context.now(), event: .displayFileWriterFailed, display: end.file.display)
                failed.error = error
                manifest.events.append(failed)
            }
            observer?.recorder(self, problem: "Display file \(end.file.name): \(error)")
        }
        try? writeManifest()
    }

    private func captureEnded(uuid: String, captureNumber: Int, reason: DisplayTracker.StreamEnd, file: DisplayFileEnd?) {
        let errorHasItsEvent: Bool = switch reason {
        case .writerFailed, .diskFull: true
        case .streamFailed, .writerFellBehind, .showsAnotherDisplay: false
        }
        fileEnded(file, uuid: uuid, errorHasItsEvent: errorHasItsEvent)
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
            guard let bytes = values.volumeAvailableCapacityForImportantUsage else { return }
            free = bytes
        } catch {
            observer?.recorder(self, problem: "The free space in \(folder.path(percentEncoded: false)) cannot be read: \(error.localizedDescription)")
            return
        }
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
        } catch {
            observer?.recorder(self, problem: "Cannot write the recording manifest: \(error.localizedDescription)")
            throw error
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
