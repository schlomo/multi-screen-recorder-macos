/// Which audio input files of a recording are still being measured against the others, read from its
/// `recording.log`: a file is out of measuring once `AudioDelays` logged (a `recorder` detail line) that
/// it joins the guide track (the anchor's own file at its start) or has no clear sound to sync, or while
/// its input is in no audio (a `no audio started` event naming it, with no `no audio stopped` after it),
/// as the status window shows no sync for a silent input. The system audio, `Audio 0 - System`, is not measured.
public enum AudioMeasuring {
    /// The audio input files started and still measuring, in the order they started.
    public static func filesMeasuring(log: String) -> [String] {
        var details: [String] = []
        var silentInputs: Set<String> = []
        for line in log.split(separator: "\n") {
            if let detail = line.firstRange(of: " detail recorder: ") {
                details.append(String(line[detail.upperBound...]))
            } else if let started = line.firstRange(of: " no audio started: ") {
                silentInputs.insert(String(line[started.upperBound...]))
            } else if let stopped = line.firstRange(of: " no audio stopped: ") {
                silentInputs.remove(String(line[stopped.upperBound...]))
            }
        }
        let inputFiles = details.compactMap { detail -> (file: String, input: String)? in
            guard detail.hasPrefix("file started: ") else { return nil }
            let name = String(detail.dropFirst("file started: ".count))
            guard let match = name.firstMatch(of: #/ Audio [1-9][0-9]* - (.+)\.mov$/#) else { return nil }
            return (name, String(match.1))
        }
        return inputFiles.filter { file, input in
            !silentInputs.contains(input)
                && !details.contains { $0.hasPrefix("\(file): joins the guide track") || $0.hasPrefix("\(file): no clear sound to sync") }
        }.map(\.file)
    }
}
