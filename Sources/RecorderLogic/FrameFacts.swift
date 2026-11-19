import Foundation

/// What a screen capture's frame says of itself: the pixel buffer's size,
/// pixel format and colour attachments, and the frame info's content rect
/// and scale factor. A capture tells its first frame's and every later
/// change of them, never each frame (D66).
public struct FrameFacts: Equatable, Sendable {
    public var width: Int
    public var height: Int
    /// The pixel format as its four-character code, such as `420v`.
    public var pixelFormat: String
    public var primaries: String
    public var transferFunction: String
    public var yCbCrMatrix: String
    /// "none", or "attached" with the profile's size and checksum: whether the pixel buffer carries an ICC profile, and which.
    public var iccProfile: String
    /// The frame info's content rect, "(x,y,w,h)"; nil when the frame has none.
    public var contentRect: String?
    public var scaleFactor: Double?
    /// What the screen check said of the frame: "passes", "fails", "shows another screen", or "not judged".
    public var screenCheck: String

    public init(
        width: Int, height: Int, pixelFormat: String, primaries: String, transferFunction: String, yCbCrMatrix: String,
        iccProfile: String, contentRect: String?, scaleFactor: Double?, screenCheck: String = "not judged"
    ) {
        self.width = width
        self.height = height
        self.pixelFormat = pixelFormat
        self.primaries = primaries
        self.transferFunction = transferFunction
        self.yCbCrMatrix = yCbCrMatrix
        self.iccProfile = iccProfile
        self.screenCheck = screenCheck
        self.contentRect = contentRect
        self.scaleFactor = scaleFactor
    }

    /// "1280×720 420v, primaries ITU_R_709_2, transfer function ITU_R_709_2, matrix ITU_R_709_2, content rect (0,0,1280,720), scale factor 1.0"
    public var text: String {
        "\(width)×\(height) \(pixelFormat), primaries \(primaries), transfer function \(transferFunction), "
            + "matrix \(yCbCrMatrix), ICC profile \(iccProfile), content rect \(contentRect ?? "none"), "
            + "scale factor \(scaleFactor.map { "\($0)" } ?? "none"), screen check \(screenCheck)"
    }

    /// Each value that differs from the frame before, "was → now"; nil when none does.
    public func changes(from before: FrameFacts) -> String? {
        let all: [(String, String, String)] = [
            ("size", "\(before.width)×\(before.height)", "\(width)×\(height)"),
            ("pixel format", before.pixelFormat, pixelFormat),
            ("primaries", before.primaries, primaries),
            ("transfer function", before.transferFunction, transferFunction),
            ("matrix", before.yCbCrMatrix, yCbCrMatrix),
            ("ICC profile", before.iccProfile, iccProfile),
            ("content rect", before.contentRect ?? "none", contentRect ?? "none"),
            ("scale factor", before.scaleFactor.map { "\($0)" } ?? "none", scaleFactor.map { "\($0)" } ?? "none"),
            ("screen check", before.screenCheck, screenCheck),
        ]
        let changed = all.filter { $0.1 != $0.2 }.map { "\($0.0) \($0.1) → \($0.2)" }
        return changed.isEmpty ? nil : changed.joined(separator: ", ")
    }

    /// "420v" for 0x34323076.
    public static func fourCharacterCode(_ code: UInt32) -> String {
        let characters = (0..<4).map { UInt8(truncatingIfNeeded: code >> UInt32(24 - 8 * $0)) }
        guard characters.allSatisfy({ $0 >= 0x20 && $0 < 0x7f }) else { return "0x" + String(code, radix: 16) }
        return String(decoding: characters, as: UTF8.self)
    }
}

/// The video encoders VideoToolbox lists for the codec in use, for the detail line at a file's start (D66).
public enum EncoderListText {
    public struct Encoder: Equatable, Sendable {
        public var name: String
        public var id: String
        public var isHardwareAccelerated: Bool

        public init(name: String, id: String, isHardwareAccelerated: Bool) {
            self.name = name
            self.id = id
            self.isHardwareAccelerated = isHardwareAccelerated
        }
    }

    /// "video encoders for hvc1: Apple HEVC (com.apple.videotoolbox.videoencoder.ave.hevc, hardware accelerated), …"
    public static func text(codec: String, _ encoders: [Encoder]) -> String {
        "video encoders for \(codec): " + (encoders.isEmpty ? "none listed" : encoders.map {
            "\($0.name) (\($0.id), \($0.isHardwareAccelerated ? "hardware accelerated" : "software"))"
        }.joined(separator: ", "))
    }
}

/// The values of an `AVAssetWriterInput`'s output settings, as one line.
public enum SettingsText {
    /// "AVVideoCodecKey=hvc1, AVVideoCompressionPropertiesKey={…}": keys in order, nested dictionaries in braces, lists in brackets.
    public static func text(_ value: Any) -> String {
        switch value {
        case let dictionary as [String: Any]:
            "{" + dictionary.keys.sorted().map { "\($0)=\(text(dictionary[$0]!))" }.joined(separator: ", ") + "}"
        case let list as [Any]:
            "[" + list.map(text).joined(separator: ", ") + "]"
        default:
            "\(value)"
        }
    }
}

/// The samples each input of a screen file took, for the detail line of a
/// failed writer: per input how many, the presentation time of the last,
/// and which input's append returned false first (D66).
public struct InputAppends: Equatable, Sendable {
    private struct Input: Equatable, Sendable {
        var name: String
        var count = 0
        var lastTime: Double?
    }

    private var inputs: [Input]
    public private(set) var firstRefused: String?

    /// The inputs by name, in the order they are told.
    public init(inputs names: [String]) {
        inputs = names.map { Input(name: $0) }
    }

    public mutating func appended(_ name: String, at seconds: Double) {
        guard let index = inputs.firstIndex(where: { $0.name == name }) else { return }
        inputs[index].count += 1
        inputs[index].lastTime = seconds
    }

    /// An append of the input returned false.
    public mutating func refused(_ name: String) {
        firstRefused = firstRefused ?? name
    }

    /// "video: 120 samples, last at 5.667 s; timecode: 1 sample, last at 1.266 s; no append returned false"
    public var text: String {
        let each = inputs.map { input in
            "\(input.name): \(input.count) \(input.count == 1 ? "sample" : "samples")"
                + (input.lastTime.map { String(format: ", last at %.3f s", $0) } ?? "")
        }
        return (each + [firstRefused.map { "the first append that returned false: \($0)" } ?? "no append returned false"])
            .joined(separator: "; ")
    }
}
