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
            await untilNoMenuIsOpen()
            guard !Task.isCancelled else { return }
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
            audioInputs: Result { () throws(DeviceReadError) in try currentAudioInputs() },
            outputFolder: nil)
        checkTask?.cancel()
        isChecking = true
        let settings = settings
        let homeFolder = homeFolder
        checkTask = Task {
            let facts = await probeReadyCheckFacts(settings: settings, homeFolder: homeFolder)
            await untilNoMenuIsOpen()
            // A newer check has replaced this one and shows its own result.
            guard !Task.isCancelled else { return }
            readyCheck = ReadyCheck.evaluate(facts, settings: settings)
            whatWillBeRecorded = WhatWillBeRecorded(
                settings: settings, displays: facts.displays, audioInputs: facts.audioInputs,
                outputFolder: facts.outputFolder)
            isChecking = false
        }
    }

    /// Returns at once in the normal case, and otherwise when the open menu
    /// or the dragged control is let go: while the app tracks one, the main
    /// run loop is not in its default mode. The window's content does not
    /// change under an open menu; the app was ended by an exception in
    /// AppKit's window layout while a menu was open, and a change of the
    /// content at that moment is the cause [ASSUMED].
    private func untilNoMenuIsOpen() async {
        await withCheckedContinuation { continuation in
            RunLoop.main.perform(inModes: [.default]) { continuation.resume() }
        }
    }
}
