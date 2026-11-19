import Foundation

/// An error with its full chain (D64): its domain and code, its
/// description, failure reason and recovery suggestion, and every
/// underlying error, so that a failure nobody foresaw still says what
/// the system reported. `text` is the one line for people; the value
/// itself is `errorDetail` in the recording manifest. The recorder's own
/// errors, which say it all in their text, have the domain
/// `MultiScreenRecorder` or the module's (`RecorderCore.…`).
public struct ErrorDetail: Codable, Equatable, Sendable, ExpressibleByStringLiteral {
    public var domain: String
    public var code: Int
    public var description: String
    public var reason: String?
    public var suggestion: String?
    public var underlying: [ErrorDetail]
    /// The chain was cut at `maximumDepth`: this error has underlying
    /// errors that are left out.
    public var truncated = false

    /// The domain of the recorder's own errors that come from no `Error`.
    public static let ownDomain = "MultiScreenRecorder"
    /// The modules whose Swift errors are the recorder's own.
    static let ownModules = ["RecorderLogic", "RecorderCore", "msr"]
    /// How many levels of underlying errors are kept; the last kept says
    /// it is `truncated` when it has more.
    public static let maximumDepth = 8

    /// Any error with its chain of underlying errors.
    public init(_ error: any Error) {
        self.init(error, depth: 0)
    }

    /// The recorder's own error text, with the errors it comes from.
    public init(message: String, underlying: [ErrorDetail] = []) {
        domain = Self.ownDomain
        code = 0
        description = message
        self.underlying = underlying
    }

    /// The recorder's own error text, with the error it comes from, if any.
    public init(message: String, underlying error: (any Error)?) {
        self.init(message: message, underlying: error.map { [ErrorDetail($0)] } ?? [])
    }

    public init(stringLiteral message: String) {
        self.init(message: message)
    }

    private init(_ error: any Error, depth: Int) {
        if let detailed = error as? any ErrorWithDetail {
            self = detailed.detail
            return
        }
        let nsError = error as NSError
        domain = nsError.domain
        code = nsError.code
        description = Self.description(of: error, nsError)
        reason = nsError.localizedFailureReason
        suggestion = nsError.localizedRecoverySuggestion
        guard depth < Self.maximumDepth else {
            underlying = []
            truncated = !nsError.underlyingErrors.isEmpty
            return
        }
        underlying = nsError.underlyingErrors.map { ErrorDetail($0, depth: depth + 1) }
    }

    /// The text macOS gives an error, but for a Swift error that is no
    /// `NSError`: its own description, where bridging gives only "The
    /// operation couldn't be completed".
    private static func description(of error: any Error, _ nsError: NSError) -> String {
        if let localized = error as? any LocalizedError, let text = localized.errorDescription { return text }
        let isBridged = type(of: error) is NSError.Type || error is any CustomNSError
        return isBridged ? nsError.localizedDescription : String(describing: error)
    }

    /// Whether it is one of the recorder's own errors, whose text says it all.
    public var isOwn: Bool {
        domain == Self.ownDomain || Self.ownModules.contains { domain.hasPrefix("\($0).") }
    }

    /// The error as one line: "cannot write a.mov: The operation could not
    /// be completed (AVFoundationErrorDomain -11800; reason: An unknown
    /// error occurred (-12912)): The operation couldn't be completed.
    /// (NSOSStatusErrorDomain -12912)".
    public var text: String {
        var facts: [String] = []
        if !isOwn { facts.append("\(domain) \(Self.codeText(code))") }
        if let reason, !reason.isEmpty { facts.append("reason: \(reason)") }
        if let suggestion, !suggestion.isEmpty { facts.append("suggestion: \(suggestion)") }
        var line = description
        if !facts.isEmpty { line += " (\(facts.joined(separator: "; ")))" }
        if !underlying.isEmpty { line += ": " + underlying.map(\.text).joined(separator: "; ") }
        if truncated { line += ": … (deeper underlying errors left out)" }
        return Self.oneLine(line)
    }

    /// Line breaks in a text macOS gives become `⏎`, so a recording log
    /// entry stays one line.
    static func oneLine(_ text: String) -> String {
        text.replacing(/\r\n|\r|\n/, with: "⏎")
    }

    /// A code, with its four-character code where it has one, as an
    /// `OSStatus` often does: "1852797029 ('nope')", "-50".
    public static func codeText(_ code: Int) -> String {
        guard let fourCharacters = fourCharacterCode(code) else { return String(code) }
        return "\(code) ('\(fourCharacters)')"
    }

    /// The four characters of a 32-bit code whose bytes are all printable ASCII.
    public static func fourCharacterCode(_ code: Int) -> String? {
        guard let bits = UInt32(exactly: code) ?? Int32(exactly: code).map(UInt32.init(bitPattern:)) else { return nil }
        let bytes = withUnsafeBytes(of: bits.bigEndian, Array.init)
        guard bytes.allSatisfy({ (0x20...0x7E).contains($0) }) else { return nil }
        return String(decoding: bytes, as: UTF8.self)
    }

    private enum CodingKeys: String, CodingKey { case domain, code, description, reason, suggestion, underlying, truncated }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        domain = try container.decode(String.self, forKey: .domain)
        code = try container.decode(Int.self, forKey: .code)
        description = try container.decode(String.self, forKey: .description)
        reason = try container.decodeIfPresent(String.self, forKey: .reason)
        suggestion = try container.decodeIfPresent(String.self, forKey: .suggestion)
        underlying = try container.decode([ErrorDetail].self, forKey: .underlying)
        truncated = try container.decodeIfPresent(Bool.self, forKey: .truncated) ?? false
    }

    /// `reason` and `suggestion` are left out where there is none, `truncated` where it is false.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(domain, forKey: .domain)
        try container.encode(code, forKey: .code)
        try container.encode(description, forKey: .description)
        try container.encodeIfPresent(reason, forKey: .reason)
        try container.encodeIfPresent(suggestion, forKey: .suggestion)
        if truncated { try container.encode(truncated, forKey: .truncated) }
        try container.encode(underlying, forKey: .underlying)
    }
}

/// An error that carries its error detail, already made where it happened.
public protocol ErrorWithDetail: Error {
    var detail: ErrorDetail { get }
}
