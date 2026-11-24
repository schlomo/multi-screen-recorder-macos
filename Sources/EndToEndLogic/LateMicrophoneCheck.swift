/// The late-microphone scenario's check of `recording.json` (D80, backlog item 52): every input recorded and the
/// test tone in the loopback device, which the VM's other input hears late. Whichever of the two is the anchor
/// (a race between their files' starts) lists `delays` `[{at: 0, delay: 0}]`; the other is measured, its latest
/// audio delay's size within `EndToEndValues.lateMicrophoneDelay`, and neither leaves the "Audio inputs" guide
/// track. That the guide places its sound in line is the tone check's, on the guide from
/// `EndToEndValues.lateMicrophoneJoinedBy` on.
public enum LateMicrophoneCheck {
    public static func failures(manifest: JSONValue, loopbackUID: String) -> [String] {
        let inputs = (manifest["files"]?.array ?? []).compactMap { file -> (uid: String, name: String, delays: [Double])? in
            guard let uid = file["audioSourceUID"]?.string, let name = file["audioSource"]?.string else { return nil }
            return (uid, name, (file["delays"]?.array ?? []).compactMap { $0["delay"]?.number })
        }
        let uids = inputs.map(\.uid)
        guard inputs.count == 2, Set(uids).count == 2, uids.contains(loopbackUID) else {
            return ["expected the loopback device and one more audio input, each with one file; found "
                + inputs.map(\.name).joined(separator: ", ")]
        }
        let isAnchor = { (input: (uid: String, name: String, delays: [Double])) in input.delays == [0] }
        guard let anchor = inputs.first(where: isAnchor), let measured = inputs.first(where: { !isAnchor($0) }) else {
            return ["no anchor: neither \(inputs[0].name) nor \(inputs[1].name) lists delays [{at: 0, delay: 0}]"]
        }
        let range = EndToEndValues.lateMicrophoneDelay
        let expected = "\(milliseconds(range.lowerBound)) to \(milliseconds(range.upperBound)) ms against the anchor \(anchor.name)"
        var failures: [String] = []
        if let latest = measured.delays.last {
            if !range.contains(abs(latest)) { failures.append("\(measured.name): audio delay \(milliseconds(latest)) ms, expected \(expected)") }
        } else {
            failures.append("\(measured.name): no audio delay measured, expected one of \(expected)")
        }
        for event in manifest["events"]?.array ?? [] where event["event"]?.string == "audio input left the guide track" {
            failures.append("\(event["audioSource"]?.string ?? "an audio input") left the \"Audio inputs\" guide track")
        }
        return failures
    }

    private static func milliseconds(_ seconds: Double) -> Int { Int((seconds * 1000).rounded()) }
}
