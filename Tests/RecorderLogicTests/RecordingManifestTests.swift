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
            name: "2026-11-12 14.03.05 Display 1 - Built-in Retina Display.mov", display: "Built-in Retina Display",
            displayUUID: "37D8832A-2D66-02CA-B9F7-8F30A301B230", frameSize: FrameSize(width: 1670, height: 1080), start: 0,
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

    /// D47: the result is ok when every file is finalized and no display
    /// file was ended by a failure; a problem told alone does not change it.
    @Test(arguments: [
        RecordingEvent.Kind.displayStreamFailed, .displayFileWriterFailed, .diskFull, .displayFileWriterFellBehind,
        .displayShowsAnotherDisplaysPicture,
    ])
    func aDisplayFileEndedByAFailureMakesTheResultProblems(failure: RecordingEvent.Kind) {
        var manifest = manifest()
        manifest.events.append(RecordingEvent(at: 0, event: failure, display: "A"))
        manifest.finalize(ended: start + 60, timeZone: berlin)
        #expect(manifest.result == .problems)
    }

    @Test func aFileNotFinalizedMakesTheResultProblems() {
        var manifest = manifest()
        manifest.files.append(.init(name: "a.mov", display: "A", displayUUID: "A", frameSize: FrameSize(width: 2, height: 2),
                                    start: 0, timecode: "00:00:00:00"))
        manifest.finalize(ended: start + 60, timeZone: berlin)
        #expect(manifest.result == .problems)
    }

    @Test func aProblemToldOrAnEventThatIsNoFailureLeavesTheResultOk() {
        var manifest = manifest()
        manifest.problems.append(RecordingProblem(at: 2_000_000_000, problem: "The displays cannot be read", error: "denied"))
        for kind in RecordingEvent.Kind.allCases where !kind.isFailure {
            manifest.events.append(RecordingEvent(at: 0, event: kind, display: "A"))
        }
        manifest.finalize(ended: start + 60, timeZone: berlin)
        #expect(manifest.result == .ok)
        #expect(manifest.problems.count == 1)
    }

    @Test func theFailuresAreTheWaysAFileEndsBadly() {
        #expect(RecordingEvent.Kind.allCases.filter(\.isFailure) == [
            .displayStreamFailed, .displayShowsAnotherDisplaysPicture, .displayFileWriterFellBehind, .displayFileWriterFailed, .diskFull,
            .audioInputFailed, .systemAudioFailed, .audioFileWriterFailed,
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

    @Test func filesAreWrittenInTheOrderOfTheirStartAndReadBackByKind() throws {
        var manifest = manifest()
        manifest.files = [RecordingManifest.DisplayFile(
            name: "d.mov", display: "LG", displayUUID: "U", frameSize: FrameSize(width: 2, height: 2), start: 3, timecode: "t")]
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
        #expect(try RecordingManifest(json: data) == manifest)
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
        var gap = RecordingEvent(at: 0, event: .audioInputGap, display: "Mic")
        gap.length = 0.25
        var changed = RecordingEvent(at: 0, event: .defaultMicrophoneChanged)
        changed.from = "Mic"
        changed.to = "Razer"
        for event in [gap, changed] {
            #expect(try JSONDecoder().decode(RecordingEvent.self, from: prettyJSON(event)) == event)
        }
        let text = String(decoding: try prettyJSON(changed), as: UTF8.self)
        #expect(text.contains(#""from" : "Mic""#))
    }

    @Test func aProblemHasItsTimeAndFullError() throws {
        let problem = RecordingProblem(at: 1_446_200_400_000, problem: "Display file a.mov", error: "The operation could not be completed")
        #expect(problem.at == 1446.2)
        #expect(problem.text == "Display file a.mov: The operation could not be completed")
        #expect(RecordingProblem(at: 0, problem: "The displays cannot be read", error: nil).text == "The displays cannot be read")
        let text = String(decoding: try prettyJSON(RecordingProblem(at: 0, problem: "p", error: nil)), as: UTF8.self)
        #expect(text.contains(#""error" : null"#))
    }

    @Test func eventsAndProblemsAreWrittenInTheOrderOfTheirTime() throws {
        var manifest = manifest()
        manifest.events = [
            RecordingEvent(at: 5_000_000_000, event: .wake), RecordingEvent(at: 2_000_000_000, event: .sleep),
            RecordingEvent(at: 2_000_000_000, event: .diskFull, display: "A"),
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
        let end = try #require(text[start...].range(of: "each names its display")).lowerBound
        let listed = text[start..<end].replacingOccurrences(of: "\n", with: " ")
            .matches(of: /`([^`]+)`/).map { String($0.output.1) }
        #expect(listed == RecordingEvent.Kind.allCases.map(\.rawValue))
    }

    @Test func theExamplesDisplayFilesReadAsTheManifestWritesThem() throws {
        let text = try design()
        let start = try #require(text.range(of: "```json\n{\n  \"app\"")).upperBound
        let json = "{\n  \"app\"" + text[start...].prefix { _ in true }.split(separator: "```").first!
        let object = try #require(try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
        let files = try #require(object["files"] as? [[String: Any]])
        let displayFiles = files.filter { $0["display"] != nil }
        #expect(displayFiles.count == 4)
        for file in displayFiles {
            let data = try JSONSerialization.data(withJSONObject: file)
            let decoded = try JSONDecoder().decode(RecordingManifest.DisplayFile.self, from: data)
            let encoded = try #require(try JSONSerialization.jsonObject(with: prettyJSON(decoded)) as? [String: Any])
            #expect(Set(encoded.keys) == Set(file.keys))
            #expect(decoded.name == file["name"] as? String)
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
        #expect(Set(settings.keys) == ["resolution", "audioMode", "systemAudio"])
        #expect(object["started"] as? String == manifest().started)
    }

    @Test func theExamplesFileNamesAreTheNamesTheRecorderGives() throws {
        let start = self.start
        #expect(RecordingNames.recordingFolder(start: start, timeZone: berlin) == "2026-11-12 14.03.05")
        let first = RecordingNames.displayFile(start: start, timeZone: berlin, number: 1, display: "Built-in Retina Display")
        let back = RecordingNames.displayFile(start: start + 1476, timeZone: berlin, number: 2, display: "LG HDR 4K")
        let text = try design()
        #expect(text.contains("\n  \(first)\n"))
        #expect(text.contains("\n  \(back)    ← back after a reconnect"))
        let timecode = Timecode(start: start, timeZone: berlin)
        #expect(text.contains(#""timecode": "\#(timecode.text(ofTick: 1476 * Int64(RecorderValues.framesPerSecond)))""#))
    }
}

@Suite struct RecordingNamesTests {
    private let utc = TimeZone(identifier: "UTC")!

    /// A name never stops a display from recording: `/` and `:` become `-`.
    @Test func charactersAFileNameCannotHoldBecomeDashes() {
        let name = RecordingNames.displayFile(start: Date(timeIntervalSince1970: 0), timeZone: utc, number: 3, display: "Dell U2720Q/2: left")
        #expect(name == "1970-01-01 00.00.00 Display 3 - Dell U2720Q-2- left.mov")
    }

    @Test func anAudioFileIsNamedByItsSource() {
        let start = Date(timeIntervalSince1970: 0)
        let microphone = RecordingNames.audioFile(
            start: start, timeZone: utc, source: .audioInput(name: "Mic 1/2", coreAudioUID: "u", channelCount: 1))
        #expect(microphone == "1970-01-01 00.00.00 Microphone - Mic 1-2.mov")
        #expect(RecordingNames.audioFile(start: start, timeZone: utc, source: .systemAudio) == "1970-01-01 00.00.00 System audio.mov")
        #expect(RecordingNames.audioFile(start: start, timeZone: utc, source: .systemAudio, taken: ["1970-01-01 00.00.00 System audio.mov"])
            == "1970-01-01 00.00.00 System audio (2).mov")
    }

    @Test func aTakenNameGetsANumber() {
        let start = Date(timeIntervalSince1970: 0)
        let name = RecordingNames.displayFile(start: start, timeZone: utc, number: 2, display: "LG HDR 4K")
        #expect(name == "1970-01-01 00.00.00 Display 2 - LG HDR 4K.mov")
        #expect(RecordingNames.displayFile(start: start, timeZone: utc, number: 2, display: "LG HDR 4K", taken: [name])
            == "1970-01-01 00.00.00 Display 2 - LG HDR 4K (2).mov")
        #expect(RecordingNames.displayFile(
            start: start, timeZone: utc, number: 2, display: "LG HDR 4K",
            taken: [name, "1970-01-01 00.00.00 Display 2 - LG HDR 4K (2).mov"])
            == "1970-01-01 00.00.00 Display 2 - LG HDR 4K (3).mov")
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
        status.displayShowingAnotherDisplaysPicture = "LG"
        #expect(status.badge == "!")
        status.displayShowingAnotherDisplaysPicture = nil
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
            var file = RecordingManifest.DisplayFile(
                name: "f\(index).mov", display: "D", displayUUID: "U", frameSize: FrameSize(width: 2, height: 2), start: 0,
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
        var failed = RecordingEvent(at: 65_000_000_000, event: .displayStreamFailed, display: "LG")
        failed.error = "-3811"
        let summary = RecordingSummary(
            manifest: manifest([.finalized, .finalized], events: [failed, RecordingEvent(at: 0, event: .sleep)]),
            recordingFolder: "/r", seconds: 70, manifestWritten: true)
        #expect(summary.endedWithError)
        #expect(summary.text.hasSuffix("Error at 1m05s: display stream failed, LG (-3811)\n"))
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
        told.problems = [RecordingProblem(at: 65_000_000_000, problem: "The displays cannot be read", error: "denied")]
        let summary = RecordingSummary(manifest: told, recordingFolder: "/r", seconds: 70, manifestWritten: true)
        #expect(!summary.endedWithError)
        #expect(summary.text.hasSuffix("Problem at 1m05s: The displays cannot be read: denied\n"))
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

    @Test func aWriterThatFailedIsAnError() {
        var failed = RecordingEvent(at: 0, event: .displayFileWriterFailed, display: "LG")
        failed.error = "cannot write"
        let summary = RecordingSummary(manifest: manifest([.finalized], events: [failed]), recordingFolder: "/r", seconds: 1, manifestWritten: true)
        #expect(summary.endedWithError)
        #expect(summary.text.contains("display file writer failed, LG (cannot write)"))
    }
}
