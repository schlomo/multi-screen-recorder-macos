import Foundation

/// A JSON document as it was written, read by the end-to-end tests' own
/// code: the assertions never read a recording through the recorder's
/// types, or a fault shared with the recorder would hide itself.
public enum JSONValue: Equatable, Sendable, Decodable, CustomStringConvertible {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else {
            self = .object(try container.decode([String: JSONValue].self))
        }
    }

    public init(json data: Data) throws {
        self = try JSONDecoder().decode(JSONValue.self, from: data)
    }

    public subscript(key: String) -> JSONValue? {
        if case .object(let members) = self { members[key] } else { nil }
    }

    public var string: String? { if case .string(let value) = self { value } else { nil } }
    public var number: Double? { if case .number(let value) = self { value } else { nil } }
    public var array: [JSONValue]? { if case .array(let value) = self { value } else { nil } }
    public var keys: Set<String>? { if case .object(let members) = self { Set(members.keys) } else { nil } }
    public var isNull: Bool { self == .null }

    /// A whole number, or nil.
    public var integer: Int? {
        guard let number, number.rounded() == number, abs(number) < 1e15 else { return nil }
        return Int(number)
    }

    public var description: String {
        switch self {
        case .null: "null"
        case .bool(let value): "\(value)"
        case .number(let value): value.rounded() == value && abs(value) < 1e15 ? "\(Int(value))" : "\(value)"
        case .string(let value): "\"\(value)\""
        case .array(let values): "[\(values.map(\.description).joined(separator: ", "))]"
        case .object(let members):
            "{\(members.sorted { $0.key < $1.key }.map { "\"\($0.key)\": \($0.value)" }.joined(separator: ", "))}"
        }
    }
}
