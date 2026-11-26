/// Whether the status window's audio rows are final, read from the recording's `recording.log`: each audio
/// source whose newest file is being written shows its clock drift (its latest `Audio N - …: clock drift`
/// line is not `not measured yet`) and, for an audio input (N ≥ 1), its sync (one of `AudioDelays`' lines
/// that ends "not synced yet" for a file of that source; a source's newer file keeps it, and a start-over
/// clears it for all but the new anchor). A source in no audio shows "measuring" for ever, so it is not
/// waited for; its event names only the device, so two devices of the same name share it. Everything is keyed by the source's number N,
/// as device names repeat and a file name changes the name's `/` and `:`.
public enum AudioRowsFinal {
    private struct Source {
        var newestFile: String?
        var isWritten = false
        var showsClockDrift = false
        var showsSync = false
    }

    private static let syncShown = [
        "joins the guide track", "carries over ", "in the guide track with the carried-over audio delay",
        "not in the guide track", "no clear sound to sync", "audio delay set by its first counted window",
    ]

    /// The newest files of the audio sources whose rows are not final yet, by number.
    public static func filesNotFinal(log: String) -> [String] {
        var sources: [Int: Source] = [:]
        var numbersByName: [String: Set<Int>] = ["System audio": [0]]
        var silent: Set<Int> = []
        for line in log.split(separator: "\n").map(String.init) {
            if let event = line.firstMatch(of: #/^\S+ \+\S+ no audio (started|stopped): (.+)$/#) {
                let numbers = numbersByName[String(event.2)] ?? []
                if event.1 == "started" { silent.formUnion(numbers) } else { silent.subtract(numbers) }
                continue
            }
            guard let range = line.firstRange(of: " detail recorder: ") else { continue }
            let detail = line[range.upperBound...]
            if let start = detail.firstMatch(of: #/^audio: startInput\(uid: ".*", number: (\d+), name: "(.*)"\)$/#) {
                numbersByName[String(start.2), default: []].insert(Int(start.1)!)
            } else if let started = detail.firstMatch(of: #/^file started: (.*? Audio (\d+) - .*\.mov)$/#) {
                sources[Int(started.2)!, default: Source()].newestFile = String(started.1)
                sources[Int(started.2)!]!.isWritten = true
            } else if let ended = detail.firstMatch(of: #/^file ended: (.*? Audio (\d+) - .*?\.mov), /#) {
                if sources[Int(ended.2)!]?.newestFile == String(ended.1) { sources[Int(ended.2)!]!.isWritten = false }
            } else if let drift = detail.firstMatch(of: #/^Audio (\d+) - .*: clock drift (?!corrected)(.*)$/#) {
                sources[Int(drift.1)!, default: Source()].showsClockDrift = !drift.2.hasPrefix("not measured yet")
            } else if let startOver = detail.firstMatch(
                of: #/^reference .* → (.*? Audio (\d+) - .*?\.mov): (?:it has no audio delay|moved on a reference miss), so it is the new anchor and every input starts over$/#) {
                for number in sources.keys { sources[number]!.showsSync = false }
                sources[Int(startOver.2)!, default: Source()].showsSync = true
            } else if !detail.hasPrefix("reference "), let delay = detail.firstMatch(of: #/^.*? Audio (\d+) - .*?\.mov: (.*)$/#),
                      syncShown.contains(where: { delay.2.hasPrefix($0) }) {
                sources[Int(delay.1)!, default: Source()].showsSync = true
            }
        }
        return sources.sorted { $0.key < $1.key }.compactMap { number, source in
            guard source.isWritten, !silent.contains(number) else { return nil }
            return source.showsClockDrift && (number == 0 || source.showsSync) ? nil : source.newestFile
        }
    }
}
