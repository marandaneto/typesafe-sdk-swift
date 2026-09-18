import Foundation
import Testing
@testable import TypeSafe

private actor SuspensionGate {
    enum Point: Hashable, Sendable { case network, attempt, total, backoff }
    private var pending: [UUID: (Point, CheckedContinuation<Void, any Error>)] = [:]
    private var started: Set<Point> = []
    private var observers: [Point: [CheckedContinuation<Void, Never>]] = [:]

    func wait(_ point: Point) async throws {
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                if Task.isCancelled { continuation.resume(throwing: CancellationError()); return }
                pending[id] = (point, continuation)
                started.insert(point)
                for observer in observers.removeValue(forKey: point) ?? [] { observer.resume() }
            }
        } onCancel: {
            Task { await self.cancel(id) }
        }
    }

    func waitUntilStarted(_ point: Point) async {
        if started.contains(point) { return }
        await withCheckedContinuation { observers[point, default: []].append($0) }
    }

    func release(_ point: Point) {
        let ids = pending.filter { $0.value.0 == point }.map(\.key)
        for id in ids { pending.removeValue(forKey: id)?.1.resume() }
    }

    private func cancel(_ id: UUID) { pending.removeValue(forKey: id)?.1.resume(throwing: CancellationError()) }
    var pendingCount: Int { pending.count }
}

private actor SuspendedTransport: HTTPTransport {
    let gate: SuspensionGate
    private(set) var calls = 0
    init(_ gate: SuspensionGate) { self.gate = gate }
    func send(_ request: URLRequest) async throws -> HTTPResult {
        calls += 1
        try await gate.wait(.network)
        return HTTPResult(data: Data(#"{"models":[]}"#.utf8), metadata: .init(statusCode: 200, headers: [:]))
    }
}

@Suite("Deadline and cancellation races", .timeLimit(.minutes(1)))
struct DeadlineTests {
    private func runtime(_ gate: SuspensionGate) -> RetryRuntime {
        RetryRuntime(
            waitForTimeout: { _, kind in try await gate.wait(kind == .attempt ? .attempt : .total) },
            sleep: { _ in try await gate.wait(.backoff) }, random: { 0 }
        )
    }

    @Test func successfulRequestDrainsBothTimers() async throws {
        let gate = SuspensionGate()
        let transport = SuspendedTransport(gate)
        let client = try TypeSafeClient(apiKey: "test", baseURL: #require(URL(string: "https://example.com")), totalTimeout: .seconds(30), transport: transport, runtime: runtime(gate))
        let task = Task { try await client.models.list() }
        defer { task.cancel() }
        await gate.waitUntilStarted(.attempt)
        await gate.waitUntilStarted(.total)
        await gate.waitUntilStarted(.network)
        await gate.release(.network)
        let response = try await task.value
        #expect(response.value.models.isEmpty)
        #expect(await gate.pendingCount == 0)
    }

    @Test func attemptTimeoutCancelsNetworkingWithoutRetryWhenDisabled() async throws {
        let gate = SuspensionGate()
        let transport = SuspendedTransport(gate)
        let client = try TypeSafeClient(apiKey: "test", baseURL: #require(URL(string: "https://example.com")), retry: .init(maxRetries: 0), transport: transport, runtime: runtime(gate))
        let task = Task { try await client.models.list() }
        defer { task.cancel() }
        await gate.waitUntilStarted(.network)
        await gate.waitUntilStarted(.attempt)
        await gate.release(.attempt)
        do { _ = try await task.value; Issue.record("Expected attempt timeout") }
        catch TypeSafeError.timeout {}
        #expect(await gate.pendingCount == 0)
        #expect(await transport.calls == 1)
    }

    @Test func totalDeadlineCancelsBackoffAndPreventsAnotherAttempt() async throws {
        let gate = SuspensionGate()
        let transport = StubTransport([.response(429), .response(200)])
        let client = try TypeSafeClient(apiKey: "test", baseURL: #require(URL(string: "https://example.com")), totalTimeout: .seconds(30), transport: transport, runtime: runtime(gate))
        let task = Task { try await client.models.list() }
        defer { task.cancel() }
        await gate.waitUntilStarted(.total)
        await gate.waitUntilStarted(.backoff)
        await gate.release(.total)
        do { _ = try await task.value; Issue.record("Expected total deadline") }
        catch TypeSafeError.deadlineExceeded {}
        #expect(await gate.pendingCount == 0)
        #expect(await transport.requests.count == 1)
    }

    @Test func callerCancellationWinsOverReadyTimers() async throws {
        let gate = SuspensionGate()
        let transport = SuspendedTransport(gate)
        let client = try TypeSafeClient(apiKey: "test", baseURL: #require(URL(string: "https://example.com")), totalTimeout: .seconds(30), transport: transport, runtime: runtime(gate))
        let task = Task { try await client.models.list() }
        defer { task.cancel() }
        await gate.waitUntilStarted(.network)
        await gate.waitUntilStarted(.attempt)
        await gate.waitUntilStarted(.total)
        task.cancel()
        await gate.release(.attempt)
        await gate.release(.total)
        do { _ = try await task.value; Issue.record("Expected cancellation") }
        catch is CancellationError {}
        #expect(await gate.pendingCount == 0)
        #expect(await transport.calls == 1)
    }

    @Test func cancellationBeforeCallDoesNotStartNetworking() async throws {
        let transport = StubTransport([])
        let client = try TypeSafeClient(apiKey: "test", baseURL: #require(URL(string: "https://example.com")), transport: transport)
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await client.models.list()
        }
        do { _ = try await task.value; Issue.record("Expected cancellation") }
        catch is CancellationError {}
        #expect(await transport.requests.isEmpty)
    }

    @Test func rejectsInvalidTotalDeadline() throws {
        #expect(throws: TypeSafeError.self) { try TypeSafeClient(apiKey: "test", totalTimeout: .zero) }
    }
}
