import Foundation
import Testing
import TypeSafe

@Suite("JSONValue coding")
struct JSONValueCodingTests {
    @Test(arguments: [
        JSONValue.null, .bool(true), .bool(false),
        .integer(.min), .integer(.max), .integer(0),
        .number(-0.125), .number(1.5),
        .string(""), .string("\"quoted\"\n\\\t👋"),
        .array([]), .object([:]),
    ])
    func roundTrips(value: JSONValue) throws {
        let data = try JSONEncoder().encode(value)
        #expect(try JSONDecoder().decode(JSONValue.self, from: data) == value)
    }

    @Test(arguments: ["1", "1.0", "1e0"])
    func normalizesIntegralNumbers(json: String) throws {
        #expect(try JSONDecoder().decode(JSONValue.self, from: Data(json.utf8)) == .integer(1))
    }

    @Test(arguments: ["", "[1", "{\"value\":}", "NaN", "Infinity", "null false"])
    func rejectsInvalidDocuments(json: String) {
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(JSONValue.self, from: Data(json.utf8))
        }
    }

    @Test func preservesExplicitNullFields() throws {
        let data = try JSONEncoder().encode(JSONValue.object(["present": .null]))
        let decoded = try JSONDecoder().decode(JSONValue.self, from: data)
        guard case .object(let fields) = decoded else {
            Issue.record("Expected a JSON object")
            return
        }
        #expect(fields["present"] == JSONValue.null)
        #expect(fields["missing"] == nil)
    }

    @Test func rejectsNestedNonfiniteNumbersEvenWithStringConversionEnabled() {
        let encoder = JSONEncoder()
        encoder.nonConformingFloatEncodingStrategy = .convertToString(
            positiveInfinity: "Infinity", negativeInfinity: "-Infinity", nan: "NaN"
        )
        #expect(throws: EncodingError.self) {
            try encoder.encode(JSONValue.object(["values": .array([.number(.nan)])]))
        }
    }
}
