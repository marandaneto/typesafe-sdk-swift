import Foundation
import Testing
@testable import TypeSafe

@Suite("Pinned wire contract")
struct ContractTests {
    private func fixture(_ name: String) throws -> Data {
        try Data(contentsOf: #require(Bundle.module.url(forResource: name, withExtension: "json")))
    }

    @Test func dictionaryRequestMatchesGoldenFixture() async throws {
        let transport = StubTransport([.response(200, [:], try fixture("system-one-response"))])
        let client = try TypeSafeClient(apiKey: "test", baseURL: #require(URL(string: "https://example.com")), transport: transport)
        let response = try await client.systemOne(
            state: .object(["document": .string("I was charged twice.")]),
            questions: [
                "category": .choice(instructions: "Category?", criteria: ["billing": .null, "technical": .null]),
                "urgent": .noul(instructions: "Urgent?"),
                "priority": .score(criteria: ["Can wait", "Needs attention", "Urgent"]),
            ]
        )
        let actual = try #require(await transport.requests.first?.httpBody)
        #expect(try JSONDecoder().decode(JSONValue.self, from: actual) == JSONDecoder().decode(JSONValue.self, from: fixture("system-one-request")))
        #expect(response.rawBody == (try fixture("system-one-response")))
        #expect(response.value.answers.count == 3)
    }

    @Test func pinnedOpenAPIDescribesSupportedEndpointsAndDiscriminators() throws {
        let schema = try JSONDecoder().decode(JSONValue.self, from: fixture("openapi"))
        #expect(schema["openapi"] == .string("3.1.0"))
        #expect(schema["paths"]?["/v1/systemone"]?["post"] != nil)
        #expect(schema["paths"]?["/v1/models"]?["get"] != nil)
        let models = try #require(schema["components"]?["schemas"])
        for (model, discriminator) in [("Noul", "noul"), ("Choice", "choice"), ("Score", "score")] {
            #expect(models[model + "Question"]?["properties"]?["type"]?["const"] == .string(discriminator))
            #expect(models[model + "Answer"]?["properties"]?["type"]?["const"] == .string(discriminator))
        }
        #expect(models["SystemOneRequest"]?["properties"]?["questions"]?["minProperties"] == .integer(1))
    }

    @Test func knownSchemaDifferencesRemainExplicit() throws {
        let schema = try JSONDecoder().decode(JSONValue.self, from: fixture("openapi"))
        let models = try #require(schema["components"]?["schemas"])
        #expect(models["ScoreQuestion"]?["properties"]?["criteria"]?["minItems"] == .integer(1))
        let nonnullContent = JSONValue.array([
            .object(["type": .string("string")]),
            .object(["type": .string("object"), "additionalProperties": .bool(true)]),
            .object(["type": .string("array"), "items": .object([:])]),
        ])
        #expect(models["SystemOneRequest"]?["properties"]?["state"]?["anyOf"] == nonnullContent)
        #expect(models["ScoreQuestion"]?["properties"]?["criteria"]?["items"]?["anyOf"] == nonnullContent)
        #expect(models["ScoreAnswer"]?["properties"]?["legend"]?["additionalProperties"]?["anyOf"] == nonnullContent)
    }
}

private extension JSONValue {
    subscript(key: String) -> JSONValue? {
        guard case .object(let object) = self else { return nil }
        return object[key]
    }
}
