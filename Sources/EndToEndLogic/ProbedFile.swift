import Foundation

/// What `ffprobe -count_frames -show_streams -of json` says about one file.
public struct ProbedFile: Sendable, Equatable {
    public struct Stream: Sendable, Equatable {
        public var index: Int
        public var codecType: String
        public var codecName: String?
        public var width: Int?
        public var height: Int?
        public var channels: Int?
        public var sampleRate: Int?
        public var duration: Double?
        /// The frames decoded (`nb_read_frames`).
        public var framesRead: Int?
        public var title: String?
        public var timecode: String?
    }

    public var streams: [Stream]

    public init(ffprobeJSON data: Data) throws {
        guard let streams = try JSONValue(json: data)["streams"]?.array else {
            throw ProbeError("ffprobe's output has no streams")
        }
        self.streams = try streams.map { stream in
            guard let index = stream["index"]?.integer, let type = stream["codec_type"]?.string else {
                throw ProbeError("a stream without index or codec_type: \(stream)")
            }
            func number(_ key: String) -> Double? { stream[key]?.string.flatMap(Double.init) ?? stream[key]?.number }
            return Stream(
                index: index, codecType: type, codecName: stream["codec_name"]?.string,
                width: stream["width"]?.integer, height: stream["height"]?.integer, channels: stream["channels"]?.integer,
                sampleRate: number("sample_rate").map { Int($0) }, duration: number("duration"),
                framesRead: number("nb_read_frames").map { Int($0) },
                title: stream["tags"]?["title"]?.string, timecode: stream["tags"]?["timecode"]?.string)
        }
    }

    public var video: [Stream] { streams.filter { $0.codecType == "video" } }
    public var audio: [Stream] { streams.filter { $0.codecType == "audio" } }
    /// The timecode track (a data stream carrying the timecode).
    public var timecodeTrack: [Stream] { streams.filter { $0.codecType == "data" && $0.timecode != nil } }
}

public struct ProbeError: Error, CustomStringConvertible {
    public let description: String
    public init(_ description: String) { self.description = description }
}

/// The assertions on one listed file through what `ffprobe` read from it.
public enum FileCheck {
    public static let framesPerSecond = Double(TimecodeValue.framesPerSecond)
    /// A file never finalized is readable up to its last complete fragment.
    public static let fragmentSeconds = 2.0
    /// How far an audio file's length may be from its end minus its start:
    /// one AAC packet (1024 samples at 48 kHz) and a millisecond.
    public static let audioLengthTolerance = 0.0224
    static let aacPacketSamples = 1024

    /// Failures, one line each.
    public static func failures(
        _ file: ListedFile, probed: ProbedFile, ending: ManifestExpectation.Ending, slack: Double
    ) -> [String] {
        var failures: [String] = []
        func fail(_ text: String) { failures.append("\(file.name): \(text)") }
        let timecodes = probed.timecodeTrack
        if timecodes.count != 1 || timecodes.first?.timecode != file.timecode {
            fail("timecode track \(timecodes.map { $0.timecode ?? "-" }), expected one with \(file.timecode)")
        }
        switch file.source {
        case .screen(_, _, let size, let guides):
            let videos = probed.video
            guard videos.count == 1, let video = videos.first else {
                fail("\(videos.count) video tracks, expected 1")
                return failures
            }
            if video.codecName != "hevc" { fail("video codec \(video.codecName ?? "-"), expected hevc") }
            if [video.width ?? 0, video.height ?? 0] != size { fail("video \(video.width ?? 0)×\(video.height ?? 0), expected \(size[0])×\(size[1])") }
            if video.title != file.label { fail("video track named \(video.title ?? "-"), expected \(file.label)") }
            if probed.audio.map(\.title) != guides { fail("audio tracks \(probed.audio.map { $0.title ?? "-" }), expected the guide tracks \(guides)") }
            let frames = video.framesRead ?? 0
            switch ending {
            case .finalized:
                let expected = Int((((file.end ?? file.start) - file.start) * framesPerSecond).rounded())
                if abs(frames - expected) > 1 { fail("\(frames) frames, expected \(expected) for its length (30 per second)") }
            case .killed(let at):
                let least = Int(((at - file.start - fragmentSeconds - slack) * framesPerSecond).rounded(.down))
                if frames < least { fail("\(frames) frames readable after the kill, expected at least \(least)") }
            }
        case .audioInput(_, _, let channels):
            let audio = probed.audio
            let titles = (1...channels).map { "\(file.label), channel \($0)" }
            if audio.map(\.title) != titles { fail("audio tracks \(audio.map { $0.title ?? "-" }), expected \(titles)") }
            if audio.contains(where: { $0.channels != 1 }) { fail("an audio track is not mono") }
            failures += lengthFailures(file, audio, ending: ending, slack: slack)
        case .systemAudio:
            let audio = probed.audio
            if audio.map(\.title) != [file.label] || audio.first?.channels != 2 {
                fail("audio tracks \(audio.map { "\($0.title ?? "-") (\($0.channels ?? 0))" }), expected one stereo \(file.label)")
            }
            failures += lengthFailures(file, audio, ending: ending, slack: slack)
        }
        if file.source.isAudio, !probed.video.isEmpty { fail("an audio file with a video track") }
        return failures
    }

    private static func lengthFailures(
        _ file: ListedFile, _ audio: [ProbedFile.Stream], ending: ManifestExpectation.Ending, slack: Double
    ) -> [String] {
        audio.compactMap { track in
            switch ending {
            case .finalized:
                let length = track.duration ?? 0
                let expected = (file.end ?? file.start) - file.start
                return abs(length - expected) > audioLengthTolerance
                    ? "\(file.name): \(track.title ?? "a track") lasts \(length) s, expected \(expected) s" : nil
            case .killed(let at):
                // A file never finalized has no length of its own: its decoded AAC packets tell.
                let length = Double((track.framesRead ?? 0) * aacPacketSamples) / Double(track.sampleRate ?? 48_000)
                let least = at - file.start - fragmentSeconds - slack
                return length < least
                    ? "\(file.name): \(track.title ?? "a track") readable for \(length) s after the kill, expected at least \(least) s" : nil
            }
        }
    }
}
