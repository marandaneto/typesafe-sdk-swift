import Foundation
import Testing
@testable import TypeSafe

@Test func roundTripsNestedJSON() throws {
    let value = JSONValue.object([
        "text": .string("Hello 👋"),
        "values": .array([.null, .bool(true), .bool(false), .integer(42), .number(0.25)]),
        "empty": .object([:]),
    ])

    let data = try JSONEncoder().encode(value)
    #expect(try JSONDecoder().decode(JSONValue.self, from: data) == value)
}

@Test func preservesLargeIntegers() throws {
    let value = JSONValue.integer(9_007_199_254_740_993)
    let data = try JSONEncoder().encode(value)
    #expect(try JSONDecoder().decode(JSONValue.self, from: data) == value)
}

@Test func distinguishesBooleansFromNumbers() throws {
    let data = Data("[true,false,1,0]".utf8)
    #expect(try JSONDecoder().decode(JSONValue.self, from: data) == .array([
        .bool(true), .bool(false), .integer(1), .integer(0),
    ]))
}

@Test(arguments: [Double.infinity, -Double.infinity, Double.nan])
func rejectsNonfiniteNumbers(value: Double) {
    #expect(throws: EncodingError.self) {
        try JSONEncoder().encode(JSONValue.number(value))
    }
}

@Test func rejectsMalformedJSON() {
    #expect(throws: DecodingError.self) {
        try JSONDecoder().decode(JSONValue.self, from: Data("{invalid}".utf8))
    }
}

@Test func canCrossActorBoundaries() async {
    actor Store {
        let value: JSONValue
        init(value: JSONValue) { self.value = value }
        func read() -> JSONValue { value }
    }

    let value = JSONValue.object(["document": .string("A support request")])
    let store = Store(value: value)
    #expect(await store.read() == value)
}
