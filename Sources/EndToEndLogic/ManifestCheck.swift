import Foundation

/// One file the recording manifest lists, as the end-to-end tests read it.
public struct ListedFile: Sendable, Equatable {
    public enum Source: Sendable, Equatable {
        case screen(uuid: String, name: String, frameSize: [Int], guideTracks: [String])
        case audioInput(uid: String, name: String, channels: Int)
        case systemAudio

        public var isAudio: Bool { if case .screen = self { false } else { true } }
    }

    /// The name events give its source: the screen's or the audio source's.
    public var sourceName: String {
        switch source {
        case .screen(_, let name, _, _), .audioInput(_, let name, _): name
        case .systemAudio: ManifestCheck.systemAudioSource
        }
    }

    public var name: String
    public var source: Source
    /// The label the file name carries after its stamp (`Screen 3 - MSR Test`).
    public var label: String
    public var start: Double
    public var end: Double?
    public var timecode: String
    public var state: String
}

/// The assertions on `recording.json`: each failure is one line.
public struct ManifestCheck {
    static let topLevelKeys: Set = ["app", "state", "started", "ended", "result", "cpu", "settings", "files", "events", "problems"]
    static let screenFileKeys: Set = [
        "name", "screen", "screenUUID", "frameSize", "start", "end", "timecode", "state", "guideTracks",
        "framesRepeatedForLateness",
    ]
    static let audioInputFileKeys: Set = [
        "name", "audioSource", "audioSourceUID", "channels", "start", "end", "timecode", "state", "clockDriftPpm",
        "clockDriftCorrection",
    ]
    static let systemAudioFileKeys = audioInputFileKeys.subtracting(["audioSourceUID"])
    static let systemAudioSource = "System audio"
    static let systemAudioLabel = "Audio 0 - System"
    /// The events that end a file by a failure (recorder.md, "Output on disk").
    static let failureEvents: Set = [
        "screen stream failed", "screen file writer failed", "disk full", "screen file writer fell behind",
        "screen shows another screen's picture", "audio input failed", "system audio failed",
        "audio file writer failed", "audio file writer fell behind",
    ]

    public let expectation: ManifestExpectation
    public private(set) var failures: [String] = []
    /// The files listed, for the checks of the files themselves.
    public private(set) var files: [ListedFile] = []
    /// The recorder's notices that passed their own check, by their index
    /// among the virtual screens' events: the anchors of the starts after them.
    public private(set) var notices: [Int: Double] = [:]
    private var eventTimes: [Int: Double] = [:]
    /// The recording's start, in seconds of the local day.
    public private(set) var started: Double?
    /// How long the recording ran from `started` to `ended`, when finalized.
    public private(set) var ranFor: Double?

    /// Checks the manifest against the expectation and the names of the
    /// files in the recording folder, `recording.json` included.
    public init(manifest: JSONValue, folder: [String], expectation: ManifestExpectation) {
        self.expectation = expectation
        checkTopLevel(manifest)
        checkFiles(manifest["files"], folder: folder)
        checkVirtualScreens(manifest["events"])
        checkPlayedAudioInputs(manifest["events"])
        checkFailureEvents(manifest["events"])
        checkSpan(manifest["events"])
    }

    private mutating func fail(_ text: String) { failures.append(text) }

    private mutating func checkTopLevel(_ manifest: JSONValue) {
        guard let keys = manifest.keys else {
            fail("recording.json does not hold an object")
            return
        }
        if keys != Self.topLevelKeys {
            fail("recording.json has the keys \(keys.sorted()), expected \(Self.topLevelKeys.sorted())")
        }
        expect(manifest["app"], .string(expectation.app), "app")
        expect(manifest["settings"], expectation.settings.json, "settings")
        started = manifest["started"]?.string.flatMap(TimeOfDay.seconds(ofTimestamp:))
        if started == nil { fail("started is \(manifest["started"] ?? .null), expected a local time with milliseconds and offset") }
        switch expectation.ending {
        case .finalized:
            expect(manifest["state"], .string("finalized"), "state")
            expect(manifest["result"], .string("ok"), "result")
            if let ended = manifest["ended"]?.string.flatMap(TimeOfDay.seconds(ofTimestamp:)) {
                if let started {
                    let ran = TimeOfDay.difference(ended, started)
                    ranFor = ran
                    if !expectation.endsAtTheStop(ran) {
                        fail("the recording ran \(Self.seconds(ran)) s from started to ended, expected \(expectation.stopBounds), from its stop to the finalize allowance after it")
                    }
                }
            } else {
                fail("ended is \(manifest["ended"] ?? .null), expected a local time with milliseconds and offset")
            }
            let cpu = manifest["cpu"]
            if cpu?.keys != ["averagePercent", "peakPercent"] || cpu?["averagePercent"]?.number == nil
                || cpu?["peakPercent"]?.number == nil {
                fail("cpu is \(cpu ?? .null), expected averagePercent and peakPercent")
            }
        case .killed:
            expect(manifest["state"], .string("recording"), "state after a kill")
            expect(manifest["ended"], .null, "ended after a kill")
            expect(manifest["result"], .null, "result after a kill")
            expect(manifest["cpu"], .null, "cpu after a kill")
        }
        if manifest["events"]?.array == nil { fail("events is not a list") }
        if let problems = manifest["problems"]?.array {
            for problem in problems where problem.keys != ["at", "problem", "error"] {
                fail("a problem has the keys \(problem.keys?.sorted() ?? []), expected at, problem and error")
            }
        } else {
            fail("problems is not a list")
        }
    }

    private mutating func expect(_ value: JSONValue?, _ expected: JSONValue, _ what: String) {
        if value != expected { fail("\(what) is \(value ?? .null), expected \(expected)") }
    }

    // MARK: Files

    private mutating func checkFiles(_ list: JSONValue?, folder: [String]) {
        guard let entries = list?.array else {
            fail("files is not a list")
            return
        }
        files = entries.compactMap { listedFile($0) }
        let names = files.map(\.name)
        if Set(names).count != names.count { fail("files lists a name twice: \(names)") }
        let movies = Set(folder.filter { $0 != "recording.json" })
        if !folder.contains("recording.json") { fail("the recording folder has no recording.json") }
        for missing in movies.subtracting(names).sorted() { fail("\(missing) is in the recording folder but not in files") }
        for extra in Set(names).subtracting(movies).sorted() { fail("\(extra) is in files but not in the recording folder") }
        for file in files where !file.name.hasSuffix(".mov") { fail("\(file.name) is not a .mov") }
        if files.map(\.start) != files.map(\.start).sorted() { fail("files are not in the order of their start") }
        checkNumbers()
    }

    private mutating func listedFile(_ entry: JSONValue) -> ListedFile? {
        let name = entry["name"]?.string ?? "?"
        guard let start = entry["start"]?.number, start >= 0 else {
            fail("\(name): start is \(entry["start"] ?? .null), expected seconds")
            return nil
        }
        guard let timecode = entry["timecode"]?.string else {
            fail("\(name): timecode is \(entry["timecode"] ?? .null)")
            return nil
        }
        guard let source = source(of: entry, name: name) else { return nil }
        let end = entry["end"]?.number
        let state = entry["state"]?.string ?? "?"
        switch expectation.ending {
        case .finalized:
            if state != "finalized" { fail("\(name): state is \(state), expected finalized") }
            if end == nil || end! < start { fail("\(name): end is \(entry["end"] ?? .null), expected seconds after its start") }
        case .killed:
            if state != "recording" { fail("\(name): state after a kill is \(state), expected recording") }
            if entry["end"] != .null { fail("\(name): end after a kill is \(entry["end"] ?? .null), expected null") }
        }
        guard let (stamp, rest) = TimeOfDay.fileNameStamp(name) else {
            fail("\(name): the name does not start with its date and time")
            return nil
        }
        let label = String(rest.dropLast(".mov".count)).replacing(#/ \(\d+\)$/#, with: "")
        if let started, abs(TimeOfDay.difference(stamp, (started + start).rounded(.down))) > 1 {
            fail("\(name): the name's time is not the file's start, \(start) s after the recording's start")
        }
        if let started {
            let expected = TimecodeValue.possible(recordingStarted: started, fileStart: start)
            if !expected.contains(where: { TimecodeValue(timecode) == $0 }) {
                let wanted = expected.map(\.description).joined(separator: " or ")
                fail("\(name): timecode is \(timecode), expected \(wanted) from started and start")
            }
        }
        return ListedFile(name: name, source: source, label: label, start: start, end: end, timecode: timecode, state: state)
    }

    private mutating func source(of entry: JSONValue, name: String) -> ListedFile.Source? {
        let keys = entry.keys ?? []
        if entry["audioSource"] == nil {
            if keys != Self.screenFileKeys { fail("\(name): the keys are \(keys.sorted()), expected \(Self.screenFileKeys.sorted())") }
            guard let uuid = entry["screenUUID"]?.string, let screen = entry["screen"]?.string,
                  let size = entry["frameSize"]?.array?.compactMap(\.integer), size.count == 2,
                  size.allSatisfy({ $0 > 0 && $0 % 2 == 0 }),
                  let guides = entry["guideTracks"]?.array?.compactMap(\.string),
                  let repeated = entry["framesRepeatedForLateness"]?.integer, repeated >= 0
            else {
                fail("\(name): a screen file entry without screenUUID, screen, an even frameSize, guideTracks or framesRepeatedForLateness")
                return nil
            }
            if guides != expectation.settings.guideTracks {
                fail("\(name): guideTracks are \(guides), expected \(expectation.settings.guideTracks)")
            }
            return .screen(uuid: uuid, name: screen, frameSize: size, guideTracks: guides)
        }
        let finalized = expectation.ending == .finalized
        if finalized ? entry["clockDriftCorrection"]?.number == nil : entry["clockDriftCorrection"] != .null {
            fail("\(name): clockDriftCorrection is \(entry["clockDriftCorrection"] ?? .null)")
        }
        if let ppm = entry["clockDriftPpm"], ppm != .null && (!finalized || ppm.number == nil) {
            fail("\(name): clockDriftPpm is \(ppm)")
        }
        if entry["audioSource"] == .string(Self.systemAudioSource) {
            if keys != Self.systemAudioFileKeys { fail("\(name): the keys are \(keys.sorted()), expected \(Self.systemAudioFileKeys.sorted())") }
            if entry["channels"] != .string("stereo") { fail("\(name): channels is \(entry["channels"] ?? .null), expected stereo") }
            return .systemAudio
        }
        if keys != Self.audioInputFileKeys { fail("\(name): the keys are \(keys.sorted()), expected \(Self.audioInputFileKeys.sorted())") }
        guard let uid = entry["audioSourceUID"]?.string, let source = entry["audioSource"]?.string,
              let channels = entry["channels"]?.integer, channels > 0
        else {
            fail("\(name): an audio file entry without audioSourceUID, audioSource or a channel count")
            return nil
        }
        return .audioInput(uid: uid, name: source, channels: channels)
    }

    /// Every label is `<kind> <n> - <name>`; a source keeps its number,
    /// two sources never share one, and the system audio is always 0.
    private mutating func checkNumbers() {
        var screenNumbers: [String: Int] = [:]
        var audioNumbers: [String: Int] = [:]
        for file in files {
            switch file.source {
            case .systemAudio:
                if file.label != Self.systemAudioLabel { fail("\(file.name): the label is not \(Self.systemAudioLabel)") }
            case .screen(let uuid, let name, _, _):
                guard let number = number(in: file, kind: "Screen", name: name) else { continue }
                if screenNumbers[uuid, default: number] != number { fail("\(file.name): screen \(uuid) changed its number") }
                screenNumbers[uuid] = number
            case .audioInput(let uid, let name, _):
                guard let number = number(in: file, kind: "Audio", name: name) else { continue }
                if audioNumbers[uid, default: number] != number { fail("\(file.name): audio input \(uid) changed its number") }
                audioNumbers[uid] = number
            }
        }
        if Set(screenNumbers.values).count != screenNumbers.count { fail("two screens share a number: \(screenNumbers)") }
        if Set(audioNumbers.values).count != audioNumbers.count { fail("two audio inputs share a number: \(audioNumbers)") }
    }

    private mutating func number(in file: ListedFile, kind: String, name: String) -> Int? {
        let namePart = name.replacing(/[\/:]/, with: "-")
        guard let match = file.label.wholeMatch(of: /(\w+) (\d+) - (.*)/), match.1 == kind, String(match.3) == namePart,
              let number = Int(match.2), number > 0
        else {
            fail("\(file.name): the label is not \"\(kind) <n> - \(namePart)\"")
            return nil
        }
        return number
    }

    // MARK: Virtual screens and played audio inputs

    private mutating func checkVirtualScreens(_ events: JSONValue?) {
        let virtualUUIDs = Set(expectation.virtualScreenFiles.map(\.screenUUID))
        let actual = files.filter { if case .screen(let uuid, _, _, _) = $0.source { virtualUUIDs.contains(uuid) } else { false } }
        let expected = expectation.virtualScreenFiles
        if actual.count != expected.count {
            fail("the virtual screens have \(actual.count) screen files, expected \(expected.count): \(actual.map(\.name))")
        }
        let virtualEvents = (events?.array ?? []).filter {
            $0["screen"]?.string?.hasPrefix(expectation.virtualScreenNamePrefix) == true
        }
        let kinds = virtualEvents.map { $0["event"]?.string ?? "?" }
        let expectedKinds = expectation.virtualScreenEvents.map(\.event)
        if kinds == expectedKinds {
            let noticeIndices = Set(expected.compactMap(\.noticedBy))
            for (index, (event, wanted)) in zip(virtualEvents, expectation.virtualScreenEvents).enumerated()
            where noticeIndices.contains(index) {
                guard let at = event["at"]?.number else { continue }
                eventTimes[index] = at
                if outside(at, wanted.expected) == nil { notices[index] = at }
            }
        }
        var numbers: [Int] = []
        for (file, wanted) in zip(actual, expected) {
            guard case .screen(let uuid, let name, let size, _) = file.source else { continue }
            if uuid != wanted.screenUUID { fail("\(file.name): screen \(uuid), expected \(wanted.screenUUID)") }
            if !name.hasPrefix(expectation.virtualScreenNamePrefix) {
                fail("\(file.name): screen \(name), expected a name starting \(expectation.virtualScreenNamePrefix)")
            }
            if size != wanted.frameSize { fail("\(file.name): frameSize \(size), expected \(wanted.frameSize)") }
            var startedBy = wanted.startedBy
            if let index = wanted.noticedBy {
                let name = expectation.virtualScreenEvents[index].event
                startedBy.notice = notices[index]
                if startedBy.notice == nil {
                    let reason = eventTimes[index].map { String(format: "%@ at %.2f s, is outside its window", name, $0) } ?? "\(name), is missing"
                    fail("\(file.name): its start is not checked: the recorder's notice, \(reason)")
                }
            }
            if wanted.noticedBy == nil || startedBy.notice != nil,
               let wrong = outside(file.start, ExpectedTime(change: startedBy, kind: .settled)) {
                fail("\(file.name): starts at \(wrong)")
            }
            if expectation.ending == .finalized, let fileEnd = file.end {
                if let endedBy = wanted.endedBy {
                    if let wrong = outside(fileEnd, endedBy) { fail("\(file.name): ends at \(wrong)") }
                } else if abs(fileEnd - expectation.stoppedAt) > expectation.timeTolerance {
                    fail("\(file.name): ends at \(fileEnd), expected \(expectation.stoppedAt)")
                }
            }
            if let match = file.label.wholeMatch(of: /Screen (\d+) - .*/), let number = Int(match.1) { numbers.append(number) }
        }
        if let first = numbers.first {
            if first != expectation.ownScreenCount + 1 {
                fail("the first virtual screen is screen \(first), expected \(expectation.ownScreenCount + 1), after the Mac's own")
            }
        }
        guard kinds == expectedKinds else {
            fail("the virtual screens' events are \(kinds), expected \(expectedKinds)")
            return
        }
        for (event, wanted) in zip(virtualEvents, expectation.virtualScreenEvents) {
            guard let at = event["at"]?.number else {
                fail("event \(event) has no time")
                continue
            }
            if let wrong = outside(at, wanted.expected) { fail("\(wanted.event) at \(wrong)") }
        }
    }

    /// The failure's text when `time` is outside the change's window, else nil.
    private func outside(_ time: Double, _ expected: ExpectedTime) -> String? {
        let window = expected.change.window(expected.kind, settleTime: expectation.settleTime, tolerance: expectation.timeTolerance)
        guard !window.contains(time) else { return nil }
        let follows = switch (expected.kind, expected.change.anchor) {
        case (.settled, let anchor?): String(format: "the settle time after %@ at %.2f s", anchor.source.description, anchor.time)
        default: expected.kind.description
        }
        return String(format: "%.2f s, expected %.2f s to %.2f s, ", time, window.lowerBound, window.upperBound) + follows
    }

    private mutating func checkPlayedAudioInputs(_ events: JSONValue?) {
        for input in expectation.playedAudioInputs {
            let listed = files.filter { if case .audioInput(let uid, _, _) = $0.source { uid == input.uid } else { false } }
            guard listed.count == 1, case .audioInput(_, let name, let channels) = listed[0].source else {
                fail("\(input.name) has \(listed.count) audio files, expected 1")
                continue
            }
            if name != input.name { fail("\(listed[0].name): audioSource \(name), expected \(input.name)") }
            if channels != input.channels { fail("\(listed[0].name): channels \(channels), expected \(input.channels)") }
            let inputEvents = (events?.array ?? []).filter { $0["audioSource"] == .string(input.name) }
            if !inputEvents.isEmpty { fail("\(input.name) has events, expected none: \(inputEvents)") }
        }
        let systemAudioFiles = files.filter { $0.source == .systemAudio }
        let expectedCount = expectation.settings.systemAudio ? 1 : 0
        if systemAudioFiles.count != expectedCount {
            fail("the system audio has \(systemAudioFiles.count) audio files, expected \(expectedCount)")
        }
    }

    // MARK: From the start to the stop

    /// A file of a source no event names runs the whole recording: it starts
    /// within the settle time of the start and, when finalized, ends at the
    /// stop. The played audio inputs are such sources.
    private mutating func checkSpan(_ events: JSONValue?) {
        let named = Set((events?.array ?? []).flatMap { [$0["screen"]?.string, $0["audioSource"]?.string].compactMap(\.self) })
        let latestStart = expectation.settleTime + expectation.timeTolerance
        for file in files where !named.contains(file.sourceName) {
            if file.start > latestStart {
                fail("\(file.name): starts at \(Self.seconds(file.start)) s, expected by \(Self.seconds(latestStart)) s, the settle time and the tolerance after the start")
            }
            if expectation.ending == .finalized, let end = file.end, !expectation.endsAtTheStop(end) {
                fail("\(file.name): ends at \(Self.seconds(end)) s, expected \(expectation.stopBounds), the stop")
            }
        }
    }

    /// Seconds to a tenth, for failure lines.
    static func seconds(_ value: Double) -> String { String(format: "%.1f", value) }

    /// No event ends a file by a failure: they are what `result` counts.
    private mutating func checkFailureEvents(_ events: JSONValue?) {
        for event in events?.array ?? [] {
            if let kind = event["event"]?.string, Self.failureEvents.contains(kind) {
                fail("a failure event: \(event)")
            }
        }
    }
}
