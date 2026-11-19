import Foundation
import Testing
@testable import EndToEndLogic

@Suite struct FileCheckTests {
    /// ffprobe's output for a screen file of 4.9 s, as read on this Mac.
    static func screenProbe(frames: Int = 147, timecode: String = "08:00:56:22", titles: [String] = ["Audio inputs", "System audio"],
                            size: (Int, Int) = (1920, 1080)) -> String {
        let audio = titles.enumerated().map { index, title in
            """
            {"index": \(index + 1), "codec_name": "aac", "codec_type": "audio", "sample_rate": "48000", "channels": \(index + 1),
             "start_time": "\(index == 0 ? "0.004792" : "0.000000")", "duration": "4.842667", "nb_read_frames": "225", "tags": {"title": "\(title)"}}
            """
        }
        return """
            {"streams": [
             {"index": 0, "codec_name": "hevc", "codec_type": "video", "width": \(size.0), "height": \(size.1), "duration": "4.900000",
              "nb_read_frames": "\(frames)", "tags": {"title": "Screen 2 - Wacom One 13T", "timecode": "08:00:56:22"}},
             \(audio.joined(separator: ",\n"))\(audio.isEmpty ? "" : ",")
             {"index": \(titles.count + 1), "codec_type": "data", "duration": "0.033333", "tags": {"timecode": "\(timecode)"}}
            ]}
            """
    }

    static let screenFile = ListedFile(
        name: "2026-11-19 08.00.56 Screen 2 - Wacom One 13T.mov",
        source: .screen(uuid: "037036FB-11CB-443E-B860-302AC081D674", name: "Wacom One 13T", frameSize: [1920, 1080],
                        guideTracks: ["Audio inputs", "System audio"]),
        label: "Screen 2 - Wacom One 13T", start: 0.3, end: 5.2, timecode: "08:00:56:22", state: "finalized")

    static func audioProbe(seconds: String = "4.297167", frames: Int = 202, titles: [String]) -> String {
        let tracks = titles.enumerated().map { index, title in
            """
            {"index": \(index), "codec_name": "aac", "codec_type": "audio", "sample_rate": "48000", "channels": 1,
             "duration": "\(seconds)", "nb_read_frames": "\(frames)", "tags": {"title": "\(title)", "timecode": "08:00:57:12"}}
            """
        }
        return """
            {"streams": [\(tracks.joined(separator: ",")), {"index": \(titles.count), "codec_type": "data",
             "duration": "0.033333", "tags": {"timecode": "08:00:57:12"}}]}
            """
    }

    static let audioFile = ListedFile(
        name: "2026-11-19 08.00.57 Audio 4 - BlackHole 2ch.mov",
        source: .audioInput(uid: "BlackHole2ch_UID", name: "BlackHole 2ch", channels: 2),
        label: "Audio 4 - BlackHole 2ch", start: 0.9666666666666667, end: 5.263833333333333, timecode: "08:00:57:12",
        state: "finalized")
    static let audioTitles = ["Audio 4 - BlackHole 2ch, channel 1", "Audio 4 - BlackHole 2ch, channel 2"]

    func failures(_ file: ListedFile, _ probe: String, ending: ManifestExpectation.Ending = .finalized) throws -> [String] {
        FileCheck.failures(file, probed: try ProbedFile(ffprobeJSON: Data(probe.utf8)), ending: ending, slack: 0.5)
    }

    @Test func ffprobesStreamsAreRead() throws {
        let probed = try ProbedFile(ffprobeJSON: Data(Self.screenProbe().utf8))
        #expect(probed.video.map(\.framesRead) == [147])
        #expect(probed.audio.map(\.title) == ["Audio inputs", "System audio"])
        #expect(probed.audio.map(\.sampleRate) == [48_000, 48_000])
        #expect(probed.timecodeTrack.map(\.index) == [3])
        #expect(probed.audio.map(\.startTime) == [0.004792, 0])
        #expect(throws: ProbeError.self) { try ProbedFile(ffprobeJSON: Data("{}".utf8)) }
    }

    @Test func aTracksFirstSampleIsAtTheTimecodePlusItsStartTime() throws {
        let probed = try ProbedFile(ffprobeJSON: Data(Self.screenProbe().utf8))
        // The guide track "Audio inputs" starts 4.792 ms into the file (its edit list).
        #expect(abs(probed.audio[0].firstSampleTime(fileStartsAt: 100) - 100.004792) < 1e-9)
        #expect(probed.audio[1].firstSampleTime(fileStartsAt: 100) == 100)
        let noStart = try ProbedFile(ffprobeJSON: Data(Self.audioProbe(titles: ["a"]).utf8))
        #expect(noStart.audio[0].firstSampleTime(fileStartsAt: 100) == 100)
    }

    @Test func aScreenFileAsRecordedPasses() throws {
        #expect(try failures(Self.screenFile, Self.screenProbe()) == [])
    }

    @Test func aFrameMoreOrLessThanThirtyASecondFails() throws {
        #expect(try failures(Self.screenFile, Self.screenProbe(frames: 146)) == [])
        #expect(try failures(Self.screenFile, Self.screenProbe(frames: 145)) == [
            "2026-11-19 08.00.56 Screen 2 - Wacom One 13T.mov: 145 frames, expected 147 for its length (30 per second)",
        ])
    }

    @Test func anotherTimecodeOrFrameSizeFails() throws {
        #expect(try failures(Self.screenFile, Self.screenProbe(timecode: "08:00:56:23")) == [
            "2026-11-19 08.00.56 Screen 2 - Wacom One 13T.mov: timecode track [\"08:00:56:23\"], expected one with 08:00:56:22",
        ])
        #expect(try failures(Self.screenFile, Self.screenProbe(size: (1920, 1088))) == [
            "2026-11-19 08.00.56 Screen 2 - Wacom One 13T.mov: video 1920×1088, expected 1920×1080",
        ])
    }

    @Test func guideTracksSwappedOrMissingFail() throws {
        #expect(try failures(Self.screenFile, Self.screenProbe(titles: ["System audio", "Audio inputs"])) == [
            "2026-11-19 08.00.56 Screen 2 - Wacom One 13T.mov: audio tracks [\"System audio\", \"Audio inputs\"], expected the guide tracks [\"Audio inputs\", \"System audio\"]",
        ])
        #expect(try failures(Self.screenFile, Self.screenProbe(titles: ["Audio inputs"])).count == 1)
    }

    @Test func anAudioFileAsRecordedPasses() throws {
        #expect(try failures(Self.audioFile, Self.audioProbe(titles: Self.audioTitles)) == [])
    }

    @Test func anAudioFileShorterThanItsEndMinusItsStartFails() throws {
        #expect(try failures(Self.audioFile, Self.audioProbe(seconds: "4.2", titles: Self.audioTitles)).count == 2)
    }

    @Test func anAudioFileWithTracksSwappedOrMissingFails() throws {
        #expect(try failures(Self.audioFile, Self.audioProbe(titles: Self.audioTitles.reversed())).count == 1)
        #expect(try failures(Self.audioFile, Self.audioProbe(titles: [Self.audioTitles[0]])).count == 1)
    }

    @Test func aKilledFileIsReadableUpToItsLastFragment() throws {
        var killed = Self.audioFile
        killed.end = nil
        // 202 AAC packets are 4.31 s: enough for a kill at 7 s (7 - 0.97 - 2 - 0.5 = 3.53 s), not at 9 s.
        #expect(try failures(killed, Self.audioProbe(titles: Self.audioTitles), ending: .killed(at: 7)) == [])
        #expect(try failures(killed, Self.audioProbe(titles: Self.audioTitles), ending: .killed(at: 9)).count == 2)
        var screen = Self.screenFile
        screen.end = nil
        #expect(try failures(screen, Self.screenProbe(frames: 147), ending: .killed(at: 7)) == [])
        #expect(try failures(screen, Self.screenProbe(frames: 147), ending: .killed(at: 8)) == [
            "2026-11-19 08.00.56 Screen 2 - Wacom One 13T.mov: 147 frames readable after the kill, expected at least 156",
        ])
    }

    @Test func aSystemAudioFileIsOneStereoTrack() throws {
        let file = ListedFile(name: "x Audio 0 - System.mov", source: .systemAudio, label: "Audio 0 - System", start: 0.9666666666666667,
                              end: 5.263833333333333, timecode: "08:00:57:12", state: "finalized")
        let stereo = Self.audioProbe(titles: ["Audio 0 - System"]).replacingOccurrences(of: "\"channels\": 1", with: "\"channels\": 2")
        #expect(try failures(file, stereo) == [])
        #expect(try failures(file, Self.audioProbe(titles: ["Audio 0 - System"])).count == 1)
    }

    @Test func anAudioFileWithVideoFails() throws {
        let probe = Self.audioProbe(titles: Self.audioTitles).replacingOccurrences(
            of: "{\"streams\": [", with: "{\"streams\": [{\"index\": 9, \"codec_type\": \"video\", \"nb_read_frames\": \"1\"},")
        #expect(try failures(Self.audioFile, probe) == ["2026-11-19 08.00.57 Audio 4 - BlackHole 2ch.mov: an audio file with a video track"])
    }
}
