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

    private(set) var settings = Settings.defaults
    private(set) var settingsError: String?
    private(set) var whatWillBeRecorded: WhatWillBeRecorded?
    private(set) var readyCheck: ReadyCheckResult?
    private(set) var isChecking = false
    /// Counts the ready checks started, so only the newest shows its result.
    @ObservationIgnored private var checkNumber = 0
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    /// A refresh waits for the main run loop's default mode; a further one is not queued.
    @ObservationIgnored private var refreshIsWaiting = false

    /// How long the devices get to settle before they are read again: one
    /// change of a display or an audio device arrives as a burst of notices.
    static let deviceChangeSettleTime = Duration.milliseconds(300)

    init(homeFolder: URL) {
        self.homeFolder = homeFolder
        settingsFile = SettingsFile.standard(homeFolder: homeFolder)
    }

    func load() {
        do {
            settings = try settingsFile.load()
            settingsError = nil
            checkAgain()
        } catch {
            settingsError = error.description
            readyCheck = nil
        }
    }

    /// Changes a setting, saves the settings file and re-runs the ready check.
    func change(_ edit: (inout Settings) -> Void) {
        edit(&settings)
        do {
            try settingsFile.save(settings)
        } catch {
            settingsError = error.description
            return
        }
        checkAgain()
    }

    func resetToDefaults() {
        do {
            try settingsFile.save(.defaults)
        } catch {
            settingsError = error.description
            return
        }
        load()
    }

    func chooseOutputFolder(_ folder: URL) {
        change { $0.outputFolder = Settings.outputFolderSetting(for: folder, homeFolder: homeFolder) }
    }

    /// Back in the app, the person may have granted a permission; a check
    /// still running is left to finish.
    func appBecameActive() {
        guard !isChecking else { return }
        refreshSoon()
    }

    /// A display came, went or changed, an audio device came or went, or the
    /// default audio input changed.
    func devicesChanged() {
        refreshSoon()
    }

    /// Re-reads the devices and re-runs the ready check once the devices
    /// have settled, once for a burst of changes.
    private func refreshSoon() {
        guard settingsError == nil else { return }
        refreshTask?.cancel()
        refreshTask = Task {
            try? await Task.sleep(for: Self.deviceChangeSettleTime)
            guard !Task.isCancelled, !refreshIsWaiting else { return }
            refreshIsWaiting = true
            whenMainRunLoopIsInDefaultMode {
                self.refreshIsWaiting = false
                self.checkAgain()
            }
        }
    }

    /// Reads the devices for "What will be recorded" and re-runs the ready
    /// check; once it is done, the section shows what the check found,
    /// the free space included.
    ///
    /// The result is shown when the main run loop is in its default mode, so
    /// the window's content does not change by itself under an open menu, a
    /// dragged control or a modal panel. The app was ended by an exception in
    /// AppKit's window layout after a display's mode was switched, with a
    /// menu open; a change of the content under the menu is one of two
    /// candidates for the cause [ASSUMED], the window's sizing the other.
    func checkAgain() {
        whatWillBeRecorded = WhatWillBeRecorded(
            settings: settings,
            displays: Result { () throws(DeviceReadError) in try currentDisplays() },
            audioInputs: Result { () throws(DeviceReadError) in try currentAudioInputs() },
            outputFolder: nil)
        checkNumber += 1
        isChecking = true
        let number = checkNumber
        let settings = settings
        let homeFolder = homeFolder
        Task {
            let facts = await probeReadyCheckFacts(settings: settings, homeFolder: homeFolder)
            whenMainRunLoopIsInDefaultMode {
                // A newer check has replaced this one and shows its own result.
                guard number == self.checkNumber else { return }
                self.readyCheck = ReadyCheck.evaluate(facts, settings: settings)
                self.whatWillBeRecorded = WhatWillBeRecorded(
                    settings: settings, displays: facts.displays, audioInputs: facts.audioInputs,
                    outputFolder: facts.outputFolder)
                self.isChecking = false
            }
        }
    }
}
