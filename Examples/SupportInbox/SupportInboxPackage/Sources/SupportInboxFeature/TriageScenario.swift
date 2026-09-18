import Foundation
import TypeSafe

enum TicketPreset: String, CaseIterable, Identifiable {
    case refund = "Duplicate charge"
    case login = "Login failure"
    case account = "Account question"

    var id: String { rawValue }
    var message: String {
        switch self {
        case .refund:
            "I was charged twice for my subscription. Rent is due tomorrow, and I need the duplicate payment refunded urgently."
        case .login:
            "Our entire team cannot log in after enabling SSO. We have a customer presentation in an hour and no one can access the workspace. Please help restore access."
        case .account:
            "Where can I change the display name on my profile? There is no rush; I am just tidying up my account."
        }
    }
}

struct TriageScenario: Encodable, Sendable {
    let state: Content
    let model: String
    let questions: [String: Question]

    static let rubric = [
        "Routine: general information or cosmetic change; no time pressure or blocked work.",
        "Timely: an inconvenience affecting one person, with a workaround and no immediate deadline.",
        "Urgent: financial hardship or a time-sensitive problem needing prompt human attention.",
        "Critical: a team-wide outage or blocked essential work with an immediate deadline.",
    ]

    init(message: String, model: String) {
        self.state = .object(["customer_message": .string(message), "channel": .string("support_inbox")])
        self.model = model
        self.questions = [
            "category": .choice(
                instructions: "Which support team should handle this customer's primary request?",
                criteria: [
                    "billing": "Payments, invoices, subscriptions, charges, and refunds.",
                    "technical": "Bugs, outages, login failures, and broken functionality.",
                    "account": "Profile changes, account settings, and general account administration.",
                    "other": "Requests not covered by billing, technical support, or account management.",
                ]
            ),
            "refund_requested": .noul(
                instructions: "Is the customer asking for money to be returned?",
                yes: "The customer explicitly requests a refund, reimbursement, or reversal of a charge.",
                no: "The customer is not asking for money back. A payment question alone is not a refund request."
            ),
            "urgency": .score(
                instructions: "How urgently should a human support agent respond? Judge the stated impact and deadline, not just emotional wording.",
                criteria: Self.rubric.map(Content.text)
            ),
        ]
    }

    func requestJSON() throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return String(decoding: try encoder.encode(self), as: UTF8.self)
    }
}

struct DemoCredentials: Sendable {
    private let key: String?

    init(environment: [String: String]) {
        let value = environment["TYPESAFE_API_KEY"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        key = value?.isEmpty == false ? value : nil
    }

    static var current: Self {
        #if DEBUG && targetEnvironment(simulator)
        Self(environment: ProcessInfo.processInfo.environment)
        #else
        Self(environment: [:])
        #endif
    }

    var isConfigured: Bool { key != nil }

    func client(timeout: Double, retries: Int, totalTimeout: Double? = nil) throws -> TypeSafeClient {
        guard let key else { throw TypeSafeError.invalidConfiguration("Use the local simulator launch script to supply TYPESAFE_API_KEY.") }
        return try TypeSafeClient(apiKey: key, timeout: .seconds(timeout), totalTimeout: totalTimeout.map { .seconds($0) }, retry: .init(maxRetries: retries))
    }

    func redacted(_ text: String) -> String {
        guard let key else { return text }
        return text.replacingOccurrences(of: key, with: "<redacted>")
    }

    func responseJSON(_ data: Data) -> String {
        let text: String
        if let value = try? JSONDecoder().decode(JSONValue.self, from: data) {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            if let formatted = try? encoder.encode(value) {
                text = String(decoding: formatted, as: UTF8.self)
            } else {
                text = String(decoding: data, as: UTF8.self)
            }
        } else {
            text = String(decoding: data, as: UTF8.self)
        }
        return redacted(text)
    }
}
