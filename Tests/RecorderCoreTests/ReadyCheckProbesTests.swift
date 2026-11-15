import Foundation
import RecorderLogic
import Testing
@testable import RecorderCore

/// The ready check's probes with stand-ins for this Mac: nothing is asked of
/// the system, nothing prompts.
@Suite struct ReadyCheckProbesTests {
    /// What the stand-in probes were asked, and on which thread.
    final class Calls: @unchecked Sendable {
        private let lock = NSLock()
        private var asked: [String] = []
        private var mainThreadAsked: [String] = []

        func record(_ name: String) {
            lock.withLock {
                asked.append(name)
                if Thread.isMainThread { mainThreadAsked.append(name) }
            }
        }

        var names: [String] { lock.withLock { asked } }
        var namesOnTheMainThread: [String] { lock.withLock { mainThreadAsked } }
    }

    private func probes(
        _ calls: Calls, screenRecording: PermissionProbe = .granted,
        displays: Result<[DisplayInfo], DeviceReadError> = .success([]),
        outputFolder: OutputFolderProbe = .usable(.bytes(5))
    ) -> ReadyCheckProbes {
        ReadyCheckProbes(
            screenRecording: { calls.record("screenRecording"); return screenRecording },
            microphonePermission: { calls.record("microphonePermission"); return true },
            displays: { calls.record("displays"); return displays },
            audioInputs: { calls.record("audioInputs"); return .success([]) },
            outputFolder: { folder in
                calls.record("outputFolder \(folder.path(percentEncoded: false))")
                return outputFolder
            })
    }

    private let home = URL(filePath: "/Users/someone", directoryHint: .isDirectory)

    @Test func theFactsAreWhatTheProbesFound() async {
        let calls = Calls()
        let facts = await probeReadyCheckFacts(
            settings: .defaults, homeFolder: home,
            probes: probes(calls, screenRecording: .notGranted, displays: .failure(DeviceReadError("none")),
                           outputFolder: .unusable("read-only")))
        #expect(facts.screenRecording == .notGranted)
        #expect(facts.microphoneGranted == true)
        #expect(facts.displays == .failure(DeviceReadError("none")))
        #expect(facts.audioInputs == .success([]))
        #expect(facts.outputFolder == .unusable("read-only"))
    }

    @Test func theOutputFolderIsTheSettingsFolderInTheHomeFolder() async {
        let calls = Calls()
        _ = await probeReadyCheckFacts(settings: .defaults, homeFolder: home, probes: probes(calls))
        #expect(calls.names.contains("outputFolder /Users/someone/Movies/Multi Screen Recorder/"))
    }

    @Test func theMicrophonePermissionIsNotAskedWithTheAudioModeNone() async {
        var settings = Settings.defaults
        settings.auto = false
        settings.audioMode = .none
        let calls = Calls()
        let facts = await probeReadyCheckFacts(settings: settings, homeFolder: home, probes: probes(calls))
        #expect(facts.microphoneGranted == nil)
        #expect(!calls.names.contains("microphonePermission"))
    }

    @Test func autoModeAsksForTheMicrophonePermissionWhateverTheSliderSays() async {
        var settings = Settings.defaults
        settings.audioMode = .none
        let calls = Calls()
        let facts = await probeReadyCheckFacts(settings: settings, homeFolder: home, probes: probes(calls))
        #expect(facts.microphoneGranted == true)
    }

    @Test func fileAccessIsOffTheMainThreadAndTheDisplaysAreOnIt() async {
        let calls = Calls()
        _ = await probeReadyCheckFacts(settings: .defaults, homeFolder: home, probes: probes(calls))
        #expect(calls.names.contains("displays"))
        #expect(calls.namesOnTheMainThread == ["displays"])
    }

    @MainActor @Test func fileAccessIsOffTheMainThreadAlsoWhenTheCallerIsOnIt() async {
        let calls = Calls()
        _ = await probeReadyCheckFacts(settings: .defaults, homeFolder: home, probes: probes(calls))
        #expect(calls.names.contains { $0.hasPrefix("outputFolder") })
        #expect(calls.namesOnTheMainThread == ["displays"])
    }
}
