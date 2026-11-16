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
        screens: Result<[ScreenInfo], DeviceReadError> = .success([]),
        audioInputs: [AudioInputInfo] = [AudioInputInfo(name: "Microphone", channelCount: 1, isDefault: true)],
        outputFolder: OutputFolderProbe = .usable(.bytes(5))
    ) -> ReadyCheckProbes {
        ReadyCheckProbes(
            screenRecording: { proof in calls.record("screenRecording \(proof)"); return screenRecording },
            microphonePermission: { calls.record("microphonePermission"); return true },
            screens: { calls.record("screens"); return screens },
            audioInputs: { calls.record("audioInputs"); return .success(audioInputs) },
            outputFolder: { folder in
                calls.record("outputFolder \(folder.path(percentEncoded: false))")
                return outputFolder
            })
    }

    private let home = URL(filePath: "/Users/someone", directoryHint: .isDirectory)

    @Test func theScreenRecordingProbeProvesAsAsked() async {
        let calls = Calls()
        _ = await probeReadyCheckFacts(proof: .captureOneFrame, settings: .defaults, homeFolder: home, probes: probes(calls))
        _ = await probeReadyCheckFacts(proof: .listScreens, settings: .defaults, homeFolder: home, probes: probes(calls))
        #expect(calls.names.filter { $0.hasPrefix("screenRecording") } == ["screenRecording captureOneFrame", "screenRecording listScreens"])
    }

    @Test func theFactsAreWhatTheProbesFound() async {
        let calls = Calls()
        let facts = await probeReadyCheckFacts(
            proof: .listScreens, settings: .defaults, homeFolder: home,
            probes: probes(calls, screenRecording: .notGranted, screens: .failure(DeviceReadError("none")),
                           outputFolder: .unusable("read-only")))
        #expect(facts.screenRecording == .notGranted)
        #expect(facts.microphoneGranted == true)
        #expect(facts.screens == .failure(DeviceReadError("none")))
        #expect(facts.audioInputs == .success([AudioInputInfo(name: "Microphone", channelCount: 1, isDefault: true)]))
        #expect(facts.outputFolder == .unusable("read-only"))
    }

    @Test func theOutputFolderIsTheSettingsFolderInTheHomeFolder() async {
        let calls = Calls()
        _ = await probeReadyCheckFacts(proof: .listScreens, settings: .defaults, homeFolder: home, probes: probes(calls))
        #expect(calls.names.contains("outputFolder /Users/someone/Movies/Multi Screen Recorder/"))
    }

    @Test func theMicrophonePermissionIsNotAskedWithTheAudioModeNone() async {
        var settings = Settings.defaults
        settings.auto = false
        settings.audioMode = .none
        let calls = Calls()
        let facts = await probeReadyCheckFacts(proof: .listScreens, settings: settings, homeFolder: home, probes: probes(calls))
        #expect(facts.microphoneGranted == nil)
        #expect(!calls.names.contains("microphonePermission"))
    }

    @Test func autoModeAsksForTheMicrophonePermissionWhateverTheSliderSays() async {
        var settings = Settings.defaults
        settings.audioMode = .none
        let calls = Calls()
        let facts = await probeReadyCheckFacts(proof: .listScreens, settings: settings, homeFolder: home, probes: probes(calls))
        #expect(facts.microphoneGranted == true)
    }

    /// The owner, 2026-11-15: "no mic should just work of course, in any mode."
    @Test(arguments: AudioMode.allCases)
    func withoutAnyAudioInputTheMicrophonePermissionIsNeitherAskedNorRead(mode: AudioMode) async {
        var settings = Settings.defaults
        settings.auto = false
        settings.audioMode = mode
        let calls = Calls()
        let facts = await probeReadyCheckFacts(proof: .listScreens, settings: settings, homeFolder: home, probes: probes(calls, audioInputs: []))
        #expect(facts.microphoneGranted == nil)
        #expect(!calls.names.contains("microphonePermission"))
    }

    @Test func noInputIsRecordedSoThePermissionIsNotAsked() async {
        var settings = Settings.defaults
        settings.auto = false
        settings.audioMode = .defaultMicrophone
        let calls = Calls()
        let notDefault = [AudioInputInfo(name: "USB", channelCount: 1, isDefault: false, transport: .usb)]
        let facts = await probeReadyCheckFacts(proof: .listScreens, settings: settings, homeFolder: home, probes: probes(calls, audioInputs: notDefault))
        #expect(facts.microphoneGranted == nil)
        #expect(!calls.names.contains("microphonePermission"))
    }

    @Test func aRecordedInputAsksForThePermission() async {
        let calls = Calls()
        let facts = await probeReadyCheckFacts(proof: .listScreens, settings: .defaults, homeFolder: home, probes: probes(calls))
        #expect(facts.microphoneGranted == true)
        #expect(calls.names.contains("microphonePermission"))
    }

    @Test func fileAccessIsOffTheMainThreadAndTheScreensAreOnIt() async {
        let calls = Calls()
        _ = await probeReadyCheckFacts(proof: .listScreens, settings: .defaults, homeFolder: home, probes: probes(calls))
        #expect(calls.names.contains("screens"))
        #expect(calls.namesOnTheMainThread == ["screens"])
    }

    @MainActor @Test func fileAccessIsOffTheMainThreadAlsoWhenTheCallerIsOnIt() async {
        let calls = Calls()
        _ = await probeReadyCheckFacts(proof: .listScreens, settings: .defaults, homeFolder: home, probes: probes(calls))
        #expect(calls.names.contains { $0.hasPrefix("outputFolder") })
        #expect(calls.namesOnTheMainThread == ["screens"])
    }
}
