import Foundation
import Testing
@testable import EndToEndLogic

/// A recording folder as the recorder writes it after the virtual-screen
/// scenario with the test tone: one of the Mac's own screens, a virtual
/// screen whose mode is switched once, the loopback device and the system audio. Each
/// test breaks one thing and expects the check to name it.
struct SampleRecording {
    static let virtualUUID = "122787BA-50AA-4A5A-B00C-3F98867665AF"
    var manifest: [String: Any]

    init(killed: Bool = false) {
        let started = "2026-11-19T08:27:21.700+01:00"
        func file(_ name: String, start: Double, end: Double, timecode: String) -> [String: Any] {
            ["name": name, "start": start, "end": killed ? NSNull() : end, "timecode": timecode,
             "state": killed ? "recording" : "finalized"]
        }
        func screen(_ name: String, screen: String, uuid: String, size: [Int], start: Double, end: Double, timecode: String) -> [String: Any] {
            file(name, start: start, end: end, timecode: timecode).merging([
                "screen": screen, "screenUUID": uuid, "frameSize": size, "guideTracks": ["Audio inputs", "System audio"],
                "framesRepeatedForLateness": 3,
            ]) { first, _ in first }
        }
        func audio(_ name: String, source: String, uid: String?, channels: Any, start: Double, end: Double, timecode: String) -> [String: Any] {
            var entry = file(name, start: start, end: end, timecode: timecode).merging([
                "audioSource": source, "channels": channels,
                "clockDriftCorrection": killed ? NSNull() : 0.0, "clockDriftPpm": NSNull(),
            ]) { first, _ in first }
            if let uid {
                entry["audioSourceUID"] = uid
                entry["inputVolume"] = 1.0
            }
            return entry
        }
        manifest = [
            "app": "Multi Screen Recorder 0.20261119.65 (6ffc65f)",
            "state": killed ? "recording" : "finalized",
            "started": started,
            "ended": killed ? NSNull() : "2026-11-19T08:27:39.000+01:00",
            "result": killed ? NSNull() : "ok",
            "cpu": killed ? NSNull() : ["averagePercent": 32.0, "peakPercent": 129.0] as [String: Any],
            "settings": ["resolution": "1080p", "audioMode": "all-inputs", "systemAudio": true] as [String: Any],
            "files": [
                screen("2026-11-19 08.27.21 Screen 1 - DELL P3421W.mov", screen: "DELL P3421W",
                       uuid: "A95C2BA6-2796-4EDF-919B-66A6C21CE71F", size: [1920, 802], start: 0.1333333, end: 17.0333333,
                       timecode: "08:27:21:25"),
                audio("2026-11-19 08.27.22 Audio 0 - System.mov", source: "System audio", uid: nil, channels: "stereo",
                      start: 0.4, end: 17.08, timecode: "08:27:22:03"),
                audio("2026-11-19 08.27.22 Audio 1 - BlackHole 2ch.mov", source: "BlackHole 2ch", uid: "BlackHole2ch_UID",
                      channels: 2, start: 0.4, end: 17.08, timecode: "08:27:22:03"),
                screen("2026-11-19 08.27.25 Screen 2 - Portable Monitor.mov", screen: "Portable Monitor", uuid: Self.virtualUUID,
                       size: [1280, 720], start: 3.4, end: 7.3, timecode: "08:27:25:03"),
                screen("2026-11-19 08.27.29 Screen 2 - Portable Monitor.mov", screen: "Portable Monitor", uuid: Self.virtualUUID,
                       size: [1600, 900], start: 7.3666667, end: 11.2666667, timecode: "08:27:29:02"),
            ],
            "events": [
                ["at": 2.226, "event": "screen connected", "screen": "Portable Monitor"],
                ["at": 7.204, "event": "screen frame size changed", "screen": "Portable Monitor", "from": [1280, 720], "to": [1600, 900]],
                ["at": 11.242, "event": "screen disconnected", "screen": "Portable Monitor"],
            ],
            "problems": [] as [Any],
        ]
    }

    var files: [[String: Any]] {
        get { manifest["files"] as! [[String: Any]] }
        set { manifest["files"] = newValue }
    }

    var folder: [String] { files.map { $0["name"] as! String } + ["recording.json", "recording.log"] }

    var json: JSONValue { try! JSONValue(json: JSONSerialization.data(withJSONObject: manifest)) }

    static let connect = ChangeTimes(asked: 2.0, done: 2.2)
    static let modeSwitch = ChangeTimes(asked: 6.0, done: 6.2)
    static let disconnect = ChangeTimes(asked: 11.0, done: 11.24)

    static func expectation(killedAt: Double? = nil) -> ManifestExpectation {
        ManifestExpectation(
            app: "Multi Screen Recorder 0.20261119.65 (6ffc65f)",
            settings: .init(resolution: "1080p", audioMode: "all-inputs", systemAudio: true),
            ending: killedAt.map { .killed(at: $0) } ?? .finalized, stoppedAt: killedAt ?? 17, ownScreenCount: 1,
            virtualScreenNames: ["Portable Monitor"],
            virtualScreenFiles: [
                .init(screenUUID: virtualUUID, frameSize: [1280, 720], startedBy: connect, noticedBy: 0,
                      endedBy: .init(change: modeSwitch, kind: .settled)),
                .init(screenUUID: virtualUUID, frameSize: [1600, 900], startedBy: modeSwitch, noticedBy: nil,
                      endedBy: .init(change: disconnect, kind: .immediate)),
            ],
            virtualScreenEvents: [
                .init(event: "screen connected", expected: .init(change: connect, kind: .immediate)),
                .init(event: "screen frame size changed", expected: .init(change: modeSwitch, kind: .settled)),
                .init(event: "screen disconnected", expected: .init(change: disconnect, kind: .immediate)),
            ],
            playedAudioInputs: [.init(name: "BlackHole 2ch", uid: "BlackHole2ch_UID", channels: 2)],
            timeTolerance: 0.5, finalizeAllowance: 3, settleTime: 1, firstFrameLimit: 1)
    }

    func check(_ expectation: ManifestExpectation = expectation(), folder: [String]? = nil) -> ManifestCheck {
        ManifestCheck(manifest: json, folder: folder ?? self.folder, expectation: expectation)
    }
}

@Suite struct ManifestCheckTests {
    @Test func aRecordingAsTheRecorderWritesItPasses() {
        let check = SampleRecording().check()
        #expect(check.failures == [])
        #expect(check.files.count == 5)
        #expect(check.files[3].label == "Screen 2 - Portable Monitor")
        #expect(check.files[1].source == .systemAudio)
    }

    @Test func aKilledRecordingPassesAsKilled() {
        #expect(SampleRecording(killed: true).check(SampleRecording.expectation(killedAt: 12)).failures == [])
    }

    @Test func aKilledRecordingIsNotAFinalizedOne() {
        let failures = SampleRecording(killed: true).check().failures
        #expect(failures.contains("state is \"recording\", expected \"finalized\""))
        #expect(failures.contains("result is null, expected \"ok\""))
        #expect(failures.contains { $0.hasSuffix("state is recording, expected finalized") })
    }

    @Test func aFinalizedRecordingIsNotAKilledOne() {
        let failures = SampleRecording().check(SampleRecording.expectation(killedAt: 12)).failures
        #expect(failures.contains("ended after a kill is \"2026-11-19T08:27:39.000+01:00\", expected null"))
        #expect(failures.contains { $0.hasSuffix("end after a kill is 17.08, expected null") })
    }

    @Test func theTimelineFileIsNoRecordedFile() {
        let sample = SampleRecording()
        #expect(sample.check(folder: sample.folder + ["2026-11-19 08-27-30.otio"]).failures.isEmpty)
    }

    @Test func aFileMissingFromTheManifestOrTheFolderFails() {
        let sample = SampleRecording()
        let extra = sample.check(folder: sample.folder + ["2026-11-19 08.27.30 Screen 3 - Other.mov"]).failures
        #expect(extra == ["2026-11-19 08.27.30 Screen 3 - Other.mov is in the recording folder but not in files"])
        let missing = sample.check(folder: sample.folder.filter { !$0.contains("System") }).failures
        #expect(missing == ["2026-11-19 08.27.22 Audio 0 - System.mov is in files but not in the recording folder"])
        let noManifest = sample.check(folder: sample.folder.filter { $0 != "recording.json" }).failures
        #expect(noManifest == ["the recording folder has no recording.json"])
        let noLog = sample.check(folder: sample.folder.filter { $0 != "recording.log" }).failures
        #expect(noLog == ["the recording folder has no recording.log"])
    }

    @Test func aProblemWithoutItsErrorDetailFails() {
        var sample = SampleRecording()
        sample.manifest["problems"] = [["at": 1.0, "problem": "p", "error": NSNull()]]
        #expect(sample.check().failures.contains { $0.contains("a problem has the keys") })
    }

    @Test func otherSettingsOrAnotherAppFail() {
        var sample = SampleRecording()
        sample.manifest["settings"] = ["resolution": "native", "audioMode": "all-inputs", "systemAudio": true]
        sample.manifest["app"] = "Multi Screen Recorder 0.1 (abc)"
        let failures = sample.check().failures
        #expect(failures.count == 2)
        #expect(failures.contains { $0.hasPrefix("settings is") })
        #expect(failures.contains("app is \"Multi Screen Recorder 0.1 (abc)\", expected \"Multi Screen Recorder 0.20261119.65 (6ffc65f)\""))
    }

    @Test func aMissingOrExtraKeyFails() {
        var sample = SampleRecording()
        sample.manifest["extra"] = 1
        sample.files[0]["framesRepeatedForLateness"] = nil
        sample.files[2]["note"] = "x"
        let failures = sample.check().failures
        #expect(failures.contains { $0.hasPrefix("recording.json has the keys") })
        #expect(failures.contains { $0.hasPrefix("2026-11-19 08.27.21 Screen 1 - DELL P3421W.mov: the keys are") })
        #expect(failures.contains { $0.hasPrefix("2026-11-19 08.27.22 Audio 1 - BlackHole 2ch.mov: the keys are") })
    }

    @Test func aWrongTimecodeFails() {
        var sample = SampleRecording()
        sample.files[3]["timecode"] = "08:27:25:04"
        #expect(sample.check().failures == [
            "2026-11-19 08.27.25 Screen 2 - Portable Monitor.mov: timecode is 08:27:25:04, expected 08:27:25:03 from started and start",
        ])
    }

    @Test func aNameWhoseTimeIsNotTheFilesStartFails() {
        var sample = SampleRecording()
        let renamed = "2026-11-19 08.27.27 Screen 2 - Portable Monitor.mov"
        sample.files[3]["name"] = renamed
        #expect(sample.check().failures == ["\(renamed): the name's time is not the file's start, 3.4 s after the recording's start"])
    }

    @Test func aScreenThatChangesItsNumberOrSharesOneFails() {
        var sample = SampleRecording()
        sample.files[4]["name"] = "2026-11-19 08.27.29 Screen 3 - Portable Monitor.mov"
        #expect(sample.check().failures.contains { $0.hasSuffix("changed its number") })
        var shared = SampleRecording()
        shared.files[3]["name"] = "2026-11-19 08.27.25 Screen 1 - Portable Monitor.mov"
        shared.files[4]["name"] = "2026-11-19 08.27.29 Screen 1 - Portable Monitor.mov"
        let failures = shared.check().failures
        #expect(failures.contains { $0.hasPrefix("two screens share a number") })
        #expect(failures.contains("the first virtual screen is screen 1, expected 2, after the Mac's own"))
    }

    @Test func aLabelThatIsNotTheSourcesFails() {
        var sample = SampleRecording()
        sample.files[1]["name"] = "2026-11-19 08.27.22 Audio 3 - System.mov"
        sample.files[2]["name"] = "2026-11-19 08.27.22 Audio 1 - BlackHole.mov"
        let failures = sample.check().failures
        #expect(failures.contains("2026-11-19 08.27.22 Audio 3 - System.mov: the label is not Audio 0 - System"))
        #expect(failures.contains("2026-11-19 08.27.22 Audio 1 - BlackHole.mov: the label is not \"Audio <n> - BlackHole 2ch\""))
    }

    @Test func aSlashOrColonInANameBecomesADash() {
        var sample = SampleRecording()
        sample.files[0]["screen"] = "DELL: P3421W/2"
        sample.files[0]["name"] = "2026-11-19 08.27.21 Screen 1 - DELL- P3421W-2.mov"
        #expect(sample.check().failures == [])
    }

    @Test func aVirtualScreenAtTheWrongSizeOrTimeFails() {
        var sample = SampleRecording()
        sample.files[4]["frameSize"] = [1280, 720]
        // The recorder noticed the connect at 2.226 s: its file starts the
        // settle time later, within the tolerance; at 2.4 s it ignored it.
        sample.files[3]["start"] = 2.4
        sample.files[3]["name"] = "2026-11-19 08.27.24 Screen 2 - Portable Monitor.mov"
        sample.files[3]["timecode"] = "08:27:24:03"
        let failures = sample.check().failures
        #expect(failures.contains("2026-11-19 08.27.29 Screen 2 - Portable Monitor.mov: frameSize [1280, 720], expected [1600, 900]"))
        #expect(failures.contains(
            "2026-11-19 08.27.24 Screen 2 - Portable Monitor.mov: starts at 2.40 s, expected 2.73 s to 4.23 s, the settle time after the recorder's notice at 2.23 s"))
    }

    @Test func aFileStartBeforeItsScreenSettledFails() {
        // The virtual screen last changed at 3.0 s, after the recorder's notice:
        // its file starts from 3.5 s on, so 3.4 s fails though after the notice plus the settle time.
        var expectation = SampleRecording.expectation()
        expectation.virtualScreenFiles[0].startedBy.lastChange = 3.0
        #expect(SampleRecording().check(expectation).failures == [
            "2026-11-19 08.27.25 Screen 2 - Portable Monitor.mov: starts at 3.40 s, expected 3.50 s to 5.00 s, the settle time after the screen's last change at 3.00 s",
        ])
    }

    /// The sample with the connect noticed at `notice` and the first virtual screen file starting at `start`;
    /// the driver saw the screen last change at 2.05 s.
    func connect(noticedAt notice: Double, startingAt start: Double) -> [String] {
        var sample = SampleRecording()
        var events = sample.manifest["events"] as! [[String: Any]]
        events[0]["at"] = notice
        sample.manifest["events"] = events
        sample.files[3]["start"] = start
        var expectation = SampleRecording.expectation()
        expectation.virtualScreenFiles[0].startedBy.lastChange = 2.05
        return sample.check(expectation).failures.filter { !$0.contains("timecode") }
    }

    @Test func aConnectNoticedLateStartsTheSettleTimeAfterTheNotice() {
        #expect(connect(noticedAt: 2.5, startingAt: 3.5) == [])
    }

    @Test func onlyAConnectsEventIsANotice() {
        #expect(SampleRecording().check().notices == [0: 2.226])
    }

    @Test func aFirstFrameWithinTheLimitAfterTheSettleTimePasses() {
        #expect(connect(noticedAt: 2.5, startingAt: 4.4) == [])
    }

    @Test func aFirstFrameLaterThanTheLimitFails() {
        #expect(connect(noticedAt: 2.5, startingAt: 4.6) == [
            "2026-11-19 08.27.25 Screen 2 - Portable Monitor.mov: starts at 4.60 s, expected 3.00 s to 4.50 s, the settle time after the recorder's notice at 2.50 s",
        ])
    }

    @Test func theStartUpIsMeasuredFromTheSettleTimesEnd() {
        var sample = SampleRecording()
        sample.files[3]["start"] = 3.75
        var expectation = SampleRecording.expectation()
        expectation.virtualScreenFiles[0].startedBy.lastChange = 2.5
        #expect(sample.check(expectation).startUps[0] == 0.25)
    }

    @Test func aStartBeforeTheNoticePlusTheSettleTimeFails() {
        #expect(connect(noticedAt: 2.5, startingAt: 2.9) == [
            "2026-11-19 08.27.25 Screen 2 - Portable Monitor.mov: starts at 2.90 s, expected 3.00 s to 4.50 s, the settle time after the recorder's notice at 2.50 s",
        ])
    }

    @Test func aNoticeOutsideItsWindowFailsTheStartToo() {
        // The connect was asked at 2.0 s and done at 2.2 s: its notice is due by 2.7 s.
        #expect(connect(noticedAt: 2.9, startingAt: 3.9) == [
            "2026-11-19 08.27.25 Screen 2 - Portable Monitor.mov: its start is not checked: the recorder's notice, screen connected at 2.90 s, is outside its window",
            "screen connected at 2.90 s, expected 1.50 s to 2.70 s, with the change",
        ])
    }

    @Test func aMissingNoticeFailsTheStart() {
        var sample = SampleRecording()
        var events = sample.manifest["events"] as! [[String: Any]]
        events[0]["at"] = nil
        sample.manifest["events"] = events
        #expect(sample.check().failures == [
            "2026-11-19 08.27.25 Screen 2 - Portable Monitor.mov: its start is not checked: the recorder's notice, screen connected, is missing",
            "event {\"event\": \"screen connected\", \"screen\": \"Portable Monitor\"} has no time",
        ])
    }

    @Test func aMissingVirtualScreenFileFails() {
        var sample = SampleRecording()
        sample.files.remove(at: 4)
        #expect(sample.check().failures.contains {
            $0.hasPrefix("the virtual screens have 1 screen files, expected 2")
        })
    }

    @Test func eventsOutOfOrderMissingOrLateFail() {
        var sample = SampleRecording()
        var events = sample.manifest["events"] as! [[String: Any]]
        events.swapAt(0, 1)
        sample.manifest["events"] = events
        #expect(sample.check().failures == [
            "2026-11-19 08.27.25 Screen 2 - Portable Monitor.mov: its start is not checked: the recorder's notice, screen connected, is missing",
            "the virtual screens' events are [\"screen frame size changed\", \"screen connected\", \"screen disconnected\"], expected [\"screen connected\", \"screen frame size changed\", \"screen disconnected\"]",
        ])
        var late = SampleRecording()
        late.manifest["events"] = [
            ["at": 2.226, "event": "screen connected", "screen": "Portable Monitor"],
            ["at": 8.0, "event": "screen frame size changed", "screen": "Portable Monitor", "from": [1280, 720], "to": [1600, 900]],
            ["at": 11.242, "event": "screen disconnected", "screen": "Portable Monitor"],
        ]
        #expect(late.check().failures == ["screen frame size changed at 8.00 s, expected 6.50 s to 7.70 s, the settle time after the change"])
        var lateDisconnect = SampleRecording()
        lateDisconnect.manifest["events"] = [
            ["at": 2.226, "event": "screen connected", "screen": "Portable Monitor"],
            ["at": 7.204, "event": "screen frame size changed", "screen": "Portable Monitor", "from": [1280, 720], "to": [1600, 900]],
            ["at": 11.8, "event": "screen disconnected", "screen": "Portable Monitor"],
        ]
        // The disconnect was done at 11.24 s: its event is due by 11.74 s, without the settle time.
        #expect(lateDisconnect.check().failures == ["screen disconnected at 11.80 s, expected 10.50 s to 11.74 s, with the change"])
    }

    @Test func aFailureEventOrAnEventOfThePlayedInputFails() {
        var sample = SampleRecording()
        var events = sample.manifest["events"] as! [[String: Any]]
        events.append(["at": 5.0, "event": "audio input gap", "audioSource": "BlackHole 2ch", "length": 0.25])
        events.append(["at": 6.0, "event": "screen stream failed", "screen": "DELL P3421W", "error": "x"])
        sample.manifest["events"] = events
        let failures = sample.check().failures
        #expect(failures.count == 2)
        #expect(failures.contains { $0.hasPrefix("BlackHole 2ch has events, expected none") })
        #expect(failures.contains { $0.hasPrefix("a failure event:") })
    }

    @Test func thePlayedInputAndTheSystemAudioAreThereOnce() {
        var sample = SampleRecording()
        sample.files[2]["channels"] = 1
        var noSystemAudio = SampleRecording()
        noSystemAudio.files.remove(at: 1)
        #expect(sample.check().failures == ["2026-11-19 08.27.22 Audio 1 - BlackHole 2ch.mov: channels 1, expected 2"])
        #expect(noSystemAudio.check().failures == ["the system audio has 0 audio files, expected 1"])
    }

    @Test func theGuideTracksFollowTheSettings() {
        var sample = SampleRecording()
        sample.files[0]["guideTracks"] = ["Audio inputs"]
        #expect(sample.check().failures == [
            "2026-11-19 08.27.21 Screen 1 - DELL P3421W.mov: guideTracks are [\"Audio inputs\"], expected [\"Audio inputs\", \"System audio\"]",
        ])
        let settings = ManifestExpectation.Settings(resolution: "1080p", audioMode: "none", systemAudio: false)
        #expect(settings.guideTracks == [])
    }

    @Test func filesOutOfTheOrderOfTheirStartFail() {
        var sample = SampleRecording()
        sample.files.swapAt(3, 4)
        #expect(sample.check().failures.contains("files are not in the order of their start"))
    }

    private func ranFailures(ended: String) -> [String] {
        var sample = SampleRecording()
        sample.manifest["ended"] = ended
        return sample.check().failures.filter { $0.hasPrefix("the recording ran") }
    }

    @Test func aRecordingEndsNotBeforeItsStopAndWithinTheFinalizeAllowanceAfterIt() {
        // started 08:27:21.700, the stop at 17 s: from 16.5 s to 20 s.
        #expect(ranFailures(ended: "2026-11-19T08:27:38.100+01:00") == [
            "the recording ran 16.4 s from started to ended, expected 16.5 s to 20.0 s, from its stop to the finalize allowance after it",
        ])
        #expect(ranFailures(ended: "2026-11-19T08:27:38.300+01:00") == [])
        #expect(ranFailures(ended: "2026-11-19T08:27:41.600+01:00") == [])
        #expect(ranFailures(ended: "2026-11-19T08:27:41.800+01:00") == [
            "the recording ran 20.1 s from started to ended, expected 16.5 s to 20.0 s, from its stop to the finalize allowance after it",
        ])
    }

    @Test func aFileOfASourceWithoutEventsEndsWithinTheSameBounds() {
        func endFailures(_ end: Double) -> [String] {
            var sample = SampleRecording()
            sample.files[1]["end"] = end
            return sample.check().failures.filter { $0.contains(": ends at") }
        }
        #expect(endFailures(16.4) == ["2026-11-19 08.27.22 Audio 0 - System.mov: ends at 16.4 s, expected 16.5 s to 20.0 s, the stop"])
        #expect(endFailures(16.6) == [])
        #expect(endFailures(19.9) == [])
        #expect(endFailures(20.1) == ["2026-11-19 08.27.22 Audio 0 - System.mov: ends at 20.1 s, expected 16.5 s to 20.0 s, the stop"])
    }

    @Test func aFileWithoutEventsRunsFromTheStartToTheStop() {
        var sample = SampleRecording()
        sample.files[0]["start"] = 1.6
        sample.files[0]["timecode"] = "08:27:23:09"
        sample.files[0]["name"] = "2026-11-19 08.27.23 Screen 1 - DELL P3421W.mov"
        sample.files[1]["end"] = 12.0
        // Moved, the file is also out of the order of the starts: only the span lines matter here.
        let failures = sample.check().failures.filter { $0.contains(": starts at") || $0.contains(": ends at") }
        #expect(failures == [
            "2026-11-19 08.27.23 Screen 1 - DELL P3421W.mov: starts at 1.6 s, expected by 1.5 s, the settle time and the tolerance after the start",
            "2026-11-19 08.27.22 Audio 0 - System.mov: ends at 12.0 s, expected 16.5 s to 20.0 s, the stop",
        ])
    }

    @Test func thePlayedInputIsRecordedFromTheStart() {
        var sample = SampleRecording()
        sample.files[2]["start"] = 3.0
        sample.files[2]["timecode"] = "08:27:24:21"
        sample.files[2]["name"] = "2026-11-19 08.27.24 Audio 1 - BlackHole 2ch.mov"
        #expect(sample.check().failures.contains(
            "2026-11-19 08.27.24 Audio 1 - BlackHole 2ch.mov: starts at 3.0 s, expected by 1.5 s, the settle time and the tolerance after the start"))
    }

    @Test func aKilledRecordingsFilesStillStartWithIt() {
        var sample = SampleRecording(killed: true)
        sample.files[0]["start"] = 2.0
        sample.files[0]["timecode"] = "08:27:23:21"
        sample.files[0]["name"] = "2026-11-19 08.27.23 Screen 1 - DELL P3421W.mov"
        #expect(sample.check(SampleRecording.expectation(killedAt: 12)).failures.filter { $0.contains(": starts at") } == [
            "2026-11-19 08.27.23 Screen 1 - DELL P3421W.mov: starts at 2.0 s, expected by 1.5 s, the settle time and the tolerance after the start",
        ])
    }
}
