import Foundation
import Testing
@testable import EndToEndLogic

@Suite struct JSONValueTests {
    @Test func aDocumentIsReadAsWritten() throws {
        let value = try JSONValue(json: Data(#"{"a": null, "b": true, "c": 2, "d": 0.5, "e": "x", "f": [1, "y"], "g": {"h": false}}"#.utf8))
        #expect(value["a"] == .null)
        #expect(value["b"] == .bool(true))
        #expect(value["c"]?.integer == 2)
        #expect(value["d"]?.integer == nil)
        #expect(value["d"]?.number == 0.5)
        #expect(value["e"]?.string == "x")
        #expect(value["f"] == .array([.number(1), .string("y")]))
        #expect(value["g"]?["h"] == .bool(false))
        #expect(value["missing"] == nil)
        #expect(value.keys == ["a", "b", "c", "d", "e", "f", "g"])
    }

    @Test func aBooleanIsNeverANumber() throws {
        let value = try JSONValue(json: Data(#"[true, 1]"#.utf8))
        #expect(value == .array([.bool(true), .number(1)]))
        #expect(value.array?.first?.number == nil)
    }

    @Test func itIsShownAsJSON() {
        #expect(JSONValue.object(["b": .array([.number(1280), .number(0.5)]), "a": .string("x")]).description == #"{"a": "x", "b": [1280, 0.5]}"#)
    }
}
