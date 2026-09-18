import Foundation

public struct RequestOptions: Sendable {
    public var timeout: Duration?
    public var totalTimeout: Duration?
    public var retry: RetryPolicy?
    public var headers: [String: String]

    public init(timeout: Duration? = nil, totalTimeout: Duration? = nil, retry: RetryPolicy? = nil, headers: [String: String] = [:]) {
        self.timeout = timeout
        self.totalTimeout = totalTimeout
        self.retry = retry
        self.headers = headers
    }
}

public struct TypeSafeClient: Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    public var description: String { "TypeSafeClient(apiKey: <redacted>)" }
    public var debugDescription: String { description }
    private let apiKey: String
    private let baseURL: URL
    private let defaultModel: String
    private let timeout: Duration
    private let totalTimeout: Duration?
    private let retry: RetryPolicy
    private let logging: LoggingOptions?
    private let transport: any HTTPTransport
    private let runtime: RetryRuntime

    public init(
        apiKey: String,
        baseURL: URL = URL(string: "https://api.typesafe.ai")!,
        defaultModel: String = "jev-latest",
        timeout: Duration = .seconds(10),
        totalTimeout: Duration? = nil,
        retry: RetryPolicy = RetryPolicy(),
        logging: LoggingOptions? = nil
    ) throws {
        try self.init(apiKey: apiKey, baseURL: baseURL, defaultModel: defaultModel, timeout: timeout,
                      totalTimeout: totalTimeout, retry: retry, logging: logging,
                      transport: URLSessionTransport(), runtime: RetryRuntime())
    }

    init(
        apiKey: String, baseURL: URL, defaultModel: String = "jev-latest",
        timeout: Duration = .seconds(10), totalTimeout: Duration? = nil,
        retry: RetryPolicy = RetryPolicy(), logging: LoggingOptions? = nil,
        transport: any HTTPTransport, runtime: RetryRuntime = RetryRuntime()
    ) throws {
        guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !apiKey.utf8.contains(13), !apiKey.utf8.contains(10),
              !defaultModel.isEmpty else {
            throw TypeSafeError.invalidConfiguration("API key and model must be nonempty and credentials must not contain newlines")
        }
        guard let scheme = baseURL.scheme, ["https", "http"].contains(scheme),
              baseURL.host != nil, baseURL.user == nil, baseURL.password == nil,
              baseURL.query == nil, baseURL.fragment == nil,
              scheme == "https" || ["localhost", "127.0.0.1", "[::1]"].contains(baseURL.host) else {
            throw TypeSafeError.invalidConfiguration("Use HTTPS, or HTTP on loopback for local testing")
        }
        try Self.validateTimeout(timeout)
        if let totalTimeout { try Self.validateTimeout(totalTimeout) }
        try retry.validate()
        self.apiKey = apiKey
        self.baseURL = baseURL
        self.defaultModel = defaultModel
        self.timeout = timeout
        self.totalTimeout = totalTimeout
        self.retry = retry
        self.logging = logging
        self.transport = transport
        self.runtime = runtime
    }

    public var models: Models { Models(client: self) }

    public struct Models: Sendable {
        fileprivate let client: TypeSafeClient

        public func list(options: RequestOptions = RequestOptions()) async throws -> APIResponse<ModelsResponse> {
            try await client.request(path: "v1/models", body: nil, options: options)
        }
    }

    public func systemOne(
        state: Content, questions: [AnyQuestion], model: String? = nil,
        options: RequestOptions = RequestOptions()
    ) async throws -> APIResponse<SystemOneResponse> {
        try Task.checkCancellation()
        var named: [String: Question] = [:]
        for question in questions {
            guard named.updateValue(question.question, forKey: question.id) == nil else {
                throw TypeSafeError.invalidRequest("Duplicate question ID '\(question.id)'")
            }
        }
        return try await systemOne(state: state, questions: named, model: model, options: options)
    }

    public func systemOne(
        state: Content, questions: [String: Question], model: String? = nil,
        options: RequestOptions = RequestOptions()
    ) async throws -> APIResponse<SystemOneResponse> {
        try Task.checkCancellation()
        guard !questions.isEmpty else { throw TypeSafeError.invalidRequest("Questions must not be empty") }
        for (name, question) in questions { try question.validate(id: name) }
        struct Body: Encodable {
            let state: Content
            let questions: [String: Question]
            let model: String
        }
        let body = try JSONEncoder().encode(Body(state: state, questions: questions, model: model ?? defaultModel))
        let response: APIResponse<SystemOneResponse> = try await request(path: "v1/systemone", body: body, options: options)
        for (name, question) in questions {
            do {
                _ = try response.answer(for: AnyQuestion(id: name, question: question))
            } catch TypeSafeError.invalidResponse(let message, _) {
                throw TypeSafeError.invalidResponse(message, details: .init(
                    metadata: response.metadata, body: response.rawBody, fieldPath: ["answers", name]
                ))
            }
        }
        return response
    }

    private func request<Value: Decodable & Sendable>(
        path: String, body: Data?, options: RequestOptions
    ) async throws -> APIResponse<Value> {
        try Task.checkCancellation()
        let policy = options.retry ?? retry
        let timeout = options.timeout ?? timeout
        let total = options.totalTimeout ?? totalTimeout
        try policy.validate()
        try Self.validateTimeout(timeout)
        if let total { try Self.validateTimeout(total) }
        let request = try makeRequest(path: path, body: body, headers: options.headers)
        let operationID = UUID()
        let operation: @Sendable () async throws -> APIResponse<Value> = {
            try await perform(request, path: path, policy: policy, timeout: timeout, operationID: operationID)
        }
        do {
            if let total {
                return try await withTimeout(total, kind: .total, operation: operation)
            }
            return try await operation()
        } catch {
            emit(.failure, level: .error, request: request, path: path, operationID: operationID,
                 attempt: nil, message: Task.isCancelled || error is CancellationError ? "cancelled" : "request failed")
            if Task.isCancelled { throw CancellationError() }
            throw error
        }
    }

    private func makeRequest(path: String, body: Data?, headers: [String: String]) throws -> URLRequest {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = body == nil ? "GET" : "POST"
        request.httpBody = body
        request.timeoutInterval = 86_400
        let protected: Set<String> = ["authorization", "accept", "content-type", "content-length", "host", "user-agent", "x-typesafe-sdk", "x-typesafe-retry-count"]
        for (name, value) in headers {
            guard !name.isEmpty, name.utf8.allSatisfy({ (33...126).contains($0) && !"()<>@,;:\\\"/[]?={} ".utf8.contains($0) }),
                  !value.utf8.contains(13), !value.utf8.contains(10) else {
                throw TypeSafeError.invalidRequest("Invalid HTTP header")
            }
            if !protected.contains(name.lowercased()) { request.setValue(value, forHTTPHeaderField: name) }
        }
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("typesafe-swift/0.1.0", forHTTPHeaderField: "X-TypeSafe-SDK")
        request.setValue("typesafe-swift/0.1.0", forHTTPHeaderField: "User-Agent")
        if body != nil { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        return request
    }

    private func perform<Value: Decodable & Sendable>(
        _ original: URLRequest, path: String, policy: RetryPolicy, timeout: Duration, operationID: UUID
    ) async throws -> APIResponse<Value> {
        var request = original
        for attempt in 0...policy.maxRetries {
            try Task.checkCancellation()
            request.setValue(attempt == 0 ? nil : String(attempt), forHTTPHeaderField: "X-TypeSafe-Retry-Count")
            emit(.request, level: .debug, request: request, path: path, operationID: operationID, attempt: attempt)
            let result: HTTPResult
            do {
                let attemptRequest = request
                result = try await withTimeout(timeout, kind: .attempt) { try await transport.send(attemptRequest) }
            } catch {
                if Task.isCancelled || error is CancellationError { throw CancellationError() }
                let failure: TypeSafeError
                if let error = error as? URLError {
                    failure = error.code == .timedOut ? .timeout : .connection(code: error.errorCode)
                } else if let error = error as? TypeSafeError {
                    failure = error
                } else { throw error }
                switch failure {
                case .timeout, .connection:
                    if attempt >= policy.maxRetries { throw failure }
                    emit(.retry, level: .warning, request: request, path: path, operationID: operationID, attempt: attempt)
                    try await runtime.sleep(policy.delay(attempt: attempt, headers: [:], random: runtime.random(), now: runtime.now()))
                    continue
                default: throw failure
                }
            }
            try Task.checkCancellation()
            emit(.response, level: .info, request: request, path: path, operationID: operationID, attempt: attempt, result: result)
            if !(200...299).contains(result.metadata.statusCode) {
                if attempt < policy.maxRetries, policy.statuses.contains(result.metadata.statusCode) {
                    emit(.retry, level: .warning, request: request, path: path, operationID: operationID, attempt: attempt, result: result)
                    try await runtime.sleep(policy.delay(attempt: attempt, headers: result.metadata.headers, random: runtime.random(), now: runtime.now()))
                    continue
                }
                throw TypeSafeError.http(statusCode: result.metadata.statusCode, body: result.data, metadata: result.metadata)
            }
            do {
                let value = try JSONDecoder().decode(Value.self, from: result.data)
                try Task.checkCancellation()
                return APIResponse(value: value, metadata: result.metadata, rawBody: result.data)
            } catch let error as DecodingError {
                throw TypeSafeError.invalidResponse("Response does not match the expected schema", details: .init(
                    metadata: result.metadata, body: result.data, fieldPath: Self.fieldPath(error)
                ))
            }
        }
        throw TypeSafeError.invalidResponse("Retry loop exhausted")
    }

    private func withTimeout<Value: Sendable>(
        _ duration: Duration, kind: TimeoutKind, operation: @escaping @Sendable () async throws -> Value
    ) async throws -> Value {
        do {
            let result = try await withThrowingTaskGroup(of: Value.self) { group in
                group.addTask(operation: operation)
                group.addTask {
                    try await runtime.waitForTimeout(duration, kind)
                    try Task.checkCancellation()
                    throw kind == .attempt ? TypeSafeError.timeout : TypeSafeError.deadlineExceeded
                }
                defer { group.cancelAll() }
                guard let result = try await group.next() else { throw CancellationError() }
                return result
            }
            try Task.checkCancellation()
            return result
        } catch {
            if Task.isCancelled { throw CancellationError() }
            throw error
        }
    }

    private func emit(
        _ kind: LogEvent.Kind, level: LogLevel, request: URLRequest, path: String,
        operationID: UUID, attempt: Int?, result: HTTPResult? = nil, message: String? = nil
    ) {
        guard let logging, level >= logging.minimumLevel else { return }
        let redactor = LogRedactor(apiKey: apiKey, requestHeaders: request.allHTTPHeaderFields ?? [:])
        let headers = result?.metadata.headers ?? request.allHTTPHeaderFields ?? [:]
        let body = kind == .request ? request.httpBody : kind == .response ? result?.data : nil
        logging.handler(LogEvent(
            level: level, kind: kind, operationID: operationID, method: request.httpMethod ?? "GET",
            path: "/" + path, attempt: attempt, statusCode: result?.metadata.statusCode,
            headers: redactor.headers(headers), body: logging.includeBodies ? redactor.body(body) : nil, message: message
        ))
    }

    private static func fieldPath(_ error: DecodingError) -> [String] {
        switch error {
        case .keyNotFound(let key, let context): return context.codingPath.map(\.stringValue) + [key.stringValue]
        case .typeMismatch(_, let context), .valueNotFound(_, let context), .dataCorrupted(let context):
            return context.codingPath.map(\.stringValue)
        @unknown default: return []
        }
    }

    private static func validateTimeout(_ timeout: Duration) throws {
        guard timeout > .zero, timeout <= .seconds(86_400) else {
            throw TypeSafeError.invalidConfiguration("Timeout must be positive and no greater than one day")
        }
    }
}
