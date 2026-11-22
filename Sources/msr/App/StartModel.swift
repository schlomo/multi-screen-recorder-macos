import Foundation
import Observation
import RecorderCore
import RecorderLogic

/// The start window's state: the settings as saved, what will be recorded,
/// and the ready check.
@MainActor
@Observable
final class StartModel {
    let homeFolder: URL
    private let settingsFile: SettingsFile
    @ObservationIgnored private let probes: ReadyCheckProbes
    @ObservationIgnored private let settleTime: Duration
    /// Runs an action once the window's content may change; in the app, when
    /// the main run loop is in its default mode.
    @ObservationIgnored private let whenContentMayChange: @MainActor (@escaping @MainActor () -> Void) -> Void

    private(set) var settings = Settings.defaults
    /// Set when the settings could not be saved; the choices still apply to this session.
    private(set) var saveError: String?
    private(set) var whatWillBeRecorded: WhatWillBeRecorded?
    private(set) var readyCheck: ReadyCheckResult?
    /// What the newest ready check found, for the recording log.
    @ObservationIgnored private(set) var readyCheckFacts: ReadyCheckFacts?
    private(set) var isChecking = false
    /// From Start on: the ready check never runs while a recording runs (D45).
    private(set) var isRecording = false
    /// Counts the ready checks started, so only the newest shows its result.
    @ObservationIgnored private var checkNumber = 0
    /// Counts the device changes noticed, so a refresh queued for the window
    /// that a newer notice has overtaken does nothing.
    @ObservationIgnored private var refreshNumber = 0
    @ObservationIgnored private var refreshTask: Task<Void, Never>?

    /// How long the devices get to settle before they are read again: one
    /// change of a screen or an audio device arrives as a burst of notices.
    static let deviceChangeSettleTime = Duration.milliseconds(300)

    init(
        homeFolder: URL, probes: ReadyCheckProbes = .system, settleTime: Duration = deviceChangeSettleTime,
        whenContentMayChange: @escaping @MainActor (@escaping @MainActor () -> Void) -> Void = whenMainRunLoopIsInDefaultMode
    ) {
        self.homeFolder = homeFolder
        self.probes = probes
        self.settleTime = settleTime
        self.whenContentMayChange = whenContentMayChange
        settingsFile = SettingsFile.standard(homeFolder: homeFolder)
    }

    /// Reads the settings file, which is never refused; what it ignores goes
    /// to standard error, as for the commands, and is not shown in the window.
    func load() {
        let read = settingsFile.load()
        if let note = read.note { StandardErrorWriter.shared.write("\(note)\n") }
        settings = read.settings
        checkAgain()
    }

    /// Changes a setting, saves the settings file and re-runs the ready check.
    func change(_ edit: (inout Settings) -> Void) {
        edit(&settings)
        do {
            try settingsFile.save(settings)
            saveError = nil
        } catch {
            saveError = ErrorDetail(error).text
        }
        check(proof: .listScreens)
    }

    func chooseOutputFolder(_ folder: URL) {
        change { $0.outputFolder = Settings.outputFolderSetting(for: folder, homeFolder: homeFolder) }
    }

    /// Back in the app, the person may have granted a permission; a check
    /// still running is left to finish.
    func appBecameActive() {
        guard !isChecking, !isRecording else { return }
        refreshSoon()
    }

    /// A screen came, went or changed, an audio device or a camera came or
    /// went, or the default audio input changed.
    func devicesChanged() {
        guard !isRecording else { return }
        refreshSoon()
    }

    /// Start is possible when the newest ready check passed.
    var canStart: Bool { !isRecording && !isChecking && readyCheck?.isReady == true }

    /// The recording started: no ready check runs any more, also no queued one.
    func recordingStarted() {
        isRecording = true
        refreshTask?.cancel()
        refreshTask = nil
    }

    /// Re-reads the devices and re-runs the ready check once the devices
    /// have settled, once for a burst of changes. A refresh waits for the
    /// main run loop's default mode; one that a newer notice has overtaken
    /// by then does nothing.
    private func refreshSoon() {
        refreshNumber += 1
        let number = refreshNumber
        refreshTask?.cancel()
        refreshTask = Task {
            try? await Task.sleep(for: settleTime)
            guard !Task.isCancelled else { return }
            whenContentMayChange {
                guard number == self.refreshNumber, !self.isRecording else { return }
                self.check(proof: .listScreens)
            }
        }
    }

    /// "Check again", and the check at the app's start: it captures a
    /// frame, so macOS's prompts come now, not at Start (D46).
    func checkAgain() {
        check(proof: .captureOneFrame)
    }

    /// The ready check, `proof` as `probeScreenRecording` takes it: reads
    /// the devices for "What will be recorded" and re-runs the ready
    /// check; once it is done, the section shows what the check found,
    /// the free space included.
    ///
    /// The result is shown when the main run loop is in its default mode, so
    /// the window's content does not change by itself under an open menu, a
    /// dragged control or a modal panel. The crash's exception was
    /// thrown in a popup menu's own window, not in the start window's layout
    /// [KNOWN, unified log]; whether this hold kept the content still under
    /// the open menu is not shown by the log, and the owner saw the table
    /// change with the menu open [ASSUMED from the owner's words]. The hold
    /// stays; the window has no popup menu now (D41).
    private func check(proof: ScreenRecordingProof) {
        guard !isRecording else { return }
        whatWillBeRecorded = WhatWillBeRecorded(
            settings: settings, screens: probes.screens(), audioInputs: probes.audioInputs(), cameras: probes.cameras(),
            outputFolder: nil)
        checkNumber += 1
        isChecking = true
        let number = checkNumber
        let settings = settings
        let homeFolder = homeFolder
        let probes = probes
        let whenContentMayChange = whenContentMayChange
        Task {
            let facts = await probeReadyCheckFacts(proof: proof, settings: settings, homeFolder: homeFolder, probes: probes)
            whenContentMayChange {
                // A newer check has replaced this one and shows its own result.
                guard number == self.checkNumber else { return }
                self.readyCheck = ReadyCheck.evaluate(facts, settings: settings)
                self.readyCheckFacts = facts
                self.whatWillBeRecorded = WhatWillBeRecorded(settings: settings, facts: facts)
                self.isChecking = false
            }
        }
    }
}
