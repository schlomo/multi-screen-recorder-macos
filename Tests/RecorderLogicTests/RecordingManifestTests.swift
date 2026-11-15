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
        let keys = ["app", "events", "files", "settings", "started", "state"].map { text.range(of: "\n  \"\($0)\"")!.lowerBound }
        #expect(keys == keys.sorted())
        #expect(try RecordingManifest(json: manifest.jsonData()) == manifest)
    }

    @Test func aRecordingWhoseProcessIsGoneIsNotFinalized() {
        var manifest = manifest()
        manifest.files.append(.init(name: "a.mov", display: "A", displayUUID: "A", frameSize: FrameSize(width: 2, height: 2),
                                    start: 0, timecode: "00:00:00:00"))
        manifest.files.append(.init(name: "b.mov", display: "A", displayUUID: "A", frameSize: FrameSize(width: 2, height: 2),
                                    start: 0, timecode: "00:00:00:00"))
        manifest.files[0].state = .finalized
        let marked = manifest.markedNotFinalized()
        #expect(marked.state == .notFinalized)
        #expect(marked.files.map(\.state) == [.finalized, .notFinalized])
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
    @Test func theBadgeCountsMinutesUntilSomethingNeedsThePerson() {
        var status = RecordingStatus()
        #expect(status.badge(elapsedSeconds: 125) == "2")
        status.isLowOnDisk = true
        #expect(status.badge(elapsedSeconds: 125) == "!")
        status.isLowOnDisk = false
        status.displayShowingAnotherDisplaysPicture = "LG"
        #expect(status.badge(elapsedSeconds: 125) == "!")
        status.displayShowingAnotherDisplaysPicture = nil
        status.problems.append("Cannot write the recording manifest: full")
        #expect(status.badge(elapsedSeconds: 125) == "!")
    }

    @Test func theStopQuestionListsTheProblems() {
        var status = RecordingStatus()
        #expect(status.stopQuestionDetails == nil)
        status.problems = ["a", "b"]
        #expect(status.stopQuestionDetails == "a\n\nb")
    }
}

@Suite struct CrashMarkerTests {
    @Test func aMarkerNamesItsFolderAndIsNamedByItsProcess() throws {
        let marker = CrashMarker(recordingFolder: "/Users/a/Movies/Multi Screen Recorder/2026-11-12 14.03.05")
        #expect(try CrashMarker(json: marker.jsonData()) == marker)
        #expect(CrashMarker.fileName(processID: 4711) == "4711.json")
        #expect(CrashMarker.processID(fileName: "4711.json") == 4711)
        #expect(CrashMarker.processID(fileName: "notes.txt") == nil)
        #expect(CrashMarker.processID(fileName: "x.json") == nil)
    }

    @Test func theReportIsTheDesignsText() throws {
        let marker = CrashMarker(recordingFolder: "<folder>")
        let design = try repositoryFile("docs/design/recorder.md").replacingOccurrences(of: "\n", with: " ")
        #expect(design.contains("(\"\(marker.report)\")"))
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
        let summary = RecordingSummary(manifest: manifest([.finalized]), recordingFolder: "/r", seconds: 3725)
        #expect(!summary.endedWithError)
        #expect(summary.text == "Recorded 1h02m05s into /r\n  f0.mov  finalized\n")
    }

    @Test func aFileNotFinalizedOrAnErrorEventIsAnError() {
        #expect(RecordingSummary(manifest: manifest([.notFinalized]), recordingFolder: "/r", seconds: 1).endedWithError)
        var failed = RecordingEvent(at: 65_000_000_000, event: .displayStreamFailed, display: "LG")
        failed.error = "-3815"
        let summary = RecordingSummary(
            manifest: manifest([.finalized, .finalized], events: [failed, RecordingEvent(at: 0, event: .sleep)]),
            recordingFolder: "/r", seconds: 70)
        #expect(summary.endedWithError)
        #expect(summary.text.hasSuffix("Error at 1m05s: display stream failed, LG (-3815)\n"))
    }

    @Test func aWriterThatFailedIsAnError() {
        var failed = RecordingEvent(at: 0, event: .displayFileWriterFailed, display: "LG")
        failed.error = "cannot write"
        let summary = RecordingSummary(manifest: manifest([.finalized], events: [failed]), recordingFolder: "/r", seconds: 1)
        #expect(summary.endedWithError)
        #expect(summary.text.contains("display file writer failed, LG (cannot write)"))
    }
}
