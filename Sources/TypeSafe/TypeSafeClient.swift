import Foundation

public struct RequestOptions: Sendable {
    public var timeout: Duration?
    public var retry: RetryPolicy?
    public var headers: [String: String]

    public init(timeout: Duration? = nil, retry: RetryPolicy? = nil, headers: [String: String] = [:]) {
        self.timeout = timeout
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
    private let retry: RetryPolicy
    private let transport: any HTTPTransport
    private let runtime: RetryRuntime

    public init(
        apiKey: String,
        baseURL: URL = URL(string: "https://api.typesafe.ai")!,
        defaultModel: String = "jev-latest",
        timeout: Duration = .seconds(10),
        retry: RetryPolicy = RetryPolicy()
    ) throws {
        try self.init(apiKey: apiKey, baseURL: baseURL, defaultModel: defaultModel, timeout: timeout,
                      retry: retry, transport: URLSessionTransport(), runtime: RetryRuntime())
    }

    init(
        apiKey: String, baseURL: URL, defaultModel: String = "jev-latest",
        timeout: Duration = .seconds(10), retry: RetryPolicy = RetryPolicy(),
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
        try retry.validate()
        self.apiKey = apiKey
        self.baseURL = baseURL
        self.defaultModel = defaultModel
        self.timeout = timeout
        self.retry = retry
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
        state: Content, questions: [String: Question], model: String? = nil,
        options: RequestOptions = RequestOptions()
    ) async throws -> APIResponse<SystemOneResponse> {
        try Task.checkCancellation()
        guard !questions.isEmpty else { throw TypeSafeError.invalidRequest("Questions must not be empty") }
        for (name, question) in questions {
            if case .score(_, let criteria) = question, criteria.count < 2 {
                throw TypeSafeError.invalidRequest("Score question '\(name)' requires at least two criteria")
            }
        }
        struct Body: Encodable {
            let state: Content
            let questions: [String: Question]
            let model: String
        }
        let body = try JSONEncoder().encode(Body(state: state, questions: questions, model: model ?? defaultModel))
        let response: APIResponse<SystemOneResponse> = try await request(path: "v1/systemone", body: body, options: options)
        for (name, question) in questions {
            switch (question, response.value.answers[name]) {
            case (.noul, .noul), (.score, .score): break
            case (.choice(_, let criteria), .choice(let answer)) where criteria[answer.choice] != nil: break
            default: throw TypeSafeError.invalidResponse("Missing or mismatched answer for '\(name)'")
            }
        }
        return response
    }

    private func request<Value: Decodable & Sendable>(
        path: String, body: Data?, options: RequestOptions
    ) async throws -> APIResponse<Value> {
        let policy = options.retry ?? retry
        let timeout = options.timeout ?? timeout
        try policy.validate()
        try Self.validateTimeout(timeout)
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = body == nil ? "GET" : "POST"
        request.httpBody = body
        request.timeoutInterval = 86_400
        let protected: Set<String> = ["authorization", "accept", "content-type", "content-length", "host", "user-agent", "x-typesafe-sdk", "x-typesafe-retry-count"]
        for (name, value) in options.headers {
            guard !name.isEmpty, name.utf8.allSatisfy({ (33...126).contains($0) && !"()<>@,;:\\\"/[]?={} ".utf8.contains($0) }),
                  !value.utf8.contains(13), !value.utf8.contains(10) else {
                throw TypeSafeError.invalidRequest("Invalid HTTP header")
            }
            if !protected.contains(name.lowercased()) { request.setValue(value, forHTTPHeaderField: name) }
        }
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("typesafe-swift/0.1.0-dev", forHTTPHeaderField: "X-TypeSafe-SDK")
        request.setValue("typesafe-swift/0.1.0-dev", forHTTPHeaderField: "User-Agent")
        if body != nil { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }

        for attempt in 0...policy.maxRetries {
            try Task.checkCancellation()
            request.setValue(attempt == 0 ? nil : String(attempt), forHTTPHeaderField: "X-TypeSafe-Retry-Count")
            let result: HTTPResult
            do {
                result = try await send(request, timeout: timeout)
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
                    try await runtime.sleep(policy.delay(attempt: attempt, headers: [:], random: runtime.random(), now: runtime.now()))
                    continue
                default: throw failure
                }
            }
            try Task.checkCancellation()
            if !(200...299).contains(result.metadata.statusCode) {
                if attempt < policy.maxRetries, policy.statuses.contains(result.metadata.statusCode) {
                    try await runtime.sleep(policy.delay(attempt: attempt, headers: result.metadata.headers, random: runtime.random(), now: runtime.now()))
                    continue
                }
                throw TypeSafeError.http(statusCode: result.metadata.statusCode, body: result.data, metadata: result.metadata)
            }
            do {
                let value = try JSONDecoder().decode(Value.self, from: result.data)
                try Task.checkCancellation()
                return APIResponse(value: value, metadata: result.metadata, rawBody: result.data)
            } catch is DecodingError {
                throw TypeSafeError.invalidResponse("Response does not match the expected schema")
            }
        }
        throw TypeSafeError.invalidResponse("Retry loop exhausted")
    }

    private func send(_ request: URLRequest, timeout: Duration) async throws -> HTTPResult {
        try await withThrowingTaskGroup(of: HTTPResult.self) { group in
            group.addTask { try await transport.send(request) }
            group.addTask {
                try await timeout.sleep()
                throw TypeSafeError.timeout
            }
            defer { group.cancelAll() }
            guard let result = try await group.next() else { throw CancellationError() }
            return result
        }
    }

    private static func validateTimeout(_ timeout: Duration) throws {
        guard timeout > .zero, timeout <= .seconds(86_400) else {
            throw TypeSafeError.invalidConfiguration("Timeout must be positive and no greater than one day")
        }
    }
}
