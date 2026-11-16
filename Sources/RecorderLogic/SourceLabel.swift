/// A recorded source's label (D55): its kind, its number and its name. The
/// numbers count per kind from 1 in order of appearance in the recording,
/// and a source keeps its number when it comes back; the system audio is
/// always number 0. The label names the source's files, reel and tracks.
public enum SourceLabel {
    public static let systemAudio = "Audio 0 - System"

    /// "Screen 2 - LG HDR 4K".
    public static func screen(_ number: Int, name: String) -> String {
        "Screen \(number) - \(name)"
    }

    /// "Audio 3 - Razer Seiren V3 Mini".
    public static func audioInput(_ number: Int, name: String) -> String {
        "Audio \(number) - \(name)"
    }
}

/// A source in the Source column of the window's tables (D55): its kind,
/// its number if it is recorded, and its name. The window shows the kind
/// as an icon; the terminal shows `text`.
public struct SourceCell: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case screen
        case audioInput
        case systemAudio
    }

    public var kind: Kind
    /// Nil for a source not recorded.
    public var number: Int?
    public var name: String

    public init(kind: Kind, number: Int?, name: String) {
        self.kind = kind
        self.number = number
        self.name = name
    }

    public static func screen(_ number: Int?, name: String) -> SourceCell {
        SourceCell(kind: .screen, number: number, name: name)
    }

    public static func audioInput(_ number: Int?, name: String) -> SourceCell {
        SourceCell(kind: .audioInput, number: number, name: name)
    }

    /// Number 0 and "System" when recorded, as in its label; else "System audio".
    public static func systemAudio(isRecorded: Bool) -> SourceCell {
        isRecorded ? SourceCell(kind: .systemAudio, number: 0, name: "System")
            : SourceCell(kind: .systemAudio, number: nil, name: AudioFileDescription.systemAudioName)
    }

    /// The label; the name alone without a number.
    public var text: String {
        guard let number else { return name }
        return switch kind {
        case .screen: SourceLabel.screen(number, name: name)
        case .audioInput: SourceLabel.audioInput(number, name: name)
        case .systemAudio: SourceLabel.systemAudio
        }
    }
}
