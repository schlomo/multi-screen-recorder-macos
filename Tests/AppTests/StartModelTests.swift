import Foundation
import RecorderCore
import RecorderLogic
import Testing
@testable import msr

/// The start window's model with stand-in probes: what happens on device
/// changes, with a menu that holds the window's content still while it is open.
@MainActor
@Suite struct StartModelTests {
    /// Counts the ready checks the stand-in probes were run for.
    final class Probed: @unchecked Sendable {
        private let lock = NSLock()
        private var proofs: [ScreenRecordingProof] = []
        var checks: Int { lock.withLock { proofs.count } }
        var proofsRun: [ScreenRecordingProof] { lock.withLock { proofs } }
        func ran(_ proof: ScreenRecordingProof) { lock.withLock { proofs.append(proof) } }
    }

    private static let settleTime = Duration.milliseconds(30)
    /// Long enough for a notice's settle time and the check after it.
    private static let settled = 0.15

    /// Stands in for the main run loop's default mode: while a menu is open
    /// an action waits, and runs when it closes. That the real hold works is
    /// tested in `MainRunLoopTests`.
    @MainActor final class Menu {
        var isOpen = false
        private var waiting: [@MainActor () -> Void] = []

        func whenContentMayChange(_ action: @escaping @MainActor () -> Void) {
            if isOpen { waiting.append(action) } else { action() }
        }

        func close() {
            isOpen = false
            let actions = waiting
            waiting = []
            actions.forEach { $0() }
        }
    }

    private let home: URL
    private let probed = Probed()
    private let menu = Menu()

    init() {
        home = FileManager.default.temporaryDirectory.appending(path: "StartModel-\(UUID().uuidString)", directoryHint: .isDirectory)
    }

    private func makeModel(settleTime: Duration = settleTime) -> StartModel {
        let probed = probed
        let probes = ReadyCheckProbes(
            screenRecording: { proof in probed.ran(proof); return .granted },
            microphonePermission: { true },
            screens: { .success(DesignExample.screens) },
            audioInputs: { .success(DesignExample.audioInputs) },
            outputFolder: { _ in .usable(.bytes(100_000_000_000)) },
            cameras: { [] },
            cameraPermission: { true })
        let menu = menu
        return StartModel(
            homeFolder: home, probes: probes, settleTime: settleTime,
            whenContentMayChange: { menu.whenContentMayChange($0) })
    }

    /// Lets the tasks of the model run, `seconds` long.
    private func wait(_ seconds: Double) async {
        try? await Task.sleep(for: .seconds(seconds))
    }

    /// Waits until `condition` holds, at most 3 s.
    private func waitUntil(_ condition: () -> Bool) async {
        for _ in 0..<600 where !condition() { try? await Task.sleep(for: .milliseconds(5)) }
    }

    /// macOS's prompts come when the app starts and at "Check again", never at Start (D46).
    @Test func theStartAndCheckAgainCaptureAFrameAndDeviceChangesDoNot() async {
        let model = makeModel()
        model.load()
        await waitUntil { model.readyCheck != nil }
        model.checkAgain()
        await waitUntil { probed.checks == 2 }
        model.devicesChanged()
        await waitUntil { probed.checks == 3 }
        model.change { $0.systemAudio.toggle() }
        await waitUntil { probed.checks == 4 }
        #expect(probed.proofsRun == [.captureOneFrame, .captureOneFrame, .listScreens, .listScreens])
    }

    @Test func aBurstOfDeviceChangesGivesOneCheck() async {
        let model = makeModel()
        for _ in 0..<5 { model.devicesChanged() }
        await waitUntil { model.readyCheck != nil }
        await wait(Self.settled)
        #expect(probed.checks == 1)
    }

    @Test func aBurstSpreadOverSeveralNoticesWithinTheSettleTimeGivesOneCheck() async {
        let model = makeModel(settleTime: .milliseconds(100))
        for _ in 0..<4 {
            model.devicesChanged()
            await wait(0.01)
        }
        await waitUntil { model.readyCheck != nil }
        await wait(Self.settled)
        #expect(probed.checks == 1)
    }

    @Test func noticesFarApartEachGiveACheck() async {
        let model = makeModel()
        model.devicesChanged()
        await waitUntil { probed.checks == 1 }
        await wait(Self.settled)
        model.devicesChanged()
        await waitUntil { probed.checks == 2 }
        await wait(Self.settled)
        #expect(probed.checks == 2)
    }

    @Test func nothingIsAppliedWhileAMenuIsOpen() async {
        let model = makeModel()
        menu.isOpen = true
        model.devicesChanged()
        await wait(Self.settled * 2)
        #expect(probed.checks == 0)
        #expect(model.whatWillBeRecorded == nil)
        #expect(model.readyCheck == nil)
        menu.close()
        await waitUntil { model.readyCheck != nil }
        #expect(probed.checks == 1)
        #expect(model.whatWillBeRecorded?.total != nil)
    }

    @Test func aCheckStartedBeforeTheMenuOpenedShowsItsResultOnlyAfterItCloses() async {
        let model = makeModel()
        model.load()
        menu.isOpen = true
        await waitUntil { probed.checks == 1 }
        await wait(Self.settled)
        #expect(model.readyCheck == nil)
        #expect(model.isChecking)
        menu.close()
        await waitUntil { model.readyCheck != nil }
        #expect(model.readyCheck != nil)
        #expect(!model.isChecking)
    }

    /// Copilot's finding on PR #1: a refresh queued for the window outlived a
    /// newer device notice, so the devices were read once too early and once
    /// more after they settled.
    @Test func aRefreshQueuedUnderAMenuIsOvertakenByANewerNotice() async {
        let model = makeModel()
        menu.isOpen = true
        model.devicesChanged()
        await wait(Self.settled)
        model.devicesChanged()
        await wait(Self.settled)
        menu.close()
        await waitUntil { model.readyCheck != nil }
        await wait(Self.settled)
        #expect(probed.checks == 1)
    }

    @Test func aChangedChoiceIsSavedAndChecked() async {
        defer { try? FileManager.default.removeItem(at: home) }
        let model = makeModel()
        model.change { $0.auto = false }
        await waitUntil { model.readyCheck != nil }
        #expect(probed.checks == 1)
        #expect(SettingsFile.standard(homeFolder: home).load().settings.auto == false)
        #expect(model.saveError == nil)
    }

    @Test func nothingIsWrittenUntilAChoiceChanges() async {
        defer { try? FileManager.default.removeItem(at: home) }
        let model = makeModel()
        model.load()
        await waitUntil { model.readyCheck != nil }
        #expect(!FileManager.default.fileExists(atPath: SettingsFile.standard(homeFolder: home).url.path(percentEncoded: false)))
    }

    @Test func aSettingsFileThatCannotBeUsedIsNotRefused() async throws {
        defer { try? FileManager.default.removeItem(at: home) }
        let file = SettingsFile.standard(homeFolder: home)
        try FileManager.default.createDirectory(at: file.url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("garbage".utf8).write(to: file.url)
        let model = makeModel()
        model.load()
        await waitUntil { model.readyCheck != nil }
        #expect(model.settings == .defaults)
        #expect(model.readyCheck != nil)
        #expect(try String(contentsOf: file.url, encoding: .utf8) == "garbage")
    }

    @Test func aSaveThatFailsIsSaidAndTheChoiceStillApplies() async throws {
        defer { try? FileManager.default.removeItem(at: home) }
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        try Data().write(to: home.appending(path: "Library"))
        let model = makeModel()
        model.change { $0.systemAudio = false }
        #expect(model.saveError?.contains("cannot be written") == true)
        #expect(model.settings.systemAudio == false)
    }
    // MARK: While recording (D45)

    @Test func whileRecordingNoDeviceChangeOrActivationRunsTheReadyCheck() async {
        let model = makeModel()
        model.checkAgain()
        await waitUntil { model.readyCheck != nil }
        let before = probed.checks
        model.recordingStarted()
        model.devicesChanged()
        model.appBecameActive()
        model.checkAgain()
        await wait(Self.settled)
        #expect(probed.checks == before)
        #expect(model.isRecording)
    }

    @Test func aRefreshQueuedBeforeTheStartDoesNothingOnceRecording() async {
        let model = makeModel()
        model.devicesChanged()
        model.recordingStarted()
        await wait(Self.settled)
        #expect(probed.checks == 0)
    }

    @Test func startIsPossibleOnlyWhenTheReadyCheckPasses() async {
        let model = makeModel()
        #expect(!model.canStart)
        model.checkAgain()
        await waitUntil { model.readyCheck != nil }
        #expect(model.canStart)
        model.recordingStarted()
        #expect(!model.canStart)
    }
}

/// The screens and audio inputs of the examples in docs/design/recorder.md.
enum DesignExample {
    static let screens = [
        ScreenInfo(name: "Built-in Retina Display", pixelSize: FrameSize(width: 3456, height: 2234), pointSize: FrameSize(width: 1728, height: 1117), isMain: true, originX: 0, originY: 0),
    ]
    static let audioInputs = [AudioInputInfo(name: "MacBook Pro Microphone", channelCount: 1, isDefault: true)]
}
