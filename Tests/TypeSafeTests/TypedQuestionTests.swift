import Foundation
import Testing
@testable import TypeSafe

private enum Category: String, CaseIterable, Sendable {
    case billing, technical
}

@Suite("Typed question handles")
struct TypedQuestionTests {
    private let body = Data("""
    {
      "model": "jev-latest",
      "answers": {
        "category": {"type":"choice","choice":"billing","confidence":0.9,"probabilities":{"billing":0.9,"technical":0.1}},
        "refund": {"type":"noul","noul":0.95},
        "urgency": {"type":"score","score":0.7,"confidence":0.8,"legend":{"0":"Routine","1":"Urgent"},"probabilities":{"0":0.3,"1":0.7}}
      },
      "usage": {"input_tokens":10,"output_tokens":3}
    }
    """.utf8)

    @Test func mixedHandlesSendOneRequestAndReturnTypedAnswers() async throws {
        let category = ChoiceQuestion<Category>(id: "category", instructions: "Which team?")
        let refund = NoulQuestion(id: "refund", instructions: "Is a refund requested?")
        let urgency = ScoreQuestion(id: "urgency", criteria: ["Routine", "Urgent"])
        let transport = StubTransport([.response(200, [:], body)])
        let client = try TypeSafeClient(apiKey: "test", baseURL: #require(URL(string: "https://example.com")), transport: transport)
        let response = try await client.systemOne(state: "Refund please", questions: [
            category.eraseToAnyQuestion(), refund.eraseToAnyQuestion(), urgency.eraseToAnyQuestion(),
        ])
        let choice = try response.answer(for: category)
        let selected: Category = choice.choice
        #expect(selected == .billing)
        #expect(choice.probabilities[.technical] == 0.1)
        #expect(try response.answer(for: refund).noul == 0.95)
        #expect(try response.answer(for: urgency).score == 0.7)
        #expect(try response.value.answer(for: category).confidence == 0.9)
        #expect(await transport.requests.count == 1)
        let data = try #require(await transport.requests.first?.httpBody)
        guard case .object(let request) = try JSONDecoder().decode(JSONValue.self, from: data),
              case .object(let questions) = request["questions"],
              case .object(let encoded) = questions["category"] else {
            Issue.record("Expected a normal named-question request")
            return
        }
        #expect(encoded["criteria"] == .object(["billing": .null, "technical": .null]))
    }

    @Test func explicitCriteriaSupportDescribedSubsets() throws {
        let category = ChoiceQuestion<Category>(id: "category", criteria: [.billing: "Payment problems"])
        let erased = category.eraseToAnyQuestion()
        #expect(erased.id == "category")
        guard case .choice(_, let criteria) = erased.question else { Issue.record("Expected choice"); return }
        #expect(criteria == ["billing": .text("Payment problems")])
    }

    @Test func rejectsDuplicateIDsBeforeNetworking() async throws {
        let transport = StubTransport([])
        let client = try TypeSafeClient(apiKey: "test", baseURL: #require(URL(string: "https://example.com")), transport: transport)
        let questions = [NoulQuestion(id: "same").eraseToAnyQuestion(), ScoreQuestion(id: "same", criteria: ["Low", "High"]).eraseToAnyQuestion()]
        do {
            _ = try await client.systemOne(state: "test", questions: questions)
            Issue.record("Expected duplicate ID error")
        } catch TypeSafeError.invalidRequest(let message) {
            #expect(message.contains("same"))
        }
        #expect(await transport.requests.isEmpty)
    }

    @Test func rejectsMissingAndWrongTypeHandles() throws {
        let response = try JSONDecoder().decode(SystemOneResponse.self, from: body)
        #expect(throws: TypeSafeError.self) { try response.answer(for: NoulQuestion(id: "missing")) }
        #expect(throws: TypeSafeError.self) { try response.answer(for: NoulQuestion(id: "category")) }
        #expect(throws: TypeSafeError.self) {
            try response.answer(for: ChoiceQuestion<Category>(id: "refund"))
        }
    }

    @Test func rejectsHandleWithDifferentCriteria() throws {
        let response = try JSONDecoder().decode(SystemOneResponse.self, from: body)
        #expect(throws: TypeSafeError.self) {
            try response.answer(for: ChoiceQuestion<Category>(id: "category", criteria: [.technical: .null]))
        }
        #expect(throws: TypeSafeError.self) {
            try response.answer(for: ScoreQuestion(id: "urgency", criteria: ["Low", "Medium", "High"]))
        }
    }

    @Test func rejectsUnknownChoiceWithoutCastingOrDefaulting() throws {
        let unknown = Data(String(decoding: body, as: UTF8.self).replacingOccurrences(of: "billing", with: "unknown").utf8)
        let response = try JSONDecoder().decode(SystemOneResponse.self, from: unknown)
        #expect(throws: TypeSafeError.self) { try response.answer(for: ChoiceQuestion<Category>(id: "category")) }
    }

    @Test func typedHandlesAndAnswersAreSendable() async throws {
        let question = ChoiceQuestion<Category>(id: "category")
        let response = try JSONDecoder().decode(SystemOneResponse.self, from: body)
        try await withThrowingTaskGroup(of: TypedChoiceAnswer<Category>.self) { group in
            group.addTask { try response.answer(for: question) }
            let answer = try await group.next()
            #expect(answer?.choice == .billing)
        }
    }
}
