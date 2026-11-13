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
    @ObservationIgnored private var checkTask: Task<Void, Never>?
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var gate = RefreshGate()

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

    /// A display or an audio input came, went or changed.
    func devicesChanged() {
        refreshSoon()
    }

    func menuOpened() {
        gate.menuOpened()
    }

    func menuClosed() {
        if gate.menuClosed() { refreshSoon() }
    }

    /// Re-reads the devices and re-runs the ready check shortly, once for a
    /// burst of changes, and never while a menu of the window is open.
    private func refreshSoon() {
        guard settingsError == nil else { return }
        refreshTask?.cancel()
        refreshTask = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled, gate.changeArrived() else { return }
            checkAgain()
        }
    }

    /// Reads the devices for "What will be recorded" and re-runs the ready
    /// check; once it is done, the section shows what the check found,
    /// the free space included.
    func checkAgain() {
        whatWillBeRecorded = WhatWillBeRecorded(
            settings: settings,
            displays: Result { () throws(DeviceReadError) in try currentDisplays() },
            audioInputs: currentAudioInputs(),
            outputFolder: nil)
        checkTask?.cancel()
        isChecking = true
        let settings = settings
        let homeFolder = homeFolder
        checkTask = Task {
            let facts = await probeReadyCheckFacts(settings: settings, homeFolder: homeFolder)
            guard !Task.isCancelled else { return }
            // A menu opened meanwhile: nothing changes under it, and the check
            // that runs when it closes shows the result.
            guard gate.changeArrived() else { return }
            readyCheck = ReadyCheck.evaluate(facts, settings: settings)
            whatWillBeRecorded = WhatWillBeRecorded(
                settings: settings, displays: facts.displays, audioInputs: facts.audioInputs,
                outputFolder: facts.outputFolder)
            isChecking = false
        }
    }
}
