import Foundation

/// The one way JSON files are written: Apple's `JSONEncoder` with sorted keys,
/// pretty printed, slashes as they are, and a final newline.
func prettyJSON(_ value: some Encodable) throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .prettyPrinted, .withoutEscapingSlashes]
    return try encoder.encode(value) + Data("\n".utf8)
}
