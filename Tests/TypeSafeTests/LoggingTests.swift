import Foundation
import os
import Testing
@testable import TypeSafe

private final class LogRecorder: Sendable {
    private let storage = OSAllocatedUnfairLock(initialState: [LogEvent]())
    func record(_ event: LogEvent) { storage.withLock { $0.append(event) } }
    var events: [LogEvent] { storage.withLock { $0 } }
}

@Suite("Logging and diagnostics")
struct LoggingTests {
    @Test func bodiesAreOmittedEvenAtDebugUnlessExplicitlyEnabled() async throws {
        let recorder = LogRecorder()
        let client = try TypeSafeClient(
            apiKey: "private-api-key", baseURL: #require(URL(string: "https://example.com")),
            logging: .init(minimumLevel: .debug, handler: recorder.record),
            transport: StubTransport([.response(200)])
        )
        _ = try await client.models.list(options: .init(headers: ["X-Custom-Secret": "private-custom-value"]))
        #expect(recorder.events.count == 2)
        #expect(recorder.events.allSatisfy { $0.body == nil })
        let request = try #require(recorder.events.first)
        #expect(request.headers["authorization"] == "<redacted>")
        #expect(request.headers["x-custom-secret"] == "<redacted>")
    }

    @Test func optInBodiesRedactCredentialsAndSensitiveFields() async throws {
        let recorder = LogRecorder()
        let body = Data(#"{"model":"test","answers":{"q":{"type":"noul","noul":0.5}},"usage":{"input_tokens":1,"output_tokens":1},"nested":{"password":"hidden-password","access_token":"hidden-token","text":"private-api-key private-header-value"}}"#.utf8)
        let client = try TypeSafeClient(
            apiKey: "private-api-key", baseURL: #require(URL(string: "https://example.com")),
            logging: .init(minimumLevel: .debug, includeBodies: true, handler: recorder.record),
            transport: StubTransport([.response(200, ["set-cookie": "hidden-cookie"], body)])
        )
        _ = try await client.systemOne(
            state: .object(["api_key": .string("hidden-key"), "text": .string("private-api-key")]),
            questions: ["q": .noul()], options: .init(headers: ["X-Credential": "private-header-value"])
        )
        for event in recorder.events {
            let logged = String(decoding: try JSONEncoder().encode(event.body), as: UTF8.self)
            for secret in ["private-api-key", "private-header-value", "hidden-key", "hidden-password", "hidden-token"] {
                #expect(!logged.contains(secret))
            }
        }
        #expect(recorder.events.last?.headers["set-cookie"] == "<redacted>")
    }

    @Test func retriesShareAnOperationIDAndRespectLevelFiltering() async throws {
        let recorder = LogRecorder()
        let client = try TypeSafeClient(
            apiKey: "test", baseURL: #require(URL(string: "https://example.com")),
            logging: .init(minimumLevel: .warning, handler: recorder.record),
            transport: StubTransport([.response(503), .response(200)]),
            runtime: RetryRuntime(sleep: { _ in })
        )
        _ = try await client.models.list()
        #expect(recorder.events.count == 1)
        #expect(recorder.events.first?.kind == .retry)
    }

    @Test func concurrentOperationsHaveDifferentIDs() async throws {
        let recorder = LogRecorder()
        let client = try TypeSafeClient(
            apiKey: "test", baseURL: #require(URL(string: "https://example.com")),
            logging: .init(minimumLevel: .debug, handler: recorder.record),
            transport: StubTransport([.response(200), .response(200)])
        )
        async let first = client.models.list()
        async let second = client.models.list()
        _ = try await (first, second)
        let requests = recorder.events.filter { $0.kind == .request }
        #expect(Set(requests.map(\.operationID)).count == 2)
        for request in requests {
            #expect(recorder.events.filter { $0.operationID == request.operationID }.count == 2)
        }
    }

    @Test func decodingErrorsPreserveResponseAndFieldPath() async throws {
        let body = Data(#"{"models":[{"description":"test","release_date":"2026-09-18"}]}"#.utf8)
        let client = try TypeSafeClient(apiKey: "test", baseURL: #require(URL(string: "https://example.com")), transport: StubTransport([.response(200, ["x-typesafe-request-id": "request-123"], body)]))
        do { _ = try await client.models.list(); Issue.record("Expected a decoding error") }
        catch TypeSafeError.invalidResponse(_, let details) {
            let details = try #require(details)
            #expect(details.body == body)
            #expect(details.metadata.requestID == "request-123")
            #expect(details.fieldPath.first == "models")
            #expect(details.fieldPath.last == "name")
        }
    }

    @Test func semanticErrorsPreserveResponseDetails() async throws {
        let body = Data(#"{"model":"test","answers":{"other":{"type":"noul","noul":0.5}},"usage":{"input_tokens":1,"output_tokens":1}}"#.utf8)
        let client = try TypeSafeClient(apiKey: "test", baseURL: #require(URL(string: "https://example.com")), transport: StubTransport([.response(200, [:], body)]))
        do { _ = try await client.systemOne(state: "test", questions: ["q": .noul()]); Issue.record("Expected missing answer") }
        catch TypeSafeError.invalidResponse(_, let details) {
            #expect(details?.body == body)
            #expect(details?.fieldPath == ["answers", "q"])
        }
    }
}
