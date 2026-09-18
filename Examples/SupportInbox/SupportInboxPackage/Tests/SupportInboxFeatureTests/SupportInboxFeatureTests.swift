import Foundation
import Testing
import TypeSafe
@testable import SupportInboxFeature

@Suite("Support Inbox scenarios")
struct SupportInboxFeatureTests {
    @Test(arguments: TicketPreset.allCases)
    func presetsIncludeEveryQuestionType(preset: TicketPreset) throws {
        let scenario = TriageScenario(message: preset.message, model: "jev-latest")
        #expect(scenario.questions.count == 3)
        guard case .choice(_, let categories) = scenario.questions["category"],
              case .noul = scenario.questions["refund_requested"],
              case .score(_, let criteria) = scenario.questions["urgency"] else {
            Issue.record("Scenario must demonstrate choice, noul, and score")
            return
        }
        #expect(Set(categories.keys) == ["billing", "technical", "account", "other"])
        #expect(criteria.count == 4)
        let body = try JSONDecoder().decode(JSONValue.self, from: Data(scenario.requestJSON().utf8))
        guard case .object(let fields) = body else { Issue.record("Expected object"); return }
        #expect(fields["model"] == .string("jev-latest"))
        #expect(fields["state"] == .object(["customer_message": .string(preset.message), "channel": .string("support_inbox")]))
        #expect(fields["apiKey"] == nil)
    }

    @Test func missingCredentialsAreRejected() {
        let credentials = DemoCredentials(environment: [:])
        #expect(!credentials.isConfigured)
        #expect(throws: TypeSafeError.self) { try credentials.client(timeout: 10, retries: 0) }
    }

    @Test func keyIsRedactedFromDisplayedResponses() {
        let credentials = DemoCredentials(environment: ["TYPESAFE_API_KEY": "test-secret"])
        #expect(credentials.isConfigured)
        let display = credentials.responseJSON(Data("{\"detail\":\"test-secret\"}".utf8))
        #expect(!display.contains("test-secret"))
        #expect(display.contains("<redacted>"))
        #expect(credentials.responseJSON(Data("test-secret".utf8)) == "<redacted>")
    }
}
