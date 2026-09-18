import Foundation

public enum LogLevel: Int, Sendable, Comparable {
    case debug = 0
    case info = 1
    case warning = 2
    case error = 3

    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

public struct LogEvent: Sendable {
    public enum Kind: String, Sendable { case request, response, retry, failure }
    public let level: LogLevel
    public let kind: Kind
    public let operationID: UUID
    public let method: String
    public let path: String
    public let attempt: Int?
    public let statusCode: Int?
    public let headers: [String: String]
    public let body: JSONValue?
    public let message: String?
}

public struct LoggingOptions: Sendable {
    public let minimumLevel: LogLevel
    public let includeBodies: Bool
    public let handler: @Sendable (LogEvent) -> Void

    public init(
        minimumLevel: LogLevel = .info,
        includeBodies: Bool = false,
        handler: @escaping @Sendable (LogEvent) -> Void
    ) {
        self.minimumLevel = minimumLevel
        self.includeBodies = includeBodies
        self.handler = handler
    }
}

struct LogRedactor {
    private static let visibleHeaders: Set<String> = [
        "accept", "content-type", "content-length", "user-agent", "x-typesafe-sdk",
        "x-typesafe-retry-count", "x-typesafe-request-id", "retry-after", "retry-after-ms",
    ]
    private let secrets: [String]

    init(apiKey: String, requestHeaders: [String: String]) {
        secrets = [apiKey] + requestHeaders.compactMap { name, value in
            Self.visibleHeaders.contains(name.lowercased()) || value.isEmpty ? nil : value
        }
    }

    func text(_ value: String) -> String {
        secrets.reduce(value) { text, secret in text.replacingOccurrences(of: secret, with: "<redacted>") }
    }

    func headers(_ values: [String: String]) -> [String: String] {
        values.reduce(into: [:]) { result, entry in
            let name = entry.key.lowercased()
            result[text(name)] = Self.visibleHeaders.contains(name) ? text(entry.value) : "<redacted>"
        }
    }

    func body(_ data: Data?) -> JSONValue? {
        guard let data else { return nil }
        guard let value = try? JSONDecoder().decode(JSONValue.self, from: data) else {
            return .string("<non-JSON body omitted>")
        }
        return redact(value)
    }

    private func redact(_ value: JSONValue) -> JSONValue {
        switch value {
        case .string(let string): return .string(text(string))
        case .array(let values): return .array(values.map(redact))
        case .object(let object):
            return .object(object.reduce(into: [:]) { result, entry in
                let normalized = entry.key.lowercased().filter { $0.isLetter || $0.isNumber }
                let sensitive = ["authorization", "apikey", "password", "secret", "cookie", "setcookie", "credentials"].contains(normalized)
                    || normalized.hasSuffix("token") || normalized.hasSuffix("secret") || normalized.hasSuffix("password")
                result[text(entry.key)] = sensitive ? .string("<redacted>") : redact(entry.value)
            })
        default: return value
        }
    }
}
