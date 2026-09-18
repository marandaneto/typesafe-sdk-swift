import Foundation
import Testing
@testable import TypeSafe

@Suite("Response validation")
struct ResponseValidationTests {
    @Test(arguments: [
        #"{"type":"noul","noul":-0.01}"#,
        #"{"type":"noul","noul":1.01}"#,
        #"{"type":"noul","noul":"0.5"}"#,
        #"{"type":"noul"}"#,
        #"{"type":"future","noul":0.5}"#,
        #"{"type":"choice","choice":"a","confidence":2,"probabilities":{"a":1}}"#,
        #"{"type":"choice","choice":"a","confidence":0.9,"probabilities":{"a":-1}}"#,
        #"{"type":"choice","choice":"a","confidence":0.9,"probabilities":{"b":1}}"#,
        #"{"type":"score","score":-1,"confidence":0.9,"legend":{"0":"low","1":"high"},"probabilities":{"0":0.5,"1":0.5}}"#,
        #"{"type":"score","score":0.5,"confidence":-1,"legend":{"0":"low","1":"high"},"probabilities":{"0":0.5,"1":0.5}}"#,
        #"{"type":"score","score":0.5,"confidence":0.9,"legend":{"0":"low","1":"high"},"probabilities":{"0":2,"1":0.5}}"#,
        #"{"type":"score","score":0.5,"confidence":0.9,"legend":{"0":"low","1":"high"},"probabilities":{"0":1}}"#,
        #"{"type":"score","score":0.5,"confidence":0.9,"legend":{"0":true,"1":"high"},"probabilities":{"0":0.5,"1":0.5}}"#,
        #"{"type":"score","score":0.5,"confidence":0.9,"legend":{"01":"high"},"probabilities":{"01":1}}"#,
        #"{"type":"score","score":2,"confidence":0.9,"legend":{"0":"low","1":"high"},"probabilities":{"0":0.5,"1":0.5}}"#,
        #"{"type":"score","score":1,"confidence":0.9,"legend":{"0":"low","2":"high"},"probabilities":{"0":0.5,"2":0.5}}"#,
    ])
    func rejectsInvalidAnswers(json: String) {
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(Answer.self, from: Data(json.utf8))
        }
    }

    @Test func acceptsRoundedProbabilitiesWithoutRequiringExactSum() throws {
        let json = #"{"type":"choice","choice":"a","confidence":0.333,"probabilities":{"a":0.333,"b":0.333,"c":0.333},"future_field":true}"#
        let answer = try JSONDecoder().decode(Answer.self, from: Data(json.utf8))
        guard case .choice(let choice) = answer else { Issue.record("Expected choice"); return }
        #expect(choice.probabilities.count == 3)
    }

    @Test(arguments: [
        #"{"input_tokens":-1,"output_tokens":1}"#,
        #"{"input_tokens":1,"output_tokens":-1}"#,
        #"{"input_tokens":null,"output_tokens":1}"#,
        #"{"output_tokens":1}"#,
    ])
    func requiresNonnegativeTokenCounts(json: String) {
        #expect(throws: DecodingError.self) { try JSONDecoder().decode(Usage.self, from: Data(json.utf8)) }
    }

    @Test func rejectsEmptyAnswers() {
        let json = #"{"model":"test","answers":{},"usage":{"input_tokens":0,"output_tokens":0}}"#
        #expect(throws: DecodingError.self) { try JSONDecoder().decode(SystemOneResponse.self, from: Data(json.utf8)) }
    }

    @Test func supportsExplicitNullScoreLegendForJavaScriptParity() throws {
        let json = #"{"type":"score","score":0.5,"confidence":0.9,"legend":{"0":null,"1":"high"},"probabilities":{"0":0.5,"1":0.5}}"#
        let answer = try JSONDecoder().decode(Answer.self, from: Data(json.utf8))
        guard case .score(let score) = answer else { Issue.record("Expected score"); return }
        #expect(score.legend[0] == JSONValue.null)
    }

    @Test func rejectsMismatchedProbabilityKeysWithoutRetrying() async throws {
        let json = #"{"model":"test","answers":{"q":{"type":"choice","choice":"a","confidence":0.9,"probabilities":{"a":1}}},"usage":{"input_tokens":0,"output_tokens":0}}"#
        let transport = StubTransport([.response(200, [:], Data(json.utf8))])
        let client = try TypeSafeClient(apiKey: "test", baseURL: #require(URL(string: "https://example.com")), transport: transport)
        do {
            _ = try await client.systemOne(state: "test", questions: ["q": .choice(criteria: ["a": .null, "b": .null])])
            Issue.record("Expected mismatch")
        } catch TypeSafeError.invalidResponse {}
        #expect(await transport.requests.count == 1)
    }

    @Test func rejectsNonfiniteValuesEvenWithCustomDecoder() {
        let decoder = JSONDecoder()
        decoder.nonConformingFloatDecodingStrategy = .convertFromString(positiveInfinity: "Infinity", negativeInfinity: "-Infinity", nan: "NaN")
        #expect(throws: DecodingError.self) {
            try decoder.decode(NoulAnswer.self, from: Data(#"{"noul":"NaN"}"#.utf8))
        }
    }
}
