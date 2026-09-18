import Foundation

struct HTTPResult: Sendable {
    let data: Data
    let metadata: ResponseMetadata
}

protocol HTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> HTTPResult
}

private final class RedirectPolicy: NSObject, URLSessionTaskDelegate {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        // Surface redirects as HTTP errors rather than forwarding credentials or replaying POSTs.
        completionHandler(nil)
    }
}

actor URLSessionTransport: HTTPTransport {
    private let session: URLSession

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        configuration.urlCredentialStorage = nil
        configuration.timeoutIntervalForRequest = 86_400
        configuration.timeoutIntervalForResource = 86_400
        session = URLSession(configuration: configuration, delegate: RedirectPolicy(), delegateQueue: nil)
    }

    deinit { session.invalidateAndCancel() }

    func send(_ request: URLRequest) async throws -> HTTPResult {
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else {
            throw TypeSafeError.invalidResponse("Expected an HTTP response")
        }
        var headers: [String: String] = [:]
        for (key, value) in response.allHeaderFields {
            headers[String(describing: key).lowercased()] = String(describing: value)
        }
        return HTTPResult(data: data, metadata: .init(statusCode: response.statusCode, headers: headers))
    }
}

enum TimeoutKind: Sendable { case attempt, total }

struct RetryRuntime: Sendable {
    var waitForTimeout: @Sendable (Duration, TimeoutKind) async throws -> Void = { duration, _ in try await duration.sleep() }
    var sleep: @Sendable (Duration) async throws -> Void = { try await $0.sleep() }
    var random: @Sendable () -> Double = { Double.random(in: 0...1) }
    var now: @Sendable () -> Date = { Date() }
}
