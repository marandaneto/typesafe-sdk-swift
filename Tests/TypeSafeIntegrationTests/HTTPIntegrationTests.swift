import Foundation
import Testing
import TypeSafe

@Suite("Loopback HTTP integration", .timeLimit(.minutes(1)))
struct HTTPIntegrationTests {
    private static let models = Data("{\"models\":[{\"name\":\"jev-latest\",\"description\":\"Test model\",\"release_date\":\"2026-09-15\"}]}".utf8)
    private var fastRetry: RetryPolicy {
        RetryPolicy(maxRetries: 2, initialDelay: .milliseconds(1), maximumDelay: .milliseconds(2), jitter: 0)
    }

    @Test func sendsRealPOSTAndDecodesAllAnswerTypes() async throws {
        let fixture = try Data(contentsOf: #require(Bundle.module.url(forResource: "system-one", withExtension: "json")))
        try await withServer([.http(200, headers: ["X-TypeSafe-Request-ID": "request-123"], body: fixture)]) { server, url in
            let client = try TypeSafeClient(apiKey: "test-only", baseURL: url.appendingPathComponent("proxy"))
            let response = try await client.systemOne(
                state: .object(["document": .string("I was charged twice.")]),
                questions: [
                    "category": .choice(instructions: "Category?", criteria: ["billing": .null, "technical": .null]),
                    "urgent": .noul(instructions: "Urgent?"),
                    "priority": .score(criteria: ["Can wait", "Needs attention", "Urgent"]),
                ],
                options: .init(headers: ["authorization": "must-not-override", "X-Custom": "example"])
            )
            #expect(response.value.model == "jev-latest")
            #expect(response.rawBody == fixture)
            #expect(response.value.usage.inputTokens == 120)
            #expect(response.metadata.requestID == "request-123")
            guard case .score(let score) = response.value.answers["priority"],
                  case .choice(let choice) = response.value.answers["category"],
                  case .noul(let noul) = response.value.answers["urgent"] else {
                Issue.record("Expected all three answer variants")
                return
            }
            #expect(score.score == 1.7)
            #expect(score.legend[2] == .string("Urgent"))
            #expect(choice.choice == "billing")
            #expect(noul.noul == 0.85)
            let request = try #require(await server.requests().first)
            #expect(request.method == "POST")
            #expect(request.path == "/proxy/v1/systemone")
            #expect(request.headers["authorization"] == "Bearer test-only")
            #expect(request.headers["x-custom"] == "example")
            #expect(request.headers["content-type"] == "application/json")
            let body = try JSONDecoder().decode(JSONValue.self, from: request.body)
            guard case .object(let fields) = body else { Issue.record("Expected request object"); return }
            #expect(fields["model"] == .string("jev-latest"))
            #expect(fields["state"] == .object(["document": .string("I was charged twice.")]))
        }
    }

    @Test func typedHandlesWorkOverURLSession() async throws {
        enum Category: String, CaseIterable, Sendable { case billing, technical }
        let category = ChoiceQuestion<Category>(id: "category")
        let urgent = NoulQuestion(id: "urgent")
        let priority = ScoreQuestion(id: "priority", criteria: ["Can wait", "Needs attention", "Urgent"])
        let fixture = try Data(contentsOf: #require(Bundle.module.url(forResource: "system-one", withExtension: "json")))
        try await withServer([.http(200, body: fixture)]) { server, url in
            let client = try TypeSafeClient(apiKey: "test", baseURL: url)
            let response = try await client.systemOne(state: "I was charged twice.", questions: [
                category.eraseToAnyQuestion(), urgent.eraseToAnyQuestion(), priority.eraseToAnyQuestion(),
            ])
            #expect(try response.answer(for: category).choice == .billing)
            #expect(try response.answer(for: urgent).noul == 0.85)
            #expect(try response.answer(for: priority).score == 1.7)
            #expect(await server.requests().count == 1)
        }
    }

    @Test(arguments: [408, 429, 500, 503])
    func retriesEligibleStatuses(status: Int) async throws {
        try await withServer([
            .http(status, headers: ["retry-after-ms": "1"], body: Data("{}".utf8)),
            .http(200, body: Self.models),
        ]) { server, url in
            let client = try TypeSafeClient(apiKey: "test", baseURL: url, retry: fastRetry)
            let response = try await client.models.list()
            #expect(response.value.models.first?.name == "jev-latest")
            let requests = await server.requests()
            #expect(requests.count == 2)
            #expect(requests[0].headers["x-typesafe-retry-count"] == nil)
            #expect(requests[1].headers["x-typesafe-retry-count"] == "1")
            #expect(requests.allSatisfy { $0.method == "GET" && $0.path == "/v1/models" })
        }
    }

    @Test(arguments: [400, 401, 403, 404, 422])
    func doesNotRetryClientErrors(status: Int) async throws {
        try await withServer([.http(status, headers: ["X-TypeSafe-Request-ID": "failed"], body: Data("denied".utf8))]) { server, url in
            let client = try TypeSafeClient(apiKey: "test", baseURL: url, retry: fastRetry)
            do {
                _ = try await client.models.list()
                Issue.record("Expected an HTTP error")
            } catch TypeSafeError.http(let actual, let body, let metadata) {
                #expect(actual == status)
                #expect(body == Data("denied".utf8))
                #expect(metadata.requestID == "failed")
            }
            #expect(await server.requests().count == 1)
        }
    }

    @Test func stopsAtRetryLimit() async throws {
        try await withServer(Array(repeating: .http(503, body: Data()), count: 3)) { server, url in
            let client = try TypeSafeClient(apiKey: "test", baseURL: url, retry: fastRetry)
            do {
                _ = try await client.models.list()
                Issue.record("Expected retry exhaustion")
            } catch TypeSafeError.http(let status, _, _) { #expect(status == 503) }
            #expect(await server.requests().count == 3)
        }
    }

    @Test func perCallCanDisableRetries() async throws {
        try await withServer([.http(503, body: Data())]) { server, url in
            let client = try TypeSafeClient(apiKey: "test", baseURL: url)
            do {
                _ = try await client.models.list(options: .init(retry: .init(maxRetries: 0)))
                Issue.record("Expected an HTTP error")
            } catch TypeSafeError.http(let status, _, _) { #expect(status == 503) }
            #expect(await server.requests().count == 1)
        }
    }

    @Test(arguments: ["not JSON", "{}", "{\"models\":42}"])
    func doesNotRetryInvalidResponses(body: String) async throws {
        try await withServer([.http(200, body: Data(body.utf8))]) { server, url in
            let client = try TypeSafeClient(apiKey: "test", baseURL: url, retry: fastRetry)
            do {
                _ = try await client.models.list()
                Issue.record("Expected invalid response")
            } catch TypeSafeError.invalidResponse {}
            #expect(await server.requests().count == 1)
        }
    }

    @Test func timeoutIncludesResponseBody() async throws {
        try await withServer([.http(200, body: Self.models, bodyDelay: 10_000_000_000)]) { server, url in
            let client = try TypeSafeClient(apiKey: "test", baseURL: url, timeout: .seconds(2), retry: .init(maxRetries: 0))
            do {
                _ = try await client.models.list()
                Issue.record("Expected timeout before response body")
            } catch TypeSafeError.timeout {}
            #expect(await server.requests().count == 1)
        }
    }

    @Test func totalDeadlineInterruptsServerDirectedBackoff() async throws {
        try await withServer([.http(429, headers: ["Retry-After": "60"], body: Data())]) { server, url in
            let client = try TypeSafeClient(apiKey: "test", baseURL: url)
            do {
                _ = try await client.models.list(options: .init(totalTimeout: .seconds(2)))
                Issue.record("Expected total deadline")
            } catch TypeSafeError.deadlineExceeded {}
            #expect(await server.requests().count == 1)
        }
    }

    @Test func totalDeadlineCancelsAnActiveResponseBody() async throws {
        try await withServer([.http(200, body: Self.models, bodyDelay: 10_000_000_000)]) { server, url in
            let client = try TypeSafeClient(apiKey: "test", baseURL: url, totalTimeout: .seconds(2))
            do { _ = try await client.models.list(); Issue.record("Expected total deadline") }
            catch TypeSafeError.deadlineExceeded {}
            #expect(await server.requests().count == 1)
        }
    }

    @Test func retriesTimeout() async throws {
        let fixture = try Data(contentsOf: #require(Bundle.module.url(forResource: "system-one", withExtension: "json")))
        try await withServer([.stall, .http(200, body: fixture)]) { server, url in
            let client = try TypeSafeClient(apiKey: "test", baseURL: url, timeout: .seconds(3), retry: fastRetry)
            _ = try await client.systemOne(state: "test", questions: ["urgent": .noul()])
            let requests = await server.requests()
            #expect(requests.count == 2)
            #expect(requests.last?.headers["x-typesafe-retry-count"] == "1")
        }
    }

    @Test func retriesInterruptedResponseBody() async throws {
        let fixture = try Data(contentsOf: #require(Bundle.module.url(forResource: "system-one", withExtension: "json")))
        try await withServer([.truncatedBody, .http(200, body: fixture)]) { server, url in
            let client = try TypeSafeClient(apiKey: "test", baseURL: url, retry: fastRetry)
            let response = try await client.systemOne(state: "test", questions: ["urgent": .noul()])
            #expect(response.value.model == "jev-latest")
            let requests = await server.requests()
            #expect(requests.count == 2)
            #expect(requests.last?.headers["x-typesafe-retry-count"] == "1")
        }
    }

    @Test func cancellationStopsActiveRequest() async throws {
        try await withServer([.stall]) { server, url in
            let client = try TypeSafeClient(apiKey: "test", baseURL: url, retry: fastRetry)
            let task = Task { try await client.models.list() }
            defer { task.cancel() }
            try await server.waitForRequests(1)
            task.cancel()
            do { _ = try await task.value; Issue.record("Expected cancellation") }
            catch is CancellationError {}
            #expect(await server.requests().count == 1)
        }
    }

    @Test func cancellationStopsBackoff() async throws {
        try await withServer([.http(429, headers: ["Retry-After": "60"], body: Data())]) { server, url in
            let client = try TypeSafeClient(apiKey: "test", baseURL: url)
            let task = Task { try await client.models.list() }
            defer { task.cancel() }
            try await server.waitForRequests(1)
            try await Task.sleep(nanoseconds: 100_000_000)
            task.cancel()
            do { _ = try await task.value; Issue.record("Expected cancellation") }
            catch is CancellationError {}
            #expect(await server.requests().count == 1)
        }
    }

    @Test func refusesRedirects() async throws {
        try await withServer([.http(302, headers: ["Location": "https://example.com/credential-leak"], body: Data())]) { server, url in
            let client = try TypeSafeClient(apiKey: "test", baseURL: url)
            do { _ = try await client.models.list(); Issue.record("Expected redirect error") }
            catch TypeSafeError.http(let status, _, _) { #expect(status == 302) }
            #expect(await server.requests().count == 1)
        }
    }

    @Test func oneSuspendedRequestDoesNotBlockAnother() async throws {
        try await withServer([.stall, .http(200, body: Self.models)]) { server, url in
            let client = try TypeSafeClient(apiKey: "test", baseURL: url, retry: .init(maxRetries: 0))
            let first = Task { try await client.models.list() }
            defer { first.cancel() }
            try await server.waitForRequests(1)
            let second = try await client.models.list(options: .init(timeout: .seconds(2)))
            #expect(second.value.models.count == 1)
            first.cancel()
            do { _ = try await first.value; Issue.record("Expected cancellation") }
            catch is CancellationError {}
            #expect(await server.requests().count == 2)
        }
    }

    @Test func concurrentCallsKeepHeadersIsolated() async throws {
        try await withServer(Array(repeating: .http(200, body: Self.models, bodyDelay: 100_000_000), count: 10)) { server, url in
            let client = try TypeSafeClient(apiKey: "test", baseURL: url)
            try await withThrowingTaskGroup(of: Void.self) { group in
                for index in 0..<10 {
                    group.addTask {
                        let response = try await client.models.list(options: .init(headers: ["X-Call": String(index)]))
                        #expect(response.value.models.count == 1)
                    }
                }
                try await group.waitForAll()
            }
            let requests = await server.requests()
            #expect(requests.count == 10)
            #expect(Set(requests.compactMap { $0.headers["x-call"] }) == Set((0..<10).map(String.init)))
            #expect(requests.allSatisfy { $0.headers["x-typesafe-retry-count"] == nil })
        }
    }
}
