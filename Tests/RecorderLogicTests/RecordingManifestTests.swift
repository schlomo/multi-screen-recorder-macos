import Foundation
import Testing
@testable import RecorderLogic

@Suite struct RecordingManifestTests {
    private let berlin = TimeZone(identifier: "Europe/Berlin")!
    private let start = Date(timeIntervalSince1970: 1_794_488_585.120)  // 2026-11-12 14:03:05.120 in Berlin

    private func manifest() -> RecordingManifest {
        var settings = Settings.manual
        settings.systemAudio = true
        return RecordingManifest(app: "Multi Screen Recorder 0.20261115.4 (a1b2c3d)", started: start, timeZone: berlin,
                                 settings: settings)
    }

    @Test func theStartIsLocalTimeWithMillisecondsAndItsOffset() {
        #expect(manifest().started == "2026-11-12T14:03:05.120+01:00")
    }

    @Test func aFileBeingWrittenHasANullEndAndKeysAreSorted() throws {
        var manifest = manifest()
        manifest.files.append(.init(
            name: "2026-11-12 14.03.05 Screen 1 - Built-in Retina Display.mov", screen: "Built-in Retina Display",
            screenUUID: "37D8832A-2D66-02CA-B9F7-8F30A301B230", frameSize: FrameSize(width: 1670, height: 1080), start: 0,
            timecode: "14:03:05:04"))
        let text = String(decoding: try manifest.jsonData(), as: UTF8.self)
        #expect(text.contains(#""end" : null"#))
        #expect(text.contains(#""guideTracks" : ["#))
        #expect(text.contains(#""state" : "recording""#))
        #expect(text.contains(#""settings" : {"#))
        #expect(text.contains(#""audioMode" : "default-microphone""#))
        #expect(text.contains(#""ended" : null"#))
        #expect(text.contains(#""result" : null"#))
        #expect(text.contains(#""problems" : ["#))
        let keys = ["app", "ended", "events", "files", "problems", "result", "settings", "started", "state"].map { text.range(of: "\n  \"\($0)\"")!.lowerBound }
        #expect(keys == keys.sorted())
        #expect(try RecordingManifest(json: manifest.jsonData()) == manifest)
    }

    @Test func aFinalizedRecordingHasItsEndAndResult() {
        var manifest = manifest()
        manifest.finalize(ended: start + 60, timeZone: berlin)
        #expect(manifest.state == .finalized)
        #expect(manifest.ended == "2026-11-12T14:04:05.120+01:00")
        #expect(manifest.result == .ok)
    }

    /// D47: the result is ok when every file is finalized and no screen
    /// file was ended by a failure or a camera stalled; a problem told alone does not change it.
    @Test(arguments: [
        RecordingEvent.Kind.screenStreamFailed, .screenFileWriterFailed, .diskFull, .screenFileWriterFellBehind,
        .screenShowsAnotherScreensPicture,
    ])
    func aScreenFileEndedByAFailureMakesTheResultProblems(failure: RecordingEvent.Kind) {
        var manifest = manifest()
        manifest.events.append(RecordingEvent(at: 0, event: failure, screen: "A"))
        manifest.finalize(ended: start + 60, timeZone: berlin)
        #expect(manifest.result == .problems)
    }

    @Test func aFileNotFinalizedMakesTheResultProblems() {
        var manifest = manifest()
        manifest.files.append(.init(name: "a.mov", screen: "A", screenUUID: "A", frameSize: FrameSize(width: 2, height: 2),
                                    start: 0, timecode: "00:00:00:00"))
        manifest.finalize(ended: start + 60, timeZone: berlin)
        #expect(manifest.result == .problems)
    }

    @Test func aProblemToldOrAnEventThatIsNoFailureLeavesTheResultOk() {
        var manifest = manifest()
        manifest.problems.append(RecordingProblem(at: 2_000_000_000, problem: "The screens cannot be read", error: "denied"))
        for kind in RecordingEvent.Kind.allCases where !kind.isFailure {
            manifest.events.append(RecordingEvent(at: 0, event: kind, screen: "A"))
        }
        manifest.finalize(ended: start + 60, timeZone: berlin)
        #expect(manifest.result == .ok)
        #expect(manifest.problems.count == 1)
    }

    @Test func theFailuresAreTheWaysAFileEndsBadly() {
        #expect(RecordingEvent.Kind.allCases.filter(\.isFailure) == [
            .screenStreamFailed, .screenShowsAnotherScreensPicture, .screenFileWriterFellBehind, .screenFileWriterFailed,
            .cameraStreamFailed, .cameraStalled, .cameraFileWriterFellBehind, .cameraFileWriterFailed, .diskFull, .audioInputFailed, .systemAudioFailed, .audioFileWriterFailed, .audioFileWriterFellBehind,
        ])
    }

    @Test func anAudioFileNotFinalizedMakesTheResultProblems() {
        var manifest = manifest()
        var file = RecordingManifest.AudioFile(
            name: "a.mov", audioSource: "Mic", audioSourceUID: "uid", channels: .mono(1), start: 0, timecode: "14:03:05:04")
        file.state = .notFinalized
        manifest.audioFiles = [file]
        manifest.finalize(ended: start + 60, timeZone: berlin)
        #expect(manifest.result == .problems)
    }

    /// D47: `result` `problems` never comes with empty `problems`. When
    /// nothing was told, finalizing adds one problem naming the first
    /// failure and how many failures there were.
    @Test(arguments: RecordingEvent.Kind.allCases.filter(\.isFailure))
    func aFailureNotToldGivesOneProblemAtTheEnd(failure: RecordingEvent.Kind) {
        var manifest = manifest()
        let isAudio = failure.rawValue.contains("audio")
        var event = RecordingEvent(at: 36_778_000_000, event: failure, screen: isAudio ? nil : "DELL", audioSource: isAudio ? "BRIO" : nil)
        event.errorDetail = "it broke"
        manifest.events.append(event)
        manifest.finalize(ended: start + 60, timeZone: berlin)
        #expect(manifest.result == .problems)
        #expect(manifest.problems == [RecordingProblem(
            atSeconds: 36.778, problem: "A failure was not told while recording",
            error: "\(isAudio ? "Audio source BRIO" : "Screen DELL"): \(failure.rawValue): it broke (1 failure event, see events)",
            errorDetail: ErrorDetail(message: failure.rawValue, underlying: ["it broke"]))])
    }

    /// The recording `2026-11-16 12.24.51`: two `screen file writer fell
    /// behind` and no problem told: exactly one problem.
    @Test func theRecordingWithFailuresAndNothingToldGetsExactlyOneProblem() {
        var manifest = manifest()
        manifest.events.append(RecordingEvent(at: 36_778_000_000, event: .screenFileWriterFellBehind, screen: "DELL P3421W"))
        manifest.events.append(RecordingEvent(at: 49_618_000_000, event: .audioInputDisconnected, audioSource: "Razer"))
        manifest.events.append(RecordingEvent(at: 72_098_000_000, event: .screenFileWriterFellBehind, screen: "DELL P3421W"))
        manifest.finalize(ended: start + 60, timeZone: berlin)
        #expect(manifest.result == .problems)
        #expect(manifest.problems == [RecordingProblem(
            atSeconds: 36.778, problem: "A failure was not told while recording",
            error: "Screen DELL P3421W: screen file writer fell behind (2 failure events, see events)",
            errorDetail: ErrorDetail(message: "screen file writer fell behind"))])
    }

    @Test func repeatedSystemAudioFailuresToldLiveAddNothing() {
        var manifest = manifest()
        let told = RecordingProblem(at: 5_000_000_000, problem: "The system audio failed", error: "the stream stopped")
        manifest.problems = [told]
        for second in [5, 9, 17] as [Int64] {
            var failed = RecordingEvent(at: second * 1_000_000_000, event: .systemAudioFailed, audioSource: "System audio")
            failed.errorDetail = "the stream stopped"
            manifest.events.append(failed)
        }
        manifest.finalize(ended: start + 60, timeZone: berlin)
        #expect(manifest.result == .problems)
        #expect(manifest.problems == [told])
    }

    /// A name with `/` or `:` is written with `-` in file names; the net
    /// does not depend on how a problem spells it.
    @Test func repeatedFailuresOfAScreenWithSlashAndColonToldLiveAddNothing() {
        var manifest = manifest()
        let told = RecordingProblem(
            at: 10_000_000_000, problem: "Screen file 2026-11-16 12.24.51 Screen 1 - A-B- Screen.mov", error: "cannot finalize")
        manifest.problems = [told]
        manifest.events.append(RecordingEvent(at: 10_000_000_000, event: .screenFileWriterFailed, screen: "A/B: Screen"))
        manifest.events.append(RecordingEvent(at: 20_000_000_000, event: .screenFileWriterFellBehind, screen: "A/B: Screen"))
        manifest.finalize(ended: start + 60, timeZone: berlin)
        #expect(manifest.problems == [told])
    }

    @Test func aScreenFileNotFinalizedWithNothingToldGetsOneProblemNamingIt() {
        var manifest = manifest()
        var screen = RecordingManifest.ScreenFile(
            name: "d.mov", screen: "LG", screenUUID: "U", frameSize: FrameSize(width: 2, height: 2), start: 1, timecode: "t")
        screen.end = 5
        screen.state = .notFinalized
        manifest.files = [screen]
        manifest.finalize(ended: start + 60, timeZone: berlin)
        #expect(manifest.result == .problems)
        #expect(manifest.problems == [RecordingProblem(
            at: 5_000_000_000, problem: "A file was not finalized and nothing was told while recording", error: "d.mov")])
    }

    /// Failure events come first: with an unfinalized file too, the one problem names the failure.
    @Test func aFailureAndAFileNotFinalizedWithNothingToldGetOneProblemNamingTheFailure() {
        var manifest = manifest()
        var audio = RecordingManifest.AudioFile(
            name: "a.mov", audioSource: "Mic", audioSourceUID: "uid", channels: .mono(1), start: 2, timecode: "t")
        audio.state = .notFinalized
        manifest.audioFiles = [audio]
        manifest.events.append(RecordingEvent(at: 30_000_000_000, event: .screenFileWriterFellBehind, screen: "DELL"))
        manifest.finalize(ended: start + 60, timeZone: berlin)
        #expect(manifest.problems == [RecordingProblem(
            atSeconds: 30, problem: "A failure was not told while recording",
            error: "Screen DELL: screen file writer fell behind (1 failure event, see events)",
            errorDetail: ErrorDetail(message: "screen file writer fell behind"))])
    }

    @Test func aFileNotFinalizedAddsNothingWhenAProblemWasTold() {
        var manifest = manifest()
        var audio = RecordingManifest.AudioFile(
            name: "a.mov", audioSource: "Mic", audioSourceUID: "uid", channels: .mono(1), start: 2, timecode: "t")
        audio.state = .notFinalized
        manifest.audioFiles = [audio]
        let told = RecordingProblem(at: 1_000_000_000, problem: "The free space cannot be read", error: "no volume")
        manifest.problems = [told]
        manifest.finalize(ended: start + 60, timeZone: berlin)
        #expect(manifest.result == .problems)
        #expect(manifest.problems == [told])
    }

    @Test func aFileNotFinalizedWithNothingToldGetsOneProblem() {
        var manifest = manifest()
        var audio = RecordingManifest.AudioFile(
            name: "a.mov", audioSource: "Mic", audioSourceUID: "uid", channels: .mono(1), start: 2, timecode: "t")
        audio.state = .notFinalized
        manifest.audioFiles = [audio]
        manifest.finalize(ended: start + 60, timeZone: berlin)
        #expect(manifest.result == .problems)
        #expect(manifest.problems == [RecordingProblem(
            at: 2_000_000_000, problem: "A file was not finalized and nothing was told while recording", error: "a.mov")])
    }

    @Test func filesAreWrittenInTheOrderOfTheirStartAndReadBackByKind() throws {
        var manifest = manifest()
        manifest.files = [RecordingManifest.ScreenFile(
            name: "d.mov", screen: "LG", screenUUID: "U", frameSize: FrameSize(width: 2, height: 2), start: 3, timecode: "t")]
        manifest.audioFiles = [
            RecordingManifest.AudioFile(name: "s.mov", audioSource: "System audio", audioSourceUID: nil, channels: .stereo, start: 1, timecode: "t"),
            RecordingManifest.AudioFile(name: "m.mov", audioSource: "Mic", audioSourceUID: "uid", channels: .mono(2), start: 5, timecode: "t"),
        ]
        let data = try manifest.jsonData()
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let files = try #require(object["files"] as? [[String: Any]])
        #expect(files.map { $0["name"] as? String } == ["s.mov", "d.mov", "m.mov"])
        #expect(files[0]["channels"] as? String == "stereo")
        #expect(files[0]["audioSourceUID"] == nil)
        #expect(files[2]["channels"] as? Int == 2)
        #expect(files[2]["clockDriftPpm"] is NSNull)
        #expect(files[2]["clockDriftCorrection"] is NSNull)
        #expect(try RecordingManifest(json: data) == manifest)
    }

    /// An audio file's clock drift is the one shown at its end, and its
    /// correction the sound added during it; neither is negative zero.
    @Test func anAudioFilesClockDriftAndCorrection() throws {
        var file = RecordingManifest.AudioFile(
            name: "a.mov", audioSource: "Razer Seiren V3 Mini", audioSourceUID: "R", channels: .mono(1), start: 0, timecode: "t")
        file.clockDrift(correction: 0.034_94, ppm: -116.12)
        #expect(file.clockDriftCorrection == 0.0349)
        #expect(file.clockDriftPpm == -116.1)
        file.clockDrift(correction: -0.000_491, ppm: nil)
        #expect(file.clockDriftCorrection == -0.0005)
        #expect(file.clockDriftPpm == nil)
        file.clockDrift(correction: -0.000_01, ppm: -0.04)
        let object = try #require(try JSONSerialization.jsonObject(with: try JSONEncoder().encode(file)) as? [String: Any])
        let text = try #require(String(data: try JSONEncoder().encode(file), encoding: .utf8))
        #expect(object["clockDriftPpm"] as? Double == 0)
        #expect(object["clockDriftCorrection"] as? Double == 0)
        #expect(!text.contains("-0"), "\(text)")
        file.clockDrift(correction: 0, ppm: nil)
        let unmeasured = try #require(try JSONSerialization.jsonObject(with: try JSONEncoder().encode(file)) as? [String: Any])
        #expect(unmeasured["clockDriftPpm"] is NSNull)
    }

    /// An audio input's file has its input volume at its start, null when
    /// it cannot be read; the system audio's file has none (D69).
    @Test func anAudioInputsFileHasItsInputVolume() throws {
        var input = RecordingManifest.AudioFile(
            name: "a.mov", audioSource: "Razer Seiren V3 Mini", audioSourceUID: "R", channels: .mono(1), start: 0, timecode: "t")
        let unread = try #require(try JSONSerialization.jsonObject(with: try JSONEncoder().encode(input)) as? [String: Any])
        #expect(unread["inputVolume"] is NSNull)
        input.inputVolume = 0.42
        let read = try #require(try JSONSerialization.jsonObject(with: try JSONEncoder().encode(input)) as? [String: Any])
        #expect(read["inputVolume"] as? Double == 0.42)
        #expect(try JSONDecoder().decode(RecordingManifest.AudioFile.self, from: JSONEncoder().encode(input)) == input)
        let system = RecordingManifest.AudioFile(
            name: "s.mov", audioSource: "System audio", audioSourceUID: nil, channels: .stereo, start: 0, timecode: "t")
        let systemObject = try #require(try JSONSerialization.jsonObject(with: try JSONEncoder().encode(system)) as? [String: Any])
        #expect(systemObject.keys.contains("inputVolume") == false)
    }

    /// Each recorded audio input's newest file, whether the new file starts before or after its earlier one's
    /// end is told, a file that ended staying its device's newest until the next starts (D80).
    @Test(arguments: [true, false]) func eachAudioInputsNewestFileIsTheLatestToStart(endFirst: Bool) {
        var manifest = RecordingManifest(app: "a", started: Date(), timeZone: .gmt, settings: .manual)
        func file(_ name: String, _ uid: String?, start: Double) -> RecordingManifest.AudioFile {
            RecordingManifest.AudioFile(name: name, audioSource: name, audioSourceUID: uid, channels: .mono(1), start: start, timecode: "t")
        }
        for started in [file("a1.mov", "A", start: 0), file("b.mov", "B", start: 0), file("s.mov", nil, start: 0), file("c.mov", "C", start: 0)] {
            _ = manifest.audioFileStarted(started)
        }
        var ended = file("a1.mov", "A", start: 0)
        ended.end = 10
        var endedB = file("b.mov", "B", start: 0)
        endedB.end = 5
        _ = manifest.audioFileEnded(endedB)
        #expect(manifest.newestAudioInputFiles(of: ["A", "B"]) == ["a1.mov": "A", "b.mov": "B"])
        if endFirst { _ = manifest.audioFileEnded(ended) }
        _ = manifest.audioFileStarted(file("a2.mov", "A", start: 10))
        if !endFirst { _ = manifest.audioFileEnded(ended) }
        #expect(manifest.newestAudioInputFiles(of: ["A", "B"]) == ["a2.mov": "A", "b.mov": "B"])
    }

    /// An audio file lists its audio delays, one entry of `at` and `delay` alone per change of the value, an
    /// empty list until set; its end keeps them; a file listed before them reads with none (D80).
    @Test func anAudioFileListsItsAudioDelaysAndKeepsThemAtItsEnd() throws {
        var manifest = RecordingManifest(app: "a", started: Date(), timeZone: .gmt, settings: .manual)
        let file = RecordingManifest.AudioFile(
            name: "a.mov", audioSource: "OsmoPocket4P", audioSourceUID: "O", channels: .mono(1), start: 10, timecode: "t")
        let unset = try #require(try JSONSerialization.jsonObject(with: try JSONEncoder().encode(file)) as? [String: Any])
        #expect((unset["delays"] as? [Any])?.isEmpty == true)
        #expect(unset["measuredDelay"] == nil)
        _ = manifest.audioFileStarted(file)
        let set = manifest.audioDelaySet(AudioDelays.Entry(delay: 0.553_24), at: 10, file: "a.mov")
        // The same delay confirmed is no change; a change is a new entry, at seconds from the file's start.
        let confirmed = manifest.audioDelaySet(AudioDelays.Entry(delay: 0.553_21), at: 20, file: "a.mov")
        let changed = manifest.audioDelaySet(AudioDelays.Entry(delay: 0.47), at: 72.345_67, file: "a.mov")
        let unlisted = manifest.audioDelaySet(AudioDelays.Entry(delay: 0.5), at: 80, file: "other.mov")
        #expect(set && !confirmed && changed && !unlisted)
        var ended = file
        ended.end = 120
        _ = manifest.audioFileEnded(ended)
        let delays = try #require(manifest.audioFiles.first?.delays)
        #expect(delays == [
            .init(at: 0, delay: 0.5532),
            .init(at: 62.346, delay: 0.47),
        ])
        #expect(manifest.audioFiles.first?.end == 120)
        let written = try #require(try JSONSerialization.jsonObject(with: try JSONEncoder().encode(manifest.audioFiles[0])) as? [String: Any])
        let entries = try #require(written["delays"] as? [[String: Any]])
        #expect(entries.map { $0.keys.sorted() } == [["at", "delay"], ["at", "delay"]])
        let earlier = #"{"name": "b.mov", "audioSource": "Mic", "channels": 1, "start": 0, "end": 1, "timecode": "t", "state": "finalized", "measuredDelay": 0.5}"#
        #expect(try JSONDecoder().decode(RecordingManifest.AudioFile.self, from: Data(earlier.utf8)).delays.isEmpty)
    }

    @Test func anInputVolumeChangeCarriesTheVolumesFrom0To1() throws {
        var changed = RecordingEvent(at: 1_200_000_000, event: .audioInputVolumeChanged, audioSource: "Razer")
        changed.from = .volume(0.5)
        changed.to = .volume(1)
        let text = String(decoding: try prettyJSON(changed), as: UTF8.self)
        #expect(text.contains(#""from" : 0.5"#))
        #expect(text.contains(#""to" : 1"#))
        #expect(try JSONDecoder().decode(RecordingEvent.self, from: prettyJSON(changed)) == changed)
        #expect(RecordingEvent.Value.volume(0.25).text == "0.25")
    }

    @Test func noAudioAndTheInputVolumeAreNoFailures() {
        for kind in [RecordingEvent.Kind.noAudioStarted, .noAudioStopped, .audioInputVolumeChanged] {
            #expect(!kind.isFailure)
        }
    }

    @Test func aFinalizedManifestTakesNoMoreEventsOrAudioFiles() {
        var manifest = manifest()
        let file = RecordingManifest.AudioFile(
            name: "a.mov", audioSource: "Mic", audioSourceUID: "uid", channels: .mono(1), start: 0, timecode: "t")
        let other = RecordingManifest.AudioFile(
            name: "b.mov", audioSource: "Mic", audioSourceUID: "uid", channels: .mono(1), start: 0, timecode: "t")
        let gap = RecordingEvent(at: 0, event: .audioInputGap, audioSource: "Mic")
        var ended = file
        ended.state = .finalized
        let taken = [
            manifest.audioFileStarted(file), manifest.audioFileStarted(file), manifest.audioFileEnded(ended), manifest.record([gap]),
        ]
        #expect(taken == [true, false, true, true])
        manifest.finalize(ended: start + 60, timeZone: berlin)
        let finalized = manifest
        let takenAfter = [manifest.record([gap]), manifest.audioFileEnded(file), manifest.audioFileStarted(other)]
        #expect(takenAfter == [false, false, false])
        #expect(manifest == finalized)
    }

    @Test func theCPUUseIsWrittenAtTheEnd() throws {
        var manifest = manifest()
        let running = try #require(try JSONSerialization.jsonObject(with: manifest.jsonData()) as? [String: Any])
        #expect(running["cpu"] is NSNull)
        manifest.finalize(ended: start + 60, timeZone: berlin, cpu: .init(averagePercent: 12.5, peakPercent: 40))
        let ended = try #require(try JSONSerialization.jsonObject(with: manifest.jsonData()) as? [String: Any])
        #expect(ended["cpu"] as? [String: Double] == ["averagePercent": 12.5, "peakPercent": 40])
    }

    @Test func aGapAndADefaultMicrophoneChangeCarryTheirFields() throws {
        var gap = RecordingEvent(at: 0, event: .audioInputGap, audioSource: "Mic")
        gap.length = 0.25
        var changed = RecordingEvent(at: 0, event: .defaultMicrophoneChanged)
        changed.from = "Mic"
        changed.to = "Razer"
        for event in [gap, changed] {
            #expect(try JSONDecoder().decode(RecordingEvent.self, from: prettyJSON(event)) == event)
        }
        let text = String(decoding: try prettyJSON(changed), as: UTF8.self)
        #expect(text.contains(#""from" : "Mic""#))
        let gapText = String(decoding: try prettyJSON(gap), as: UTF8.self)
        #expect(gapText.contains(#""audioSource" : "Mic""#))
        #expect(!gapText.contains(#""screen""#))
    }

    @Test func aProblemHasItsTimeAndFullError() throws {
        let problem = RecordingProblem(at: 1_446_200_400_000, problem: "Screen file a.mov", error: "The operation could not be completed")
        #expect(problem.at == 1446.2)
        #expect(problem.text == "Screen file a.mov: The operation could not be completed")
        #expect(RecordingProblem(at: 0, problem: "The screens cannot be read", error: nil).text == "The screens cannot be read")
        let text = String(decoding: try prettyJSON(RecordingProblem(at: 0, problem: "p", error: nil)), as: UTF8.self)
        #expect(text.contains(#""error" : null"#))
        #expect(text.contains(#""errorDetail" : null"#))
    }

    /// A recording log not complete on disk at the end makes the result `problems` (D64).
    @Test func aRecordingLogNotWrittenAtTheEndIsAnError() {
        var manifest = manifest()
        manifest.problems = [RecordingProblem(at: 0, problem: "Cannot write the recording log recording.log", error: "full")]
        manifest.finalize(ended: start + 60, timeZone: berlin, recordingLogWritten: false)
        #expect(manifest.result == .problems)
        #expect(RecordingSummary(manifest: manifest, recordingFolder: "/r", seconds: 60, manifestWritten: true).endedWithError)
    }

    /// A manifest from before D64 has an event's `error` and no `errorDetail`: reading it keeps the text.
    @Test func anOlderEventsErrorIsKept() throws {
        let json = #"{ "at": 1.0, "event": "screen stream failed", "screen": "LG", "error": "the stream stopped (-3811)" }"#
        let event = try JSONDecoder().decode(RecordingEvent.self, from: Data(json.utf8))
        #expect(event.error == "the stream stopped (-3811)")
        let written = try #require(try JSONSerialization.jsonObject(with: prettyJSON(event)) as? [String: Any])
        #expect(written["error"] as? String == "the stream stopped (-3811)")
    }

    /// D64: every event and problem with an `error` carries its `errorDetail`,
    /// the full chain with each level's domain and code.
    @Test func anErrorIsWrittenAsItsTextAndItsErrorDetail() throws {
        let osStatus = NSError(domain: NSOSStatusErrorDomain, code: -12912)
        let detail = ErrorDetail(message: "cannot write a.mov", underlying: NSError(
            domain: "AVFoundationErrorDomain", code: -11800, userInfo: [NSUnderlyingErrorKey: osStatus]))
        var event = RecordingEvent(at: 1_000_000_000, event: .screenFileWriterFailed, screen: "LG")
        event.errorDetail = detail
        var manifest = manifest()
        manifest.events = [event, RecordingEvent(at: 2_000_000_000, event: .sleep)]
        manifest.problems = [event.problem, RecordingProblem(at: 3_000_000_000, problem: "p", error: nil)]
        let data = try manifest.jsonData()
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let events = try #require(object["events"] as? [[String: Any]])
        #expect(events[0]["error"] as? String == detail.text)
        let written = try #require(events[0]["errorDetail"] as? [String: Any])
        #expect(written["description"] as? String == "cannot write a.mov")
        let avFoundation = try #require((written["underlying"] as? [[String: Any]])?.first)
        #expect(avFoundation["domain"] as? String == "AVFoundationErrorDomain")
        #expect(avFoundation["code"] as? Int == -11800)
        let status = try #require((avFoundation["underlying"] as? [[String: Any]])?.first)
        #expect(status["code"] as? Int == -12912)
        #expect(events[1]["error"] == nil)
        #expect(events[1]["errorDetail"] == nil)
        let problems = try #require(object["problems"] as? [[String: Any]])
        #expect(problems[0]["error"] as? String == "screen file writer failed: \(detail.text)")
        #expect((problems[0]["errorDetail"] as? [String: Any])?["description"] as? String == "screen file writer failed")
        #expect(problems[1]["errorDetail"] is NSNull)
        #expect(try RecordingManifest(json: data) == manifest)
    }

    @Test func eventsAndProblemsAreWrittenInTheOrderOfTheirTime() throws {
        var manifest = manifest()
        manifest.events = [
            RecordingEvent(at: 5_000_000_000, event: .wake), RecordingEvent(at: 2_000_000_000, event: .sleep),
            RecordingEvent(at: 2_000_000_000, event: .diskFull, screen: "A"),
        ]
        manifest.problems = [
            RecordingProblem(at: 3_000_000_000, problem: "late", error: nil), RecordingProblem(at: 1_000_000_000, problem: "early", error: nil),
        ]
        let written = try RecordingManifest(json: manifest.jsonData())
        #expect(written.events.map(\.event) == [.sleep, .diskFull, .wake])
        #expect(written.problems.map(\.problem) == ["early", "late"])
    }

    @Test func eventTimesAreSecondsToTheMillisecond() {
        #expect(RecordingEvent(at: 1_446_200_400_000, event: .sleep).at == 1446.2)
    }

    // MARK: The design holds the code

    private func design() throws -> String { try repositoryFile("docs/design/recorder.md") }

    @Test func theEventsAreThoseTheDesignLists() throws {
        let text = try design()
        let start = try #require(text.range(of: "The events: ")).upperBound
        let end = try #require(text[start...].range(of: "each names its screen")).lowerBound
        let listed = text[start..<end].replacingOccurrences(of: "\n", with: " ")
            .matches(of: /`([^`]+)`/).map { String($0.output.1) }
        #expect(listed == RecordingEvent.Kind.allCases.map(\.rawValue))
    }

    @Test func theExamplesScreenFilesReadAsTheManifestWritesThem() throws {
        let text = try design()
        let start = try #require(text.range(of: "```json\n{\n  \"app\"")).upperBound
        let json = "{\n  \"app\"" + text[start...].prefix { _ in true }.split(separator: "```").first!
        let object = try #require(try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
        let files = try #require(object["files"] as? [[String: Any]])
        let screenFiles = files.filter { $0["screen"] != nil }
        #expect(screenFiles.count == 4)
        for file in screenFiles {
            let data = try JSONSerialization.data(withJSONObject: file)
            let decoded = try JSONDecoder().decode(RecordingManifest.ScreenFile.self, from: data)
            let encoded = try #require(try JSONSerialization.jsonObject(with: prettyJSON(decoded)) as? [String: Any])
            #expect(Set(encoded.keys) == Set(file.keys))
            #expect(decoded.name == file["name"] as? String)
        }
        let cameraFiles = files.filter { $0["camera"] != nil }
        #expect(cameraFiles.count == 1)
        for file in cameraFiles {
            let decoded = try JSONDecoder().decode(RecordingManifest.CameraFile.self, from: JSONSerialization.data(withJSONObject: file))
            let encoded = try #require(try JSONSerialization.jsonObject(with: prettyJSON(decoded)) as? [String: Any])
            #expect(Set(encoded.keys) == Set(file.keys))
        }
        let events = try #require(object["events"] as? [[String: Any]])
        for event in events {
            _ = try JSONDecoder().decode(RecordingEvent.self, from: JSONSerialization.data(withJSONObject: event))
        }
        let problems = try #require(object["problems"] as? [[String: Any]])
        for problem in problems {
            let decoded = try JSONDecoder().decode(RecordingProblem.self, from: JSONSerialization.data(withJSONObject: problem))
            let encoded = try #require(try JSONSerialization.jsonObject(with: prettyJSON(decoded)) as? [String: Any])
            #expect(Set(encoded.keys) == Set(problem.keys))
        }
        let written = try #require(try JSONSerialization.jsonObject(with: manifest().jsonData()) as? [String: Any])
        #expect(Set(object.keys) == Set(written.keys))
        // The example is a recording still running: no end and no result yet.
        #expect(object["ended"] is NSNull)
        #expect(object["result"] is NSNull)
        let settings = try #require(object["settings"] as? [String: Any])
        #expect(Set(settings.keys) == ["resolution", "audioMode", "systemAudio", "cameraMode", "limitCameras"])
        #expect(object["started"] as? String == manifest().started)
    }

    @Test func theExamplesFileNamesAreTheNamesTheRecorderGives() throws {
        let start = self.start
        #expect(RecordingNames.recordingFolder(start: start, timeZone: berlin) == "2026-11-12 14.03.05")
        let first = RecordingNames.screenFile(start: start, timeZone: berlin, number: 1, screen: "Built-in Retina Display")
        let back = RecordingNames.screenFile(start: start + 1476, timeZone: berlin, number: 2, screen: "LG HDR 4K")
        let text = try design()
        #expect(text.contains("\n  \(first)\n"))
        #expect(text.contains("\n  \(back)    ← back after a reconnect"))
        let timecode = Timecode(start: start, timeZone: berlin)
        #expect(text.contains(#""timecode": "\#(timecode.text(ofTick: 1476 * Int64(RecorderValues.framesPerSecond)))""#))
    }
}

@Suite struct RecordingNamesTests {
    private let utc = TimeZone(identifier: "UTC")!

    /// A name never stops a screen from recording: `/` and `:` become `-`.
    @Test func charactersAFileNameCannotHoldBecomeDashes() {
        let name = RecordingNames.screenFile(start: Date(timeIntervalSince1970: 0), timeZone: utc, number: 3, screen: "Dell U2720Q/2: left")
        #expect(name == "1970-01-01 00.00.00 Screen 3 - Dell U2720Q-2- left.mov")
    }

    @Test func anAudioFileIsNamedByItsLabel() {
        let start = Date(timeIntervalSince1970: 0)
        let microphone = RecordingNames.audioFile(
            start: start, timeZone: utc, source: .audioInput(number: 2, name: "Mic 1/2", coreAudioUID: "u", channelCount: 1))
        #expect(microphone == "1970-01-01 00.00.00 Audio 2 - Mic 1-2.mov")
        #expect(RecordingNames.audioFile(start: start, timeZone: utc, source: .systemAudio) == "1970-01-01 00.00.00 Audio 0 - System.mov")
        #expect(RecordingNames.audioFile(start: start, timeZone: utc, source: .systemAudio, taken: ["1970-01-01 00.00.00 Audio 0 - System.mov"])
            == "1970-01-01 00.00.00 Audio 0 - System (2).mov")
    }

    @Test func aTakenNameGetsANumber() {
        let start = Date(timeIntervalSince1970: 0)
        let name = RecordingNames.screenFile(start: start, timeZone: utc, number: 2, screen: "LG HDR 4K")
        #expect(name == "1970-01-01 00.00.00 Screen 2 - LG HDR 4K.mov")
        #expect(RecordingNames.screenFile(start: start, timeZone: utc, number: 2, screen: "LG HDR 4K", taken: [name])
            == "1970-01-01 00.00.00 Screen 2 - LG HDR 4K (2).mov")
        #expect(RecordingNames.screenFile(
            start: start, timeZone: utc, number: 2, screen: "LG HDR 4K",
            taken: [name, "1970-01-01 00.00.00 Screen 2 - LG HDR 4K (2).mov"])
            == "1970-01-01 00.00.00 Screen 2 - LG HDR 4K (3).mov")
    }
}

@Suite struct RecordingProblemsTests {
    /// D47: the badge shows only "!", nothing otherwise.
    @Test func theBadgeIsEmptyUntilSomethingNeedsThePerson() {
        var status = RecordingStatus()
        #expect(status.badge == nil)
        status.isLowOnDisk = true
        #expect(status.badge == "!")
        status.isLowOnDisk = false
        status.screenShowingAnotherScreensPicture = "LG"
        #expect(status.badge == "!")
        status.screenShowingAnotherScreensPicture = nil
        status.problems.append("Cannot write the recording manifest: full")
        #expect(status.badge == "!")
    }
}

@Suite struct RecordingDurationTests {
    @Test(arguments: [("1h30m", 5400), ("45m", 2700), ("90s", 90), ("2h", 7200), ("1h0m5s", 3605), ("90", 5400), ("5", 300)])
    func hoursMinutesAndSeconds(text: String, seconds: Int) {
        #expect(RecordingDuration(text)?.seconds == seconds)
    }

    @Test(arguments: ["", "0m", "0", "1.5h", "1.5", "m", "1m1h", "-1h", "-5", "1h 30m"])
    func anythingElseIsInvalid(text: String) {
        #expect(RecordingDuration(text) == nil)
    }
}

@Suite struct RecordingSummaryTests {
    private func manifest(_ states: [RecordingManifest.State], events: [RecordingEvent] = []) -> RecordingManifest {
        var manifest = RecordingManifest(app: "x", started: Date(), timeZone: .current, settings: .defaults)
        for (index, state) in states.enumerated() {
            var file = RecordingManifest.ScreenFile(
                name: "f\(index).mov", screen: "D", screenUUID: "U", frameSize: FrameSize(width: 2, height: 2), start: 0,
                timecode: "00:00:00:00")
            file.state = state
            manifest.files.append(file)
        }
        manifest.events = events
        return manifest
    }

    @Test func aCleanRecordingEndsWithoutError() {
        let summary = RecordingSummary(manifest: manifest([.finalized]), recordingFolder: "/r", seconds: 3725, manifestWritten: true)
        #expect(!summary.endedWithError)
        #expect(summary.text == "Recorded 1h02m05s into /r\n  f0.mov  finalized\n")
    }

    @Test func aFileNotFinalizedOrAnErrorEventIsAnError() {
        #expect(RecordingSummary(manifest: manifest([.notFinalized]), recordingFolder: "/r", seconds: 1, manifestWritten: true).endedWithError)
        var failed = RecordingEvent(at: 65_000_000_000, event: .screenStreamFailed, screen: "LG")
        failed.errorDetail = "-3811"
        let summary = RecordingSummary(
            manifest: manifest([.finalized, .finalized], events: [failed, RecordingEvent(at: 0, event: .sleep)]),
            recordingFolder: "/r", seconds: 70, manifestWritten: true)
        #expect(summary.endedWithError)
        #expect(summary.text.hasSuffix("Error at 1m05s: screen stream failed, LG (-3811)\n"))
    }

    /// F3: the final manifest not written is a failure; the file on disk has no `ended`.
    @Test func aFinalManifestNotWrittenIsAnError() {
        let summary = RecordingSummary(manifest: manifest([.finalized]), recordingFolder: "/r", seconds: 1, manifestWritten: false)
        #expect(summary.endedWithError)
        #expect(summary.text.hasSuffix("The recording manifest could not be written at the end: recording.json has no end.\n"))
        #expect(!RecordingSummary(manifest: manifest([.finalized]), recordingFolder: "/r", seconds: 1, manifestWritten: true).endedWithError)
    }

    @Test func aProblemIsListedWithItsTimeAndIsNoErrorByItself() {
        var told = manifest([.finalized])
        told.problems = [RecordingProblem(at: 65_000_000_000, problem: "The screens cannot be read", error: "denied")]
        let summary = RecordingSummary(manifest: told, recordingFolder: "/r", seconds: 70, manifestWritten: true)
        #expect(!summary.endedWithError)
        #expect(summary.text.hasSuffix("Problem at 1m05s: The screens cannot be read: denied\n"))
    }

    @Test func theSummaryListsTheAudioFilesAndTheCPUUse() {
        var recorded = manifest([.finalized])
        recorded.audioFiles = [RecordingManifest.AudioFile(
            name: "a.mov", audioSource: "Mic", audioSourceUID: "u", channels: .mono(1), start: 0, timecode: "t")]
        recorded.audioFiles[0].state = .finalized
        recorded.cpu = RecordingManifest.CPU(averagePercent: 12.4, peakPercent: 31.6)
        let summary = RecordingSummary(manifest: recorded, recordingFolder: "/r", seconds: 5, manifestWritten: true)
        #expect(summary.text == "Recorded 5s into /r\n  f0.mov  finalized\n  a.mov  finalized\n"
            + "CPU 12 % on average, 32 % at the peak, of one core (this process only)\n")
    }

    /// The screens by number, then the audio sources by number, the system audio (0) first; a source's files by start,
    /// also when a later file was appended before an earlier one.
    @Test func theFilesAreListedByScreenNumberThenAudioNumberThenStart() {
        let utc = TimeZone(identifier: "UTC")!
        let started = Date(timeIntervalSince1970: 1_800_000_000)
        func screen(_ number: Int, _ name: String, at seconds: Double) -> RecordingManifest.ScreenFile {
            RecordingManifest.ScreenFile(
                name: RecordingNames.screenFile(start: started + seconds, timeZone: utc, number: number, screen: name),
                screen: name, screenUUID: "U\(number)", frameSize: FrameSize(width: 2, height: 2), start: seconds, timecode: "t")
        }
        func audio(_ source: AudioFileDescription.Source, at seconds: Double) -> RecordingManifest.AudioFile {
            RecordingManifest.AudioFile(
                name: RecordingNames.audioFile(start: started + seconds, timeZone: utc, source: source),
                audioSource: "M", audioSourceUID: "u", channels: .mono(1), start: seconds, timecode: "t")
        }
        func input(_ number: Int, _ name: String) -> AudioFileDescription.Source {
            .audioInput(number: number, name: name, coreAudioUID: "u\(number)", channelCount: 1)
        }
        var recorded = manifest([])
        recorded.files = [screen(2, "B", at: 0), screen(1, "A", at: 840), screen(1, "A", at: 0)]
        recorded.audioFiles = [audio(input(4, "D"), at: 0), audio(.systemAudio, at: 0), audio(input(10, "K"), at: 0),
                               audio(input(1, "C"), at: 900), audio(input(1, "C"), at: 0)]
        let lines = RecordingSummary(manifest: recorded, recordingFolder: "/r", seconds: 5, manifestWritten: true)
            .text.split(separator: "\n").dropFirst().map { $0.dropFirst(2).dropLast(11) }
        let names = lines.map { String($0) }
        #expect(names == [recorded.files[2].name, recorded.files[1].name, recorded.files[0].name,
                          recorded.audioFiles[1].name, recorded.audioFiles[4].name, recorded.audioFiles[3].name,
                          recorded.audioFiles[0].name, recorded.audioFiles[2].name])
        #expect(names.map { $0.dropFirst(20).prefix { $0 != "." } } == [
            "Screen 1 - A", "Screen 1 - A", "Screen 2 - B", "Audio 0 - System", "Audio 1 - C", "Audio 1 - C", "Audio 4 - D", "Audio 10 - K"])
    }

    @Test func aWriterThatFailedIsAnError() {
        var failed = RecordingEvent(at: 0, event: .screenFileWriterFailed, screen: "LG")
        failed.errorDetail = "cannot write"
        let summary = RecordingSummary(manifest: manifest([.finalized], events: [failed]), recordingFolder: "/r", seconds: 1, manifestWritten: true)
        #expect(summary.endedWithError)
        #expect(summary.text.contains("screen file writer failed, LG (cannot write)"))
    }
}

/// Camera files and camera events in the recording manifest (D74).
@Suite struct CameraFileManifestTests {
    private let berlin = TimeZone(identifier: "Europe/Berlin")!
    private let start = Date(timeIntervalSince1970: 1_794_488_585.120)  // 2026-11-12 14:03:05.120 in Berlin

    private func manifest() -> RecordingManifest {
        RecordingManifest(app: "Multi Screen Recorder (tests)", started: start, timeZone: berlin, settings: .defaults)
    }

    private func cameraFile(at seconds: Double = 1.5) -> RecordingManifest.CameraFile {
        RecordingManifest.CameraFile(
            name: "2026-11-12 14.03.06 Camera 1 - FaceTime HD Camera.mov", camera: "FaceTime HD Camera",
            cameraUniqueID: "0x1410000005ac8600", frameSize: FrameSize(width: 1920, height: 1080), start: seconds,
            timecode: "14:03:06:20", guideTracks: ["Audio inputs", "System audio"])
    }

    @Test func aCameraFileIsListedInFilesInTheOrderOfItsStartAndReadBack() throws {
        var manifest = manifest()
        manifest.files.append(.init(
            name: "2026-11-12 14.03.05 Screen 1 - Built-in Retina Display.mov", screen: "Built-in Retina Display",
            screenUUID: "37D8832A", frameSize: FrameSize(width: 1670, height: 1080), start: 0, timecode: "14:03:05:04"))
        manifest.cameraFiles.append(cameraFile())
        manifest.events.append(RecordingEvent(at: 1_000_000_000, event: .cameraConnected, camera: "FaceTime HD Camera"))
        let text = String(decoding: try manifest.jsonData(), as: UTF8.self)
        #expect(text.contains(#""camera" : "FaceTime HD Camera""#))
        #expect(text.contains(#""cameraUniqueID" : "0x1410000005ac8600""#))
        #expect(text.contains(#""cameraMode" : "real""#))
        let screen = try #require(text.range(of: "Screen 1 - Built-in Retina Display.mov"))
        let camera = try #require(text.range(of: "Camera 1 - FaceTime HD Camera.mov"))
        #expect(screen.lowerBound < camera.lowerBound)
        let read = try RecordingManifest(json: manifest.jsonData())
        #expect(read == manifest)
        #expect(read.cameraFiles.map(\.camera) == ["FaceTime HD Camera"])
        #expect(read.events.first?.camera == "FaceTime HD Camera")
    }

    @Test func aManifestOfBeforeCamerasRecordedNone() throws {
        let json = """
            {"app": "test", "state": "finalized", "started": "2026-11-20T10:00:00.000+01:00", "ended": null,
             "settings": {"audioMode": "wired", "resolution": "native", "systemAudio": true},
             "files": [], "events": [], "problems": []}
            """
        #expect(try RecordingManifest(json: Data(json.utf8)).settings.cameraMode == "none")
    }

    @Test func aCameraFileNotFinalizedMakesTheResultProblemsAndIsNamedWhenNothingWasTold() {
        var manifest = manifest()
        var file = cameraFile()
        file.state = .notFinalized
        manifest.cameraFiles = [file]
        manifest.finalize(ended: start + 60, timeZone: berlin)
        #expect(manifest.result == .problems)
        #expect(manifest.problems.first?.error == file.name)
    }

    @Test func aCameraEventIsAProblemOfTheCamera() {
        var failed = RecordingEvent(at: 2_000_000_000, event: .cameraStreamFailed, camera: "FaceTime HD Camera")
        failed.errorDetail = "the stand-in failed"
        #expect(failed.subject == "FaceTime HD Camera")
        #expect(failed.problem.problem == "Camera FaceTime HD Camera")
    }

    @Test func theCameraFilesAreListedAfterTheScreensAndBeforeTheAudio() {
        var recorded = manifest()
        recorded.cameraFiles = [cameraFile(at: 0)]
        recorded.files = [.init(
            name: "2026-11-12 14.03.06 Screen 1 - A.mov", screen: "A", screenUUID: "A", frameSize: FrameSize(width: 2, height: 2),
            start: 1, timecode: "t")]
        recorded.audioFiles = [RecordingManifest.AudioFile(
            name: "2026-11-12 14.03.05 Audio 0 - System.mov", audioSource: "System audio", audioSourceUID: nil, channels: .stereo,
            start: 0, timecode: "t")]
        let names = RecordingSummary(manifest: recorded, recordingFolder: "/r", seconds: 5, manifestWritten: true)
            .text.split(separator: "\n").dropFirst().prefix(3).map { $0.dropFirst(22).prefix { $0 != "." } }
        #expect(names == ["Screen 1 - A", "Camera 1 - FaceTime HD Camera", "Audio 0 - System"])
    }
}
