import Foundation

/// The timeline file (D68): an OpenTimelineIO file, plain JSON, in the form
/// DaVinci Resolve itself exports, that loads every file of a recording at
/// its timecode, with a marker per event. Derived whole from the recording
/// manifest every time; never read back.
public enum ResolveTimeline {
    public enum Failure: Error, Equatable, CustomStringConvertible {
        case lengthMissing(file: String)
        case unreadable(what: String, text: String)

        public var description: String {
            switch self {
            case .lengthMissing(let file): "the length of \(file) is not known"
            case .unreadable(let what, let text): "\(what) is not readable: \(text)"
            }
        }
    }

    public static let fileExtension = "otio"
    private static let rate = Double(RecorderValues.framesPerSecond)

    /// The timeline file's name for a recording folder's name. Resolve names
    /// the imported timeline after the file name up to its first dot, so the
    /// dots become `-`, as does every other character outside printable ASCII
    /// and `/` and `:`: "2026-11-20 12.36.09" gives "2026-11-20 12-36-09.otio".
    public static func fileName(forFolder folder: String) -> String {
        timelineName(forFolder: folder) + "." + fileExtension
    }

    static func timelineName(forFolder folder: String) -> String {
        String(folder.unicodeScalars.map { scalar in
            (0x20...0x7E).contains(scalar.value) && !".:/".unicodeScalars.contains(scalar) ? Character(scalar) : "-"
        })
    }

    /// A length in frames, rounded down: Resolve drops the channel mapping
    /// of a clip one frame longer than its file.
    public static func frames(seconds: Double) -> Int {
        Int((seconds * rate + 1e-6).rounded(.down))
    }

    /// The files whose length the media file must tell: those without an end.
    public static func filesWithoutEnd(in manifest: RecordingManifest) -> [String] {
        manifest.files.filter { $0.end == nil }.map(\.name) + manifest.cameraFiles.filter { $0.end == nil }.map(\.name)
            + manifest.audioFiles.filter { $0.end == nil }.map(\.name)
    }

    /// The timeline file's content; `mediaSeconds` holds the media file's duration of each file in `filesWithoutEnd`.
    public static func data(
        manifest: RecordingManifest, folderName: String, mediaSeconds: [String: Double]
    ) throws -> Data {
        let name = timelineName(forFolder: folderName)
        let recordingStart = Int((try Moment(manifest.started).secondsOfDay * rate).rounded())
        let screens = try manifest.files.map { file in
            try Placed(
                name: file.name, source: file.screen, timecode: file.timecode, start: file.start, end: file.end,
                mediaSeconds: mediaSeconds[file.name], channels: nil, recordingStart: recordingStart)
        }.filter { $0.frames > 0 }
        let cameras = try manifest.cameraFiles.map { file in
            try Placed(
                name: file.name, source: file.camera, timecode: file.timecode, start: file.start, end: file.end,
                mediaSeconds: mediaSeconds[file.name], channels: nil, recordingStart: recordingStart)
        }.filter { $0.frames > 0 }
        let audiosAsRecorded = try manifest.audioFiles.map { file in
            try Placed(
                name: file.name, source: file.audioSource, timecode: file.timecode, start: file.start, end: file.end,
                mediaSeconds: mediaSeconds[file.name], channels: file.channels, recordingStart: recordingStart)
        }.filter { $0.frames > 0 }
        let earliest = (screens + cameras + audiosAsRecorded).min { $0.startFrame < $1.startFrame }
        let timelineStart = earliest?.startFrame ?? 0
        let delays = Dictionary(manifest.audioFiles.map { ($0.name, $0.delays) }) { $1 }
        let audios = audiosAsRecorded.flatMap { file in file.stretches(delays[file.name] ?? [], notBefore: timelineStart) }
            .filter { $0.frames > 0 }
        let videoTracks = Self.videoTracks(screens, timelineStart: timelineStart)
            + Self.videoTracks(cameras, timelineStart: timelineStart)
        let audioTracks = Self.audioTracks(audios, timelineStart: timelineStart)
        let markers = try Self.markers(manifest: manifest, name: name, timelineStart: timelineStart)
        let timeline = Node.object([
            ("OTIO_SCHEMA", "Timeline.1"),
            ("name", .string(name)),
            ("metadata", .object([("Resolve_OTIO", .object([("Resolve OTIO Meta Version", "1.0")]))])),
            ("global_start_time", time(earliest?.timecodeFrame ?? 0)),
            ("tracks", .object([
                ("OTIO_SCHEMA", "Stack.1"),
                ("name", ""),
                ("metadata", .object([])),
                ("source_range", .null),
                ("enabled", true),
                ("effects", .array([])),
                ("markers", .array(markers)),
                ("children", .array(videoTracks + audioTracks)),
            ])),
        ])
        return Data((timeline.pretty() + "\n").utf8)
    }

    // MARK: Files as placed on the timeline

    private struct Placed {
        let name: String
        /// Where the file goes on the timeline: its timecode in frames, a day
        /// later for a file after midnight, earlier by its audio delay (D77, D80).
        var startFrame: Int
        /// The file's own timecode in frames, which its clip's source range keeps.
        let timecodeFrame: Int
        /// The file's frames.
        let length: Int
        /// The frames the clip plays, from `trimmed` on.
        var frames: Int
        /// The file's first frames the clip leaves out: where it would start before the timeline or overlap its source's previous clip.
        var trimmed = 0
        let channels: RecordingManifest.AudioFile.Channels?
        let label: String
        let number: Int
        /// The stretch of its file, from 0: a file is split where its audio delay changes (D80).
        var stretch = 0

        init(
            name: String, source: String, timecode: String, start: Double, end: Double?, mediaSeconds: Double?,
            channels: RecordingManifest.AudioFile.Channels?, recordingStart: Int
        ) throws {
            guard let match = timecode.wholeMatch(of: /(\d+):(\d+):(\d+):(\d+)/),
                  let hours = Int(match.1), let minutes = Int(match.2), let seconds = Int(match.3), let frames = Int(match.4)
            else { throw Failure.unreadable(what: "the timecode of \(name)", text: timecode) }
            self.name = name
            let framesPerDay = 24 * 60 * 60 * RecorderValues.framesPerSecond
            timecodeFrame = ((hours * 60 + minutes) * 60 + seconds) * RecorderValues.framesPerSecond + frames
            // Past midnight, the timecode starts over: a timecode half a day or more before where the file
            // starts after the recording's start is on the next day.
            let expected = recordingStart + Int((start * ResolveTimeline.rate).rounded())
            startFrame = timecodeFrame + (timecodeFrame + framesPerDay / 2 <= expected ? framesPerDay : 0)
            guard let seconds = end.map({ $0 - start }) ?? mediaSeconds else { throw Failure.lengthMissing(file: name) }
            length = ResolveTimeline.frames(seconds: seconds)
            self.frames = length
            self.channels = channels
            label = Self.label(ofFileName: name, source: source)
            number = SourceLabel.listPosition(ofFileName: name).number
        }

        /// The file split at each change of its audio delay, each stretch placed by its entry, the one before
        /// the first entry by the first; unchanged without one.
        func stretches(_ delays: [RecordingManifest.AudioFile.Delay], notBefore timelineStart: Int) -> [Placed] {
            guard !delays.isEmpty else { return [self] }
            let starts = [0] + delays.dropFirst().map { ResolveTimeline.frames(seconds: $0.at) }
            return delays.indices.map { index in
                var stretch = self
                stretch.stretch = index
                stretch.trimmed = min(starts[index], frames)
                stretch.frames = min(index + 1 < starts.count ? starts[index + 1] : frames, frames) - stretch.trimmed
                stretch.startFrame += stretch.trimmed
                return stretch.placed(earlierBy: delays[index].delay, notBefore: timelineStart)
            }
        }

        /// The clip placed `delay` seconds earlier, to the nearest frame (negative: later); what would
        /// start before `timelineStart` is trimmed off, so the clip starts there.
        func placed(earlierBy delay: Double, notBefore timelineStart: Int) -> Placed {
            var placed = self
            placed.startFrame -= Int((delay * ResolveTimeline.rate).rounded())
            if placed.startFrame < timelineStart {
                let before = timelineStart - placed.startFrame
                placed.trimmed += before
                placed.frames -= before
                placed.startFrame = timelineStart
            }
            return placed
        }

        /// An audio input's number of mono tracks; the system audio's stereo track is one.
        var channelCount: Int {
            switch channels {
            case .mono(let count): max(1, count)
            case .stereo, nil: 1
            }
        }

        /// The source channels of the file's track `track` that the clip plays, as Resolve has them.
        func channelEntries(_ track: Int) -> [Node] {
            let channels = channels == .stereo ? [0, 1] : [0]
            return channels.map { .object([("Source Channel ID", .int($0)), ("Source Track ID", .int(channels.count == 2 ? 0 : track))]) }
        }

        /// "Screen 1 - DELL P3421W": the file name without its time stamp, its extension and a " (2)" suffix.
        static func label(ofFileName name: String, source: String) -> String {
            let base = name.replacing(/^\d{4}-\d{2}-\d{2}\ \d{2}\.\d{2}\.\d{2}\ /, with: "").replacing(/\.mov$/, with: "")
            // A source's own name can end in " (2)"; only a suffix beyond it marks a file name made unique.
            return base.hasSuffix(RecordingNames.fileNamePart(source)) ? base : base.replacing(/\ \(\d+\)$/, with: "")
        }
    }

    // MARK: Tracks

    private static func videoTracks(_ screens: [Placed], timelineStart: Int) -> [Node] {
        let bySource = Dictionary(grouping: screens, by: \.number)
        let earliestScreenStart = screens.map(\.startFrame).min()
        let first = screens.filter { $0.startFrame == earliestScreenStart }
            .max { ($0.frames, -$0.number) < ($1.frames, -$1.number) }?.number
        let order = (first.map { [$0] } ?? []) + bySource.keys.sorted().filter { $0 != first }
        return order.map { number in
            let files = bySource[number]!.sorted { $0.startFrame < $1.startFrame }
            let children = trackChildren(files, timelineStart: timelineStart) { _ in .object([("Resolve_OTIO", .object([]))]) }
            return track(name: files[0].label, kind: "Video", resolve: [("Locked", false)], children: children)
        }
    }

    private static func audioTracks(_ audios: [Placed], timelineStart: Int) -> [Node] {
        var linkGroups: [String: Int] = [:]
        var tracks: [Node] = []
        let bySource = Dictionary(grouping: audios, by: \.number)
        for number in bySource.keys.sorted() {
            let files = bySource[number]!.sorted { $0.startFrame < $1.startFrame }
            let count = files.map(\.channelCount).max() ?? 1
            let isStereo = files.contains { $0.channels == .stereo }
            for channel in 0..<count {
                let onTrack = files.filter { channel < $0.channelCount }
                let children = trackChildren(onTrack, timelineStart: timelineStart) { file in
                    var resolve: [(String, Node)] = [("Channels", .array(file.channelEntries(channel)))]
                    if file.channelCount > 1 {
                        let clip = "\(file.name)#\(file.stretch)"
                        if linkGroups[clip] == nil { linkGroups[clip] = linkGroups.count + 1 }
                        resolve.append(("Link Group ID", .int(linkGroups[clip]!)))
                    }
                    return .object([("Resolve_OTIO", .object(resolve))])
                }
                let name = count > 1 ? "\(files[0].label), channel \(channel + 1)" : files[0].label
                tracks.append(track(
                    name: name, kind: "Audio",
                    resolve: [("Locked", false), ("Audio Type", .string(isStereo ? "Stereo" : "Mono")), ("SoloOn", false)],
                    children: children))
            }
        }
        return tracks
    }

    private static func track(name: String, kind: String, resolve: [(String, Node)], children: [Node]) -> Node {
        .object([
            ("OTIO_SCHEMA", "Track.1"),
            ("name", .string(name)),
            ("kind", .string(kind)),
            ("enabled", true),
            ("metadata", .object([("Resolve_OTIO", .object(resolve))])),
            ("source_range", .null),
            ("effects", .array([])),
            ("markers", .array([])),
            ("children", .array(children)),
        ])
    }

    /// The clips of a track in time order, a gap before each where the track is empty. A clip that
    /// starts before the previous one ends (a delayed audio file's, D77, or by a frame's rounding)
    /// leaves out its overlapping head, so what it plays stays at its own time.
    private static func trackChildren(_ files: [Placed], timelineStart: Int, metadata: (Placed) -> Node) -> [Node] {
        var children: [Node] = []
        var cursor = timelineStart
        for var file in files {
            if file.startFrame < cursor {
                let overlap = cursor - file.startFrame
                file.trimmed += overlap
                file.frames -= overlap
                file.startFrame = cursor
                guard file.frames > 0 else { continue }
            }
            if file.startFrame > cursor {
                children.append(.object([
                    ("OTIO_SCHEMA", "Gap.1"),
                    ("name", ""),
                    ("metadata", .object([])),
                    ("enabled", true),
                    ("source_range", range(start: 0, frames: file.startFrame - cursor)),
                    ("effects", .array([])),
                    ("markers", .array([])),
                ]))
            }
            children.append(clip(file, metadata: metadata(file)))
            cursor = file.startFrame + file.frames
        }
        return children
    }

    private static func clip(_ file: Placed, metadata: Node) -> Node {
        let available = range(start: file.timecodeFrame, frames: file.length)
        return .object([
            ("OTIO_SCHEMA", "Clip.2"),
            ("name", .string(file.name)),
            ("enabled", true),
            ("metadata", metadata),
            ("source_range", range(start: file.timecodeFrame + file.trimmed, frames: file.frames)),
            ("effects", .array([])),
            ("markers", .array([])),
            ("active_media_reference_key", "DEFAULT_MEDIA"),
            ("media_references", .object([("DEFAULT_MEDIA", .object([
                ("OTIO_SCHEMA", "ExternalReference.1"),
                ("name", .string(file.name)),
                ("metadata", .object([])),
                ("available_range", available),
                ("available_image_bounds", .null),
                ("target_url", .string(file.name)),
            ]))])),
        ])
    }

    // MARK: Markers

    private static func markers(manifest: RecordingManifest, name: String, timelineStart: Int) throws -> [Node] {
        let started = try Moment(manifest.started)
        let ended = try manifest.ended.map { try Moment($0) }
        let eventsByFrame = Dictionary(grouping: manifest.events) { event in
            max(0, Int(((started.secondsOfDay * rate) + event.at * rate).rounded()) - timelineStart)
        }
        let eventText = { (event: RecordingEvent) in
            EventLine.text(event, started: started.date, timeZone: started.timeZone)
        }

        var note = [recordingLine(started: started, ended: ended)]
        var title = "Recording \(name)"
        if let largest = (manifest.files.map(\.frameSize) + manifest.cameraFiles.map(\.frameSize)).max(by: { area($0) < area($1) }) {
            let size = "\(largest[0]) x \(largest[1])"
            title += ": set resolution \(size)"
            note.append("Set the timeline resolution to \(size) (the largest video file): Timeline > Timeline Settings.")
        }
        note.append(manifest.cameraFiles.isEmpty
            ? "Tracks: one per screen, one per audio channel; the channels of one input are a linked group."
            : "Tracks: one per screen, then one per camera, one per audio channel; the channels of one input are a linked group.")
        note.append("Markers: blue = screen change, green = audio and other changes.")
        note.append(manifest.problems.isEmpty ? "Problems: none." : "Problems:")
        note += manifest.problems.map { EventLine.problemText($0, started: started.date, timeZone: started.timeZone) }
        note += (eventsByFrame[0] ?? []).map(eventText)

        let eventMarkers = eventsByFrame.filter { $0.key > 0 }.sorted { $0.key < $1.key }.map { frame, events in
            let isScreen = events.contains { $0.event.rawValue.hasPrefix("screen") || $0.event.rawValue.hasPrefix("main screen") }
            return marker(
                name: events.map(\.event.rawValue).joined(separator: "; "), color: isScreen ? "BLUE" : "GREEN",
                note: events.map(eventText), frame: frame)
        }
        return [marker(name: title, color: "RED", note: note, frame: 0)] + eventMarkers
    }

    private static func area(_ size: [Int]) -> Int { size.reduce(1, *) }

    /// "Multi Screen Recorder, recording 2026-11-20 12:36:09 to 12:38:18 (2m09s)."
    private static func recordingLine(started: Moment, ended: Moment?) -> String {
        let begin = "Multi Screen Recorder, recording \(started.dateText) \(started.clockText)"
        guard let ended else { return begin + ", not finished." }
        let seconds = ended.date.timeIntervalSince(started.date)
        return begin + " to \(ended.clockText) (\(RecordingSummary.elapsed(seconds: seconds)))."
    }

    private static func marker(name: String, color: String, note: [String], frame: Int) -> Node {
        .object([
            ("OTIO_SCHEMA", "Marker.2"),
            ("name", .string(name)),
            ("color", .string(color)),
            ("metadata", .object([("Resolve_OTIO", .object([
                ("Keywords", .array([])),
                ("Note", .string(note.joined(separator: "\n"))),
            ]))])),
            ("marked_range", range(start: frame, frames: 1)),
        ])
    }

    /// A time stamp of the manifest, "2026-11-20T12:36:09.076+01:00", in its own offset.
    private struct Moment {
        let date: Date
        let timeZone: TimeZone
        let dateText: String
        let clockText: String
        let secondsOfDay: Double

        init(_ text: String) throws {
            guard let match = text.wholeMatch(of: /(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})(?:\.(\d+))?([+-])(\d{2}):(\d{2})/),
                  let year = Int(match.1), let month = Int(match.2), let day = Int(match.3), let hour = Int(match.4),
                  let minute = Int(match.5), let second = Int(match.6), let offsetHours = Int(match.9),
                  let offsetMinutes = Int(match.10),
                  let timeZone = TimeZone(secondsFromGMT: (match.8 == "-" ? -1 : 1) * (offsetHours * 3600 + offsetMinutes * 60))
            else { throw Failure.unreadable(what: "the time stamp", text: text) }
            let fraction = match.7.flatMap { Double("0." + $0) } ?? 0
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = timeZone
            let parts = DateComponents(
                year: year, month: month, day: day, hour: hour, minute: minute, second: second,
                nanosecond: Int((fraction * 1_000_000_000).rounded()))
            guard let date = calendar.date(from: parts) else { throw Failure.unreadable(what: "the time stamp", text: text) }
            self.date = date
            self.timeZone = timeZone
            dateText = String(format: "%04d-%02d-%02d", year, month, day)
            clockText = String(format: "%02d:%02d:%02d", hour, minute, second)
            secondsOfDay = Double(hour * 3600 + minute * 60 + second) + fraction
        }
    }

    // MARK: JSON

    private static func time(_ frames: Int) -> Node {
        .object([("OTIO_SCHEMA", "RationalTime.1"), ("rate", .double(rate)), ("value", .double(Double(frames)))])
    }

    private static func range(start: Int, frames: Int) -> Node {
        .object([("OTIO_SCHEMA", "TimeRange.1"), ("start_time", time(start)), ("duration", time(frames))])
    }

    /// JSON in the order it is built, written as Resolve writes numbers: `30.0`, not `30`.
    private indirect enum Node: ExpressibleByStringLiteral, ExpressibleByBooleanLiteral {
        case null
        case bool(Bool)
        case int(Int)
        case double(Double)
        case string(String)
        case array([Node])
        case object([(String, Node)])

        init(stringLiteral value: String) { self = .string(value) }
        init(booleanLiteral value: Bool) { self = .bool(value) }

        func pretty(_ indent: String = "") -> String {
            let inner = indent + "  "
            switch self {
            case .null: return "null"
            case .bool(let value): return value ? "true" : "false"
            case .int(let value): return String(value)
            case .double(let value): return String(format: "%.1f", value)
            case .string(let value): return Self.quoted(value)
            case .array(let items):
                guard !items.isEmpty else { return "[]" }
                return "[\n" + items.map { inner + $0.pretty(inner) }.joined(separator: ",\n") + "\n\(indent)]"
            case .object(let members):
                guard !members.isEmpty else { return "{}" }
                return "{\n" + members.map { "\(inner)\(Self.quoted($0.0)): \($0.1.pretty(inner))" }.joined(separator: ",\n")
                    + "\n\(indent)}"
            }
        }

        private static func quoted(_ text: String) -> String {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .withoutEscapingSlashes
            // A String always encodes.
            return String(decoding: (try? encoder.encode(text)) ?? Data(), as: UTF8.self)
        }
    }
}
