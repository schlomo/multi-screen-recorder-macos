import Foundation

/// The names in a recording folder (D20, D31): the folder is named by the
/// recording's local start time, each file by its own.
public enum RecordingNames {
    /// "2026-11-12 14.03.05".
    public static func timeStamp(_ date: Date, timeZone: TimeZone) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        func two(_ value: Int?) -> String { String(format: "%02d", value ?? 0) }
        return "\(String(format: "%04d", parts.year ?? 0))-\(two(parts.month))-\(two(parts.day))"
            + " \(two(parts.hour)).\(two(parts.minute)).\(two(parts.second))"
    }

    public static func recordingFolder(start: Date, timeZone: TimeZone) -> String {
        timeStamp(start, timeZone: timeZone)
    }

    /// "2026-11-12 14.03.05 Screen 1 - Built-in Retina Display.mov"; when that
    /// name is taken in the recording folder (a new file within the same
    /// second), " (2)", " (3)" and so on before the extension.
    public static func screenFile(
        start: Date, timeZone: TimeZone, number: Int, screen: String, taken: Set<String> = []
    ) -> String {
        untaken("\(timeStamp(start, timeZone: timeZone)) Screen \(number) - \(fileNamePart(screen))", taken: taken)
    }

    /// "2026-11-12 14.03.05 Microphone - MacBook Pro Microphone.mov" for an
    /// audio input under its unique name, "2026-11-12 14.03.05 System
    /// audio.mov" for the system audio; a taken name as for a screen file.
    public static func audioFile(
        start: Date, timeZone: TimeZone, source: AudioFileDescription.Source, taken: Set<String> = []
    ) -> String {
        let what = switch source {
        case .audioInput(let name, _, _): "Microphone - \(fileNamePart(name))"
        case .systemAudio: AudioFileDescription.systemAudioName
        }
        return untaken("\(timeStamp(start, timeZone: timeZone)) \(what)", taken: taken)
    }

    private static func untaken(_ base: String, taken: Set<String>) -> String {
        var name = "\(base).mov"
        var copy = 2
        while taken.contains(name) {
            name = "\(base) (\(copy)).mov"
            copy += 1
        }
        return name
    }

    public static let manifest = "recording.json"

    /// A device name as part of a file name: `/` and `:`, which a file name
    /// cannot hold or Finder shows as the other, become `-`, so a name never
    /// stops a screen from recording.
    public static func fileNamePart(_ name: String) -> String {
        name.replacing(/[\/:]/, with: "-")
    }
}
