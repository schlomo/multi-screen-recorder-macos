/// Which audio input files of a recording are still being measured against the others, read from its
/// `recording.log`'s `recorder` detail lines: a file is out of measuring once `AudioDelays` logged that
/// it joins the guide track (the anchor's own file at its start) or has no clear sound to sync. The
/// system audio, `Audio 0 - System`, is not measured.
public enum AudioMeasuring {
    /// The audio input files started and still measuring, in the order they started.
    public static func filesMeasuring(log: String) -> [String] {
        let details = log.split(separator: "\n").compactMap { line in
            line.firstRange(of: " detail recorder: ").map { String(line[$0.upperBound...]) }
        }
        let inputFiles = details.compactMap { detail -> String? in
            guard detail.hasPrefix("file started: ") else { return nil }
            let name = String(detail.dropFirst("file started: ".count))
            return name.contains(#/ Audio [1-9][0-9]* - /#) ? name : nil
        }
        return inputFiles.filter { name in
            !details.contains { $0.hasPrefix("\(name): joins the guide track") || $0.hasPrefix("\(name): no clear sound to sync") }
        }
    }
}
