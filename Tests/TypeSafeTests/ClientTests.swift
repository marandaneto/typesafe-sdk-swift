import Foundation
import Testing
@testable import TypeSafe

actor StubTransport: HTTPTransport {
    enum Step: Sendable {
        case response(Int, [String: String] = [:], Data = Data("{\"models\":[]}".utf8))
        case connectionFailure
    }
    private var steps: [Step]
    private(set) var requests: [URLRequest] = []

    init(_ steps: [Step]) { self.steps = steps }

    func send(_ request: URLRequest) async throws -> HTTPResult {
        requests.append(request)
        guard !steps.isEmpty else { throw TypeSafeError.invalidResponse("Unexpected request") }
        switch steps.removeFirst() {
        case .connectionFailure: throw URLError(.networkConnectionLost)
        case .response(let status, let headers, let body):
            return HTTPResult(data: body, metadata: .init(statusCode: status, headers: headers))
        }
    }
}

private actor SleepRecorder {
    private(set) var delays: [Duration] = []
    func sleep(_ duration: Duration) { delays.append(duration) }
}

@Suite("Client unit tests")
struct ClientTests {
    private let url = URL(string: "https://example.com")!

    @Test func usesDeterministicExponentialBackoff() async throws {
        let transport = StubTransport([.response(503), .connectionFailure, .response(200)])
        let sleeps = SleepRecorder()
        let client = try TypeSafeClient(
            apiKey: "test", baseURL: url, transport: transport,
            runtime: RetryRuntime(sleep: { await sleeps.sleep($0) }, random: { 1 })
        )
        _ = try await client.models.list()
        #expect(await sleeps.delays == [.milliseconds(375), .milliseconds(750)])
        let requests = await transport.requests
        #expect(requests.count == 3)
        #expect(requests.last?.value(forHTTPHeaderField: "X-TypeSafe-Retry-Count") == "2")
    }

    @Test func passesServerDelayToSleeper() async throws {
        let transport = StubTransport([.response(429, ["retry-after-ms": "1250"]), .response(200)])
        let sleeps = SleepRecorder()
        let client = try TypeSafeClient(
            apiKey: "test", baseURL: url, transport: transport,
            runtime: RetryRuntime(sleep: { await sleeps.sleep($0) })
        )
        _ = try await client.models.list()
        #expect(await sleeps.delays == [.milliseconds(1250)])
    }

    @Test func rejectsInvalidQuestionsBeforeNetworking() async throws {
        let transport = StubTransport([])
        let client = try TypeSafeClient(apiKey: "test", baseURL: url, transport: transport)
        for questions: [String: Question] in [[:], ["score": .score(criteria: ["Only one"])]] {
            do {
                _ = try await client.systemOne(state: "test", questions: questions)
                Issue.record("Expected invalid request")
            } catch TypeSafeError.invalidRequest {}
        }
        #expect(await transport.requests.isEmpty)
    }

    @Test func rejectsInvalidConfiguration() throws {
        #expect(throws: TypeSafeError.self) { try TypeSafeClient(apiKey: " ") }
        #expect(throws: TypeSafeError.self) { try TypeSafeClient(apiKey: "key\r\nInjected: true") }
        #expect(throws: TypeSafeError.self) { try TypeSafeClient(apiKey: "test", timeout: .zero) }
        #expect(throws: TypeSafeError.self) { try TypeSafeClient(apiKey: "test", retry: .init(maxRetries: -1)) }
        #expect(throws: TypeSafeError.self) {
            try TypeSafeClient(apiKey: "test", baseURL: #require(URL(string: "http://example.com")))
        }
    }

    @Test func rejectsInvalidPerCallOptionsWithoutNetworking() async throws {
        let transport = StubTransport([])
        let client = try TypeSafeClient(apiKey: "test", baseURL: url, transport: transport)
        do {
            _ = try await client.models.list(options: .init(timeout: .zero))
            Issue.record("Expected configuration error")
        } catch TypeSafeError.invalidConfiguration {}
        do {
            _ = try await client.models.list(options: .init(headers: ["X-Test": "a\r\nb"]))
            Issue.record("Expected header validation error")
        } catch TypeSafeError.invalidRequest {}
        #expect(await transport.requests.isEmpty)
    }

    @Test func preservesOmissionVersusExplicitNull() throws {
        let questions: [String: Question] = [
            "omitted": .noul(),
            "null": .noul(instructions: .null, yes: .null),
        ]
        let value = try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(questions))
        #expect(value == .object([
            "omitted": .object(["type": .string("noul")]),
            "null": .object(["type": .string("noul"), "instructions": .null, "criteria": .object(["true": .null])]),
        ]))
    }

    @Test func rejectsMismatchedAnswer() async throws {
        let body = Data("{\"model\":\"test\",\"answers\":{\"q\":{\"type\":\"noul\",\"noul\":0.5}},\"usage\":{\"input_tokens\":1,\"output_tokens\":1}}".utf8)
        let transport = StubTransport([.response(200, [:], body)])
        let client = try TypeSafeClient(apiKey: "test", baseURL: url, transport: transport)
        do {
            _ = try await client.systemOne(state: "test", questions: ["q": .choice(criteria: ["a": .null])])
            Issue.record("Expected answer mismatch")
        } catch TypeSafeError.invalidResponse {}
        #expect(await transport.requests.count == 1)
    }
}

@Suite("Retry policy")
struct RetryPolicyTests {
    @Test func capsBackoffAndAppliesJitter() {
        let policy = RetryPolicy()
        #expect(policy.delay(attempt: 0, headers: [:], random: 0, now: Date()) == .milliseconds(500))
        #expect(policy.delay(attempt: 1, headers: [:], random: 1, now: Date()) == .milliseconds(750))
        #expect(policy.delay(attempt: 100, headers: [:], random: 0, now: Date()) == .seconds(5))
    }

    @Test func parsesServerDelays() {
        let now = Date(timeIntervalSince1970: 0)
        let policy = RetryPolicy()
        #expect(policy.delay(attempt: 0, headers: ["retry-after": "2"], random: 0, now: now) == .seconds(2))
        #expect(policy.delay(attempt: 0, headers: ["retry-after": "Thu, 01 Jan 1970 00:00:03 GMT"], random: 0, now: now) == .seconds(3))
        #expect(policy.delay(attempt: 0, headers: ["retry-after-ms": "100", "retry-after": "2"], random: 0, now: now) == .milliseconds(100))
    }

    @Test(arguments: ["garbage", "-1", "nan", "inf", "61"])
    func fallsBackForInvalidOrExcessiveServerDelays(value: String) {
        #expect(RetryPolicy().delay(attempt: 0, headers: ["retry-after": value], random: 0, now: Date()) == .milliseconds(500))
    }

    @Test func canIgnoreServerDelays() {
        let policy = RetryPolicy(respectRetryAfter: false)
        #expect(policy.delay(attempt: 0, headers: ["retry-after": "30"], random: 0, now: Date()) == .milliseconds(500))
    }
}
