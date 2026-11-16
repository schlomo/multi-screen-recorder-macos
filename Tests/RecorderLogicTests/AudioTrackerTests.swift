import Testing
@testable import RecorderLogic

@Suite struct AudioTrackerTests {
    private let second: Int64 = 1_000_000_000

    private func settings(_ mode: AudioMode, systemAudio: Bool = false) -> Settings {
        var settings = Settings.defaults
        settings.auto = false
        settings.audioMode = mode
        settings.systemAudio = systemAudio
        return settings
    }

    private let builtIn = AudioInputInfo(name: "MacBook Pro Microphone", channelCount: 1, isDefault: true, transport: .builtIn, uid: "BuiltIn")
    private let usb = AudioInputInfo(name: "Razer Seiren V3 Mini", channelCount: 1, isDefault: false, transport: .usb, uid: "Razer")
    private let headset = AudioInputInfo(name: "AirPods", channelCount: 1, isDefault: false, transport: .bluetooth, uid: "AirPods")

    private func names(_ events: [RecordingEvent]) -> [String] {
        events.map { "\($0.event.rawValue)" + ($0.audioSource.map { ": \($0)" } ?? "") }
    }

    @Test func atTheStartTheAudioModesInputsAndTheSystemAudioStartAtOnce() {
        var tracker = AudioTracker(settings: settings(.wired, systemAudio: true))
        let step = tracker.begin(inputs: [builtIn, usb, headset], mainDisplayID: 1, at: 0)
        #expect(step.events.isEmpty)
        #expect(step.actions == [
            .startInput(uid: "BuiltIn", name: "MacBook Pro Microphone"),
            .startInput(uid: "Razer", name: "Razer Seiren V3 Mini"),
            .startSystemAudio,
        ])
    }

    @Test func theAudioModeNoneRecordsNoInput() {
        var tracker = AudioTracker(settings: settings(.none))
        #expect(tracker.begin(inputs: [builtIn, usb], mainDisplayID: 1, at: 0) == AudioTracker.Step())
        #expect(tracker.nextDueTime() == nil)
    }

    @Test func anInputThatAppearsStartsAfterTheSettleTime() {
        var tracker = AudioTracker(settings: settings(.wired))
        _ = tracker.begin(inputs: [builtIn], mainDisplayID: 1, at: 0)
        let appeared = tracker.observe([builtIn, usb], at: 5 * second)
        #expect(names(appeared.events) == ["audio input connected: Razer Seiren V3 Mini"])
        #expect(appeared.actions.isEmpty)
        #expect(tracker.nextDueTime() == 6 * second)
        #expect(tracker.due(at: 6 * second).actions == [.startInput(uid: "Razer", name: "Razer Seiren V3 Mini")])
    }

    @Test func anInputThatDisconnectsEndsItsFileAndAReplugStartsANewOne() {
        var tracker = AudioTracker(settings: settings(.wired))
        _ = tracker.begin(inputs: [builtIn, usb], mainDisplayID: 1, at: 0)
        // The capture sees the unplug first, the device list follows.
        let ended = tracker.captureEnded(.input("Razer"), .disconnected, at: 10 * second)
        #expect(names(ended.events) == ["audio input disconnected: Razer Seiren V3 Mini"])
        let gone = tracker.observe([builtIn], at: 10 * second + 1)
        #expect(gone.events.isEmpty)
        #expect(gone.actions.isEmpty)
        #expect(tracker.due(at: 20 * second).actions.isEmpty)
        #expect(tracker.sourcesShown.first { $0.id == .input("Razer") }?.state == .disconnected)
        let back = tracker.observe([builtIn, usb], at: 27 * second)
        #expect(names(back.events) == ["audio input connected: Razer Seiren V3 Mini"])
        #expect(tracker.due(at: 28 * second).actions == [.startInput(uid: "Razer", name: "Razer Seiren V3 Mini")])
    }

    @Test func anInputGoneFromTheListIsStoppedWithItsEvent() {
        var tracker = AudioTracker(settings: settings(.wired))
        _ = tracker.begin(inputs: [builtIn, usb], mainDisplayID: 1, at: 0)
        let gone = tracker.observe([builtIn], at: 3 * second)
        #expect(names(gone.events) == ["audio input disconnected: Razer Seiren V3 Mini"])
        #expect(gone.actions == [.stop(.input("Razer"))])
        // The capture's own end afterwards changes nothing.
        #expect(tracker.captureEnded(.input("Razer"), .disconnected, at: 3 * second) == AudioTracker.Step())
    }

    @Test func theDefaultMicrophoneIsFollowed() {
        var tracker = AudioTracker(settings: settings(.defaultMicrophone))
        #expect(tracker.begin(inputs: [builtIn, usb], mainDisplayID: 1, at: 0).actions
            == [.startInput(uid: "BuiltIn", name: "MacBook Pro Microphone")])
        var newBuiltIn = builtIn
        newBuiltIn.isDefault = false
        var newUSB = usb
        newUSB.isDefault = true
        let changed = tracker.observe([newBuiltIn, newUSB], at: 4 * second)
        #expect(names(changed.events) == ["default microphone changed"])
        #expect(changed.events.first?.from == "MacBook Pro Microphone")
        #expect(changed.events.first?.to == "Razer Seiren V3 Mini")
        #expect(changed.actions == [.stop(.input("BuiltIn"))])
        #expect(tracker.due(at: 5 * second).actions == [.startInput(uid: "Razer", name: "Razer Seiren V3 Mini")])
    }

    @Test func aFailingCaptureIsAFailureAndStartsAgainWithTheBackOff() {
        var tracker = AudioTracker(settings: settings(.defaultMicrophone))
        _ = tracker.begin(inputs: [builtIn], mainDisplayID: 1, at: 0)
        let failed = tracker.captureEnded(.input("BuiltIn"), .captureFailed("boom"), at: 2 * second)
        #expect(names(failed.events) == ["audio input failed: MacBook Pro Microphone"])
        #expect(failed.events.first?.error == "boom")
        #expect(failed.events.first?.event.isFailure == true)
        #expect(tracker.nextDueTime() == 3 * second)
        #expect(tracker.due(at: 3 * second).actions.count == 1)
        _ = tracker.captureEnded(.input("BuiltIn"), .captureFailed("boom"), at: 4 * second)
        #expect(tracker.nextDueTime() == 6 * second)
        tracker.fileStarted(.input("BuiltIn"))
    }

    @Test func aDisconnectIsNoFailure() {
        #expect(!RecordingEvent.Kind.audioInputDisconnected.isFailure)
        #expect(!RecordingEvent.Kind.audioInputGap.isFailure)
        #expect(RecordingEvent.Kind.audioFileWriterFailed.isFailure)
        #expect(RecordingEvent.Kind.systemAudioFailed.isFailure)
    }

    @Test func theSystemAudioMovesToTheNewMainDisplayWhenItsDisplayGoes() {
        var tracker = AudioTracker(settings: settings(.none, systemAudio: true))
        #expect(tracker.begin(inputs: [], mainDisplayID: 1, at: 0).actions == [.startSystemAudio])
        tracker.systemAudioCaptures(displayID: 1)
        #expect(tracker.observeDisplays(mainDisplayID: 1, connected: [1, 2], at: second) == AudioTracker.Step())
        let moved = tracker.observeDisplays(mainDisplayID: 2, connected: [2], at: 2 * second)
        #expect(names(moved.events) == ["system audio stopped: System audio"])
        #expect(moved.actions == [.stop(.systemAudio)])
        let started = tracker.due(at: 3 * second)
        #expect(names(started.events) == ["system audio started: System audio"])
        #expect(started.actions == [.startSystemAudio])
    }

    @Test func anEventAboutAnAudioSourceNamesItAsAudioSourceNeverAsDisplay() {
        var tracker = AudioTracker(settings: settings(.wired))
        _ = tracker.begin(inputs: [builtIn], mainDisplayID: 1, at: 0)
        let appeared = tracker.observe([builtIn, usb], at: second).events
        #expect(appeared.map(\.audioSource) == ["Razer Seiren V3 Mini"])
        #expect(appeared.map(\.display) == [nil])
    }

    @Test func anInputLostAgainWithoutADeviceChangeIsAFailure() {
        var tracker = AudioTracker(settings: settings(.wired))
        _ = tracker.begin(inputs: [builtIn, usb], mainDisplayID: 1, at: 0)
        #expect(names(tracker.captureEnded(.input("Razer"), .disconnected, at: second).events)
            == ["audio input disconnected: Razer Seiren V3 Mini"])
        // Still listed: tried again after the back-off, and lost again with no notice.
        #expect(tracker.due(at: 2 * second).actions == [.startInput(uid: "Razer", name: "Razer Seiren V3 Mini")])
        let again = tracker.captureEnded(.input("Razer"), .disconnected, at: 3 * second)
        #expect(names(again.events) == ["audio input failed: Razer Seiren V3 Mini"])
        #expect(again.events.first?.error == AudioTracker.sourceLostAgain(.input("Razer")))
        #expect(again.events.first?.event.isFailure == true)
        #expect(tracker.nextDueTime() == 5 * second)
        #expect(tracker.sourcesShown.first { $0.id == .input("Razer") }?.state == .failedRetrying)
    }

    @Test func anInputLostAfterTheDeviceListChangedIsNoFailure() {
        var tracker = AudioTracker(settings: settings(.wired))
        _ = tracker.begin(inputs: [builtIn, usb], mainDisplayID: 1, at: 0)
        _ = tracker.captureEnded(.input("Razer"), .disconnected, at: second)
        _ = tracker.observe([builtIn], at: 2 * second)
        _ = tracker.observe([builtIn, usb], at: 3 * second)
        #expect(tracker.due(at: 4 * second).actions.count == 1)
        #expect(names(tracker.captureEnded(.input("Razer"), .disconnected, at: 5 * second).events)
            == ["audio input disconnected: Razer Seiren V3 Mini"])
    }

    @Test func theSystemAudioLostAgainWithoutADisplayChangeIsAFailure() {
        var tracker = AudioTracker(settings: settings(.none, systemAudio: true))
        _ = tracker.begin(inputs: [], mainDisplayID: 1, at: 0)
        _ = tracker.observeDisplays(mainDisplayID: 1, connected: [1], at: 0)
        #expect(names(tracker.captureEnded(.systemAudio, .disconnected, at: second).events) == ["system audio stopped: System audio"])
        #expect(tracker.due(at: 2 * second).actions == [.startSystemAudio])
        let again = tracker.captureEnded(.systemAudio, .disconnected, at: 3 * second)
        #expect(names(again.events) == ["system audio failed: System audio"])
        #expect(again.events.first?.error == AudioTracker.sourceLostAgain(.systemAudio))
        // After a display change, a lost stream is a move again, no failure.
        #expect(tracker.due(at: 10 * second).actions == [.startSystemAudio])
        _ = tracker.observeDisplays(mainDisplayID: 2, connected: [1, 2], at: 11 * second)
        #expect(names(tracker.captureEnded(.systemAudio, .disconnected, at: 12 * second).events) == ["system audio stopped: System audio"])
    }

    @Test func aWriterThatFellBehindIsAFailureAndStartsAgain() {
        var tracker = AudioTracker(settings: settings(.defaultMicrophone))
        _ = tracker.begin(inputs: [builtIn], mainDisplayID: 1, at: 0)
        let behind = tracker.captureEnded(.input("BuiltIn"), .writerFellBehind, at: second)
        #expect(names(behind.events) == ["audio file writer fell behind: MacBook Pro Microphone"])
        #expect(behind.events.first?.event.isFailure == true)
        #expect(tracker.nextDueTime() == 2 * second)
    }

    @Test func aFormerDefaultMicrophoneDefaultAgainWaitsTheSettleTime() {
        var tracker = AudioTracker(settings: settings(.defaultMicrophone))
        _ = tracker.begin(inputs: [builtIn, usb], mainDisplayID: 1, at: 0)
        var otherBuiltIn = builtIn
        otherBuiltIn.isDefault = false
        var defaultUSB = usb
        defaultUSB.isDefault = true
        _ = tracker.observe([otherBuiltIn, defaultUSB], at: 4 * second)
        _ = tracker.due(at: 5 * second)
        let back = tracker.observe([builtIn, usb], at: 8 * second)
        #expect(back.actions == [.stop(.input("Razer"))])
        #expect(tracker.due(at: 8 * second).actions.isEmpty)
        #expect(tracker.nextDueTime() == 9 * second)
        #expect(tracker.due(at: 9 * second).actions == [.startInput(uid: "BuiltIn", name: "MacBook Pro Microphone")])
    }

    @Test func aFullDiskWaitsForRoom() {
        var tracker = AudioTracker(settings: settings(.defaultMicrophone))
        _ = tracker.begin(inputs: [builtIn], mainDisplayID: 1, at: 0)
        #expect(names(tracker.captureEnded(.input("BuiltIn"), .diskFull, at: second).events) == ["disk full: MacBook Pro Microphone"])
        #expect(tracker.isWaitingForRoom)
        #expect(tracker.due(at: 10 * second).actions.isEmpty)
        tracker.roomAgain()
        #expect(tracker.due(at: 11 * second).actions.count == 1)
    }

    @Test func aChannelCountChangeStartsANewFile() {
        var tracker = AudioTracker(settings: settings(.defaultMicrophone))
        _ = tracker.begin(inputs: [builtIn], mainDisplayID: 1, at: 0)
        var stereo = builtIn
        stereo.channelCount = .success(2)
        #expect(tracker.observe([stereo], at: second).actions == [.stop(.input("BuiltIn"))])
        #expect(tracker.due(at: 2 * second).actions == [.startInput(uid: "BuiltIn", name: "MacBook Pro Microphone")])
    }

    @Test func anInputWithoutAUIDCannotBeRecordedAndSaysSo() {
        var tracker = AudioTracker(settings: settings(.defaultMicrophone))
        var noUID = builtIn
        noUID.uid = nil
        #expect(tracker.begin(inputs: [noUID], mainDisplayID: 1, at: 0).notRecordable == ["MacBook Pro Microphone"])
    }

    @Test func twoInputsWithTheSameNameAreNumbered() {
        var tracker = AudioTracker(settings: settings(.allInputs))
        let twin = AudioInputInfo(name: "MacBook Pro Microphone", channelCount: 1, isDefault: false, transport: .usb, uid: "Twin")
        #expect(tracker.begin(inputs: [builtIn, twin], mainDisplayID: 1, at: 0).actions == [
            .startInput(uid: "BuiltIn", name: "MacBook Pro Microphone"),
            .startInput(uid: "Twin", name: "MacBook Pro Microphone (2)"),
        ])
    }

    @Test func sleepEndsEveryAudioFileAndWakeStartsThemAgain() {
        var tracker = AudioTracker(settings: settings(.defaultMicrophone, systemAudio: true))
        _ = tracker.begin(inputs: [builtIn], mainDisplayID: 1, at: 0)
        #expect(tracker.sleep() == [.stop(.input("BuiltIn")), .stop(.systemAudio)])
        #expect(tracker.nextDueTime() == nil)
        let woke = tracker.wake([builtIn], at: 100 * second)
        #expect(woke.actions.isEmpty)
        #expect(tracker.due(at: 101 * second).actions.count == 2)
    }
}
