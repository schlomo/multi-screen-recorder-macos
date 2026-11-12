import Foundation
import Observation
import RecorderCore
import RecorderLogic

/// The start window's state: the settings as saved, and the ready check.
@MainActor
@Observable
final class StartModel {
    let homeFolder: URL
    private let settingsFile: SettingsFile

    private(set) var settings = Settings.defaults
    private(set) var settingsError: String?
    private(set) var readyCheck: ReadyCheckResult?
    private(set) var isChecking = false
    @ObservationIgnored private var checkTask: Task<Void, Never>?

    init(homeFolder: URL) {
        self.homeFolder = homeFolder
        settingsFile = SettingsFile.standard(homeFolder: homeFolder)
    }

    func load() {
        do {
            settings = try settingsFile.load()
            settingsError = nil
            runReadyCheckAgain()
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
        runReadyCheckAgain()
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

    private func runReadyCheckAgain() {
        checkTask?.cancel()
        isChecking = true
        let settings = settings
        let homeFolder = homeFolder
        checkTask = Task {
            let result = await runReadyCheck(settings: settings, homeFolder: homeFolder)
            guard !Task.isCancelled else { return }
            readyCheck = result
            isChecking = false
        }
    }
}
