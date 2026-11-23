import Foundation
import Testing
@testable import RecorderLogic

/// The recording of 2026-11-20 12.36.09 and the timeline file made from it, which the owner's DaVinci Resolve 21.2 imported.
let timelineFixtureFolderName = "2026-11-20 12.36.09"

func timelineFixture(_ name: String) throws -> String {
    try repositoryFile("Tests/RecorderLogicTests/Fixtures/resolve-timeline/\(name)")
}

/// A manifest from the JSON parts of a recording that started 2026-11-20 10:00:00.000 in Berlin.
private func manifest(
    started: String = "2026-11-20T10:00:00.000+01:00", ended: String? = "2026-11-20T10:02:10.000+01:00", files: [String], events: [String] = [], problems: [String] = []
) throws -> RecordingManifest {
    let end = ended.map { "\"\($0)\"" } ?? "null"
    let json = """
        {"app": "test", "state": "finalized", "started": "\(started)", "ended": \(end),
         "settings": {"audioMode": "wired", "resolution": "native", "systemAudio": true},
         "files": [\(files.joined(separator: ","))], "events": [\(events.joined(separator: ","))],
         "problems": [\(problems.joined(separator: ","))]}
        """
    return try RecordingManifest(json: Data(json.utf8))
}

private func screen(
    _ stamp: String = "10.00.00", _ label: String, timecode: String = "10:00:00:00", start: Double = 0, end: Double? = 10,
    size: (Int, Int) = (1920, 1080), suffix: String = ""
) -> String {
    let source = label.components(separatedBy: " - ").dropFirst().joined(separator: " - ")
    let endText = end.map { String($0) } ?? "null"
    return """
        {"name": "2026-11-20 \(stamp) \(label)\(suffix).mov", "screen": "\(source)", "screenUUID": "u", "frameSize": [\(size.0), \(size.1)],
         "start": \(start), "end": \(endText), "timecode": "\(timecode)", "state": "finalized", "guideTracks": [],
         "framesRepeatedForLateness": 0}
        """
}

private func audio(
    _ stamp: String = "10.00.00", _ label: String, channels: String, timecode: String = "10:00:00:00", start: Double = 0,
    end: Double? = 10, suffix: String = "", delay: Double? = nil
) -> String {
    let source = label.components(separatedBy: " - ").dropFirst().joined(separator: " - ")
    let endText = end.map { String($0) } ?? "null"
    let delayText = delay.map { String($0) } ?? "null"
    return """
        {"name": "2026-11-20 \(stamp) \(label)\(suffix).mov", "audioSource": "\(source)", "channels": \(channels), "start": \(start),
         "end": \(endText), "timecode": "\(timecode)", "state": "finalized", "measuredDelay": \(delayText)}
        """
}

private func event(_ kind: String, at: Double, extra: String = "") -> String {
    #"{"at": \#(at), "event": "\#(kind)"\#(extra)}"#
}

private typealias JSON = [String: Any]

private func timeline(_ manifest: RecordingManifest, media: [String: Double] = [:]) throws -> JSON {
    let data = try ResolveTimeline.data(manifest: manifest, folderName: "2026-11-20 10.00.00", mediaSeconds: media)
    return try #require(JSONSerialization.jsonObject(with: data) as? JSON)
}

private extension Dictionary where Key == String, Value == Any {
    var stack: JSON { self["tracks"] as! JSON }
    var children: [JSON] { self["children"] as! [JSON] }
    var markers: [JSON] { self["markers"] as! [JSON] }
    var tracks: [JSON] { stack.children }
    var trackNames: [String] { tracks.map { $0["name"] as! String } }
    var clips: [JSON] { children.filter { ($0["OTIO_SCHEMA"] as! String) == "Clip.2" } }
    var note: String { ((self["metadata"] as! JSON)["Resolve_OTIO"] as! JSON)["Note"] as! String }
    var resolve: JSON { (self["metadata"] as! JSON)["Resolve_OTIO"] as! JSON }
    var frames: (start: Double, duration: Double) {
        let range = (self["source_range"] ?? self["marked_range"]) as! JSON
        return ((range["start_time"] as! JSON)["value"] as! Double, (range["duration"] as! JSON)["value"] as! Double)
    }
}

@Suite struct ResolveTimelineTests {
    @Test func theGoldenFileIsWhatWeWriteForTheRecordingResolveImported() throws {
        let manifest = try RecordingManifest(json: Data(timelineFixture("recording.json").utf8))
        let data = try ResolveTimeline.data(manifest: manifest, folderName: timelineFixtureFolderName, mediaSeconds: [:])
        #expect(String(decoding: data, as: UTF8.self) == (try timelineFixture("2026-11-20 12-36-09.otio")))
    }

    @Test(arguments: [
        ("2026-11-20 12.36.09", "2026-11-20 12-36-09.otio"),
        ("a/b:c", "a-b-c.otio"),
        ("Café ü", "Caf- -.otio"),
        ("tab\there", "tab-here.otio"),
    ])
    func theFileNameHasNoDotsAndOnlyPrintableAscii(folder: String, expected: String) {
        #expect(ResolveTimeline.fileName(forFolder: folder) == expected)
    }

    @Test func aLengthIsRoundedDownAndNeverUp() {
        #expect(ResolveTimeline.frames(seconds: 129.5) == 3885)
        #expect(ResolveTimeline.frames(seconds: 1.0999) == 32)
        #expect(ResolveTimeline.frames(seconds: 33.0 / 30 - 0.00001) == 32)
        // Floating point noise below a whole frame is not a lost frame.
        #expect(ResolveTimeline.frames(seconds: 33.0 / 30 - 1e-9) == 33)
        #expect(ResolveTimeline.frames(seconds: 0) == 0)
    }

    @Test func aClipIsTheFilesLengthRoundedDownAtItsTimecode() throws {
        let result = try timeline(manifest(files: [screen("10.00.00", "Screen 1 - A", timecode: "10:00:01:07", start: 1.2, end: 3.0999)]))
        let clip = try #require(result.tracks[0].clips.first)
        #expect(clip.frames == (1_080_037, 56))
        let reference = (clip["media_references"] as! JSON)["DEFAULT_MEDIA"] as! JSON
        let available = reference["available_range"] as! JSON
        #expect(((available["start_time"] as! JSON)["value"] as! Double, (available["duration"] as! JSON)["value"] as! Double) == (1_080_037, 56))
        #expect(reference["target_url"] as? String == "2026-11-20 10.00.00 Screen 1 - A.mov")
        #expect(reference["available_image_bounds"] is NSNull)
    }

    @Test func aFileWithoutAnEndTakesItsLengthFromTheMedia() throws {
        let recording = try manifest(ended: nil, files: [
            screen("10.00.00", "Screen 1 - A", end: nil), audio("10.00.00", "Audio 1 - M", channels: "1", end: 4.5),
        ])
        #expect(ResolveTimeline.filesWithoutEnd(in: recording) == ["2026-11-20 10.00.00 Screen 1 - A.mov"])
        let result = try timeline(recording, media: ["2026-11-20 10.00.00 Screen 1 - A.mov": 7.4999])
        #expect(result.tracks[0].clips[0].frames.duration == 224)
        #expect(result.tracks[1].clips[0].frames.duration == 135)
        #expect(throws: ResolveTimeline.Failure.lengthMissing(file: "2026-11-20 10.00.00 Screen 1 - A.mov")) {
            try timeline(recording)
        }
    }

    @Test func anUnfinishedRecordingSaysSoInItsInfoMarker() throws {
        let result = try timeline(manifest(ended: nil, files: [screen("10.00.00", "Screen 1 - A", end: nil)]), media: [
            "2026-11-20 10.00.00 Screen 1 - A.mov": 1,
        ])
        #expect(result.stack.markers[0].note.hasPrefix("Multi Screen Recorder, recording 2026-11-20 10:00:00, not finished.\n"))
    }

    @Test func theInfoMarkerSaysTheLargestScreensResolutionAndTheProblems() throws {
        let problem = #"{"at": 3.5, "problem": "Screen LG", "error": "stream failed", "errorDetail": null}"#
        let result = try timeline(manifest(
            files: [screen("10.00.00", "Screen 1 - A", size: (1920, 1080)), screen("10.00.00", "Screen 2 - B", size: (3440, 1440))],
            problems: [problem]))
        let info = result.stack.markers[0]
        #expect(info["name"] as? String == "Recording 2026-11-20 10-00-00: set resolution 3440 x 1440")
        #expect(info["color"] as? String == "RED")
        #expect(info.frames == (0, 1))
        #expect(info.note == """
            Multi Screen Recorder, recording 2026-11-20 10:00:00 to 10:02:10 (2m10s).
            Set the timeline resolution to 3440 x 1440 (the largest video file): Timeline > Timeline Settings.
            Tracks: one per screen, one per audio channel; the channels of one input are a linked group.
            Markers: blue = screen change, green = audio and other changes.
            Problems:
            10:00:03 +3.5s problem: Screen LG: stream failed
            """)
    }

    @Test func anAudioOnlyRecordingHasNoResolution() throws {
        let result = try timeline(manifest(files: [audio("10.00.00", "Audio 1 - M", channels: "1")]))
        let info = result.stack.markers[0]
        #expect(info["name"] as? String == "Recording 2026-11-20 10-00-00")
        #expect(!info.note.contains("resolution"))
        #expect(info.note.contains("Problems: none."))
        #expect(result.trackNames == ["Audio 1 - M"])
        #expect(result["global_start_time"] != nil)
    }

    @Test func theScreenThatStartsFirstAndRunsLongestIsV1ThenTheOthersByNumber() throws {
        let result = try timeline(manifest(files: [
            screen("10.00.00", "Screen 1 - A", end: 8),
            screen("10.00.00", "Screen 2 - B", end: 9),
            screen("10.00.00", "Screen 3 - C", end: 6),
            screen("10.00.05", "Screen 4 - D", timecode: "10:00:05:00", start: 5, end: 60),
            audio("10.00.00", "Audio 1 - M", channels: "1", end: 70),
        ]))
        #expect(result.trackNames == ["Screen 2 - B", "Screen 1 - A", "Screen 3 - C", "Screen 4 - D", "Audio 1 - M"])
        #expect(result.tracks.map { $0["kind"] as! String } == ["Video", "Video", "Video", "Video", "Audio"])
        #expect(result.tracks[0].resolve["Locked"] as? Bool == false)
    }

    /// D74: a camera file is a video track like a screen file, the cameras' tracks after the screens'.
    @Test func theCamerasAreVideoTracksAfterTheScreens() throws {
        let camera = """
            {"name": "2026-11-20 10.00.01 Camera 1 - FaceTime HD Camera.mov", "camera": "FaceTime HD Camera",
             "cameraUniqueID": "c", "frameSize": [1920, 1080], "start": 1, "end": 9, "timecode": "10:00:01:00",
             "state": "finalized", "guideTracks": [], "framesRepeatedForLateness": 0}
            """
        let result = try timeline(manifest(files: [
            screen("10.00.00", "Screen 1 - A", end: 8),
            camera,
            audio("10.00.00", "Audio 1 - M", channels: "1", end: 70),
        ]))
        #expect(result.trackNames == ["Screen 1 - A", "Camera 1 - FaceTime HD Camera", "Audio 1 - M"])
        #expect(result.tracks.map { $0["kind"] as! String } == ["Video", "Video", "Audio"])
    }

    /// The resolution to set is the largest video file's, a camera's too.
    @Test func theResolutionToSetIsTheLargestVideoFiles() throws {
        let camera = """
            {"name": "2026-11-20 10.00.01 Camera 1 - BRIO.mov", "camera": "BRIO",
             "cameraUniqueID": "c", "frameSize": [3840, 2160], "start": 1, "end": 9, "timecode": "10:00:01:00",
             "state": "finalized", "guideTracks": [], "framesRepeatedForLateness": 0}
            """
        let result = try timeline(manifest(files: [screen("10.00.00", "Screen 1 - A", end: 8), camera]))
        #expect(result.stack.markers[0].note.contains(
            "Set the timeline resolution to 3840 x 2160 (the largest video file): Timeline > Timeline Settings."))
    }

    @Test func v1IsChosenAmongTheScreensThatStartFirstNotAmongAllFiles() throws {
        let result = try timeline(manifest(files: [
            audio("09.59.59", "Audio 1 - M", channels: "1", timecode: "09:59:59:29", start: 0, end: 70),
            screen("10.00.00", "Screen 1 - A", end: 8),
            screen("10.00.00", "Screen 2 - B", end: 9),
        ]))
        #expect(result.trackNames == ["Screen 2 - B", "Screen 1 - A", "Audio 1 - M"])
    }

    @Test func withoutAScreenAtTheTimelineStartTheEarliestScreenIsV1() throws {
        let result = try timeline(manifest(files: [
            screen("10.00.05", "Screen 2 - B", timecode: "10:00:05:00", start: 5, end: 60),
            screen("10.00.06", "Screen 1 - A", timecode: "10:00:06:00", start: 6, end: 10),
            audio("10.00.00", "Audio 1 - M", channels: "1", end: 70),
        ]))
        #expect(result.trackNames == ["Screen 2 - B", "Screen 1 - A", "Audio 1 - M"])
    }

    @Test func eventsOnOneFrameMakeOneMarkerAndAnEventAtFrameZeroJoinsTheInfoMarker() throws {
        let result = try timeline(manifest(
            files: [screen("10.00.00", "Screen 1 - A")],
            events: [
                event("audio input connected", at: 0.01, extra: #", "audioSource": "Mic""#),
                event("default microphone changed", at: 10, extra: #", "from": "A", "to": "B""#),
                event("audio input disconnected", at: 10.01, extra: #", "audioSource": "A""#),
                event("screen connected", at: 20, extra: #", "screen": "LG""#),
                event("main screen changed", at: 20.01, extra: #", "screen": "LG""#),
            ]))
        let markers = result.stack.markers
        #expect(markers.count == 3)
        #expect(markers[0]["name"] as? String == "Recording 2026-11-20 10-00-00: set resolution 1920 x 1080")
        #expect(markers[0].note.hasSuffix("Problems: none.\n10:00:00 +0.0s audio input connected: Mic"))
        #expect(markers[1].frames == (300, 1))
        #expect(markers[1]["name"] as? String == "default microphone changed; audio input disconnected")
        #expect(markers[1]["color"] as? String == "GREEN")
        #expect(markers[1].note == "10:00:10 +10.0s default microphone changed A → B\n10:00:10 +10.0s audio input disconnected: A")
        #expect(markers[2].frames == (600, 1))
        #expect(markers[2]["color"] as? String == "BLUE")
        #expect(markers[2]["name"] as? String == "screen connected; main screen changed")
    }

    @Test func markerFramesCountFromTheTimelineStartNotFromMidnight() throws {
        let result = try timeline(manifest(
            files: [screen("10.00.02", "Screen 1 - A", timecode: "10:00:02:00", start: 2)],
            events: [event("screen connected", at: 12, extra: #", "screen": "LG""#)]))
        #expect(result["global_start_time"] != nil)
        #expect(result.stack.markers[1].frames == (300, 1))
    }

    /// A measured delay places the audio clip that much earlier, to the nearest frame; one that would start
    /// before the timeline is trimmed at its start instead (D77).
    @Test func aMeasuredDelayPlacesTheAudioClipEarlier() throws {
        let result = try timeline(manifest(files: [
            screen("10.00.00", "Screen 1 - A", timecode: "10:00:00:00", end: 20),
            audio("10.00.01", "Audio 1 - Razer", channels: "1", timecode: "10:00:01:00", start: 1, end: 11),
            audio("10.00.01", "Audio 2 - Osmo", channels: "1", timecode: "10:00:01:00", start: 1, end: 11, delay: 0.55),
            audio("10.00.00", "Audio 3 - BRIO", channels: "1", timecode: "10:00:00:00", start: 0, end: 10, delay: 0.55),
        ]))
        #expect(result.trackNames == ["Screen 1 - A", "Audio 1 - Razer", "Audio 2 - Osmo", "Audio 3 - BRIO"])
        #expect(result.tracks[1].children[0].frames == (0, 30))
        #expect(result.tracks[2].children[0].frames == (0, 13))
        #expect(result.tracks[2].clips[0].frames == (1_080_030, 300))
        let trimmed = result.tracks[3].clips[0]
        #expect(result.tracks[3].children.count == 1)
        #expect(trimmed.frames == (1_080_017, 283))
        let available = ((trimmed["media_references"] as! JSON)["DEFAULT_MEDIA"] as! JSON)["available_range"] as! JSON
        #expect(((available["start_time"] as! JSON)["value"] as! Double, (available["duration"] as! JSON)["value"] as! Double)
            == (1_080_000, 300))
    }

    /// A delayed file that would overlap its source's previous one leaves out its head, so what
    /// it plays stays at its own time, never pushed later.
    @Test func aDelayedClipOverlappingThePreviousOneLeavesOutItsHead() throws {
        let result = try timeline(manifest(files: [
            audio("10.00.00", "Audio 2 - Osmo", channels: "1", timecode: "10:00:00:00", start: 0, end: 10),
            audio("10.00.10", "Audio 2 - Osmo", channels: "1", timecode: "10:00:10:06", start: 10.2, end: 20, delay: 0.55),
        ]))
        let children = result.tracks[0].children
        #expect(children.map { $0["OTIO_SCHEMA"] as! String } == ["Clip.2", "Clip.2"])
        #expect(children[0].frames == (1_080_000, 300))
        // 0.55 s is 17 frames earlier: from frame 289, 11 frames into the first file, which ends at frame 300.
        #expect(children[1].frames == (1_080_317, 283))
    }

    @Test func aSourceWithTwoFilesIsOneTrackWithAGapBetweenAndNoGapAfter() throws {
        let result = try timeline(manifest(files: [
            audio("10.00.00", "Audio 2 - R", channels: "1", timecode: "10:00:00:10", start: 0.3, end: 3),
            audio("10.00.05", "Audio 2 - R", channels: "1", timecode: "10:00:05:00", start: 5, end: 9),
            audio("10.00.10", "Audio 2 - R", channels: "1", timecode: "10:00:10:00", start: 10, end: 12, suffix: " (2)"),
        ]))
        #expect(result.trackNames == ["Audio 2 - R"])
        let kinds = result.tracks[0].children.map { $0["OTIO_SCHEMA"] as! String }
        #expect(kinds == ["Clip.2", "Gap.1", "Clip.2", "Gap.1", "Clip.2"])
        #expect(result.tracks[0].children[1].frames == (0, 59))
        #expect(result.tracks[0].children[3].frames == (0, 30))
        #expect(result.tracks[0].resolve["Audio Type"] as? String == "Mono")
    }

    @Test func aSuffixOfACopiedFileNameIsNotPartOfTheTrackName() throws {
        let result = try timeline(manifest(files: [
            screen("10.00.00", "Screen 1 - A", suffix: " (2)"), audio("10.00.00", "Audio 3 - Cam (Pro)", channels: "1", suffix: " (3)"),
        ]))
        #expect(result.trackNames == ["Screen 1 - A", "Audio 3 - Cam (Pro)"])
    }

    @Test func aScreenNamedWithACopySuffixKeepsItInItsTrackName() throws {
        let result = try timeline(manifest(files: [
            screen("10.00.00", "Screen 1 - DELL U2720Q (2)"),
            screen("10.00.05", "Screen 1 - DELL U2720Q (2)", timecode: "10:00:05:00", start: 5, suffix: " (2)"),
        ]))
        #expect(result.trackNames == ["Screen 1 - DELL U2720Q (2)"])
    }

    @Test func aFileOfZeroFramesGetsNoClipAndNoGap() throws {
        let result = try timeline(manifest(files: [
            audio("10.00.00", "Audio 1 - M", channels: "1", timecode: "10:00:01:00", start: 1, end: 5),
            audio("10.00.06", "Audio 1 - M", channels: "1", timecode: "10:00:06:00", start: 6, end: 6.02),
            audio("10.00.08", "Audio 1 - M", channels: "1", timecode: "10:00:08:00", start: 8, end: 9),
            screen("10.00.00", "Screen 2 - Z", end: 0.01),
        ]))
        #expect(result.trackNames == ["Audio 1 - M"])
        let kinds = result.tracks[0].children.map { $0["OTIO_SCHEMA"] as! String }
        #expect(kinds == ["Clip.2", "Gap.1", "Clip.2"])
        #expect(result.tracks[0].children[1].frames == (0, 90))
        #expect(result["global_start_time"] != nil)
    }

    @Test func aFileAfterMidnightIsPlacedAfterTheEarlierFilesAndKeepsItsOwnTimecode() throws {
        let result = try timeline(manifest(
            started: "2026-11-20T23:50:00.000+01:00", ended: "2026-11-21T00:02:00.000+01:00",
            files: [
                screen("23.50.00", "Screen 1 - A", timecode: "23:50:00:00", end: 700),
                audio("00.01.10", "Audio 1 - M", channels: "1", timecode: "00:01:10:00", start: 670, end: 700),
            ],
            events: [event("screen connected", at: 680, extra: #", "screen": "LG""#)]))
        let startOfScreen = ((23 * 60 + 50) * 60) * 30.0
        func start(_ clip: JSON) -> Double { (((clip["source_range"] as! JSON)["start_time"] as! JSON)["value"] as! Double) }
        #expect(((result["global_start_time"] as! JSON)["value"] as! Double) == startOfScreen)
        #expect(result.tracks[1].children.map { $0["OTIO_SCHEMA"] as! String } == ["Gap.1", "Clip.2"])
        #expect(result.tracks[1].children[0].frames == (0, 20100))
        #expect(start(result.tracks[1].clips[0]) == 2100)
        #expect(result.stack.markers[1].frames == (20400, 1))
    }

    @Test func audioTracksFollowTheSourceNumberWithLinkedChannelsAndTheStereoSystemAudio() throws {
        let result = try timeline(manifest(files: [
            audio("10.00.00", "Audio 2 - Two", channels: "2"),
            audio("10.00.00", "Audio 1 - One", channels: "1"),
            audio("10.00.00", "Audio 0 - System", channels: "\"stereo\""),
            audio("10.00.00", "Audio 3 - Two again", channels: "2"),
        ]))
        #expect(result.trackNames == [
            "Audio 0 - System", "Audio 1 - One", "Audio 2 - Two, channel 1", "Audio 2 - Two, channel 2",
            "Audio 3 - Two again, channel 1", "Audio 3 - Two again, channel 2",
        ])
        let kinds = result.tracks.map { $0.resolve["Audio Type"] as! String }
        #expect(kinds == ["Stereo", "Mono", "Mono", "Mono", "Mono", "Mono"])
        func channels(_ track: Int) -> [[String: Int]] { result.tracks[track].clips[0].resolve["Channels"] as! [[String: Int]] }
        #expect(channels(0) == [["Source Channel ID": 0, "Source Track ID": 0], ["Source Channel ID": 1, "Source Track ID": 0]])
        #expect(channels(1) == [["Source Channel ID": 0, "Source Track ID": 0]])
        #expect(channels(3) == [["Source Channel ID": 0, "Source Track ID": 1]])
        let links = result.tracks.map { $0.clips[0].resolve["Link Group ID"] as? Int }
        #expect(links == [nil, nil, 1, 1, 2, 2])
    }

    @Test func aTimestampOrTimecodeThatCannotBeReadIsAnError() {
        #expect(throws: ResolveTimeline.Failure.self) {
            try ResolveTimeline.data(
                manifest: try manifest(files: [screen("10.00.00", "Screen 1 - A", timecode: "10:00")]), folderName: "x", mediaSeconds: [:])
        }
    }
}
