import Foundation

public struct RetryPolicy: Sendable {
    public var maxRetries: Int
    public var initialDelay: Duration
    public var maximumDelay: Duration
    public var jitter: Double
    public var statuses: Set<Int>
    public var respectRetryAfter: Bool
    public var maximumRetryAfter: Duration

    public init(
        maxRetries: Int = 2,
        initialDelay: Duration = .milliseconds(500),
        maximumDelay: Duration = .seconds(5),
        jitter: Double = 0.25,
        statuses: Set<Int> = Set([408, 429]).union(Set(500...599)),
        respectRetryAfter: Bool = true,
        maximumRetryAfter: Duration = .seconds(60)
    ) {
        self.maxRetries = maxRetries
        self.initialDelay = initialDelay
        self.maximumDelay = maximumDelay
        self.jitter = jitter
        self.statuses = statuses
        self.respectRetryAfter = respectRetryAfter
        self.maximumRetryAfter = maximumRetryAfter
    }

    func validate() throws {
        guard maxRetries >= 0, maxRetries <= 100,
              initialDelay >= .zero, maximumDelay >= .zero,
              maximumRetryAfter >= .zero,
              maximumDelay <= .seconds(86_400), maximumRetryAfter <= .seconds(86_400),
              initialDelay <= .seconds(86_400), jitter.isFinite, (0...1).contains(jitter),
              statuses.allSatisfy({ (100...599).contains($0) }) else {
            throw TypeSafeError.invalidConfiguration("Invalid retry policy")
        }
    }

    func delay(attempt: Int, headers: [String: String], random: Double, now: Date) -> Duration {
        if respectRetryAfter, let delay = serverDelay(headers: headers, now: now),
           delay.isFinite, delay >= 0, delay <= maximumRetryAfter.seconds {
            return .seconds(delay)
        }
        let exponential = min(maximumDelay.seconds, initialDelay.seconds * pow(2, Double(min(attempt, 100))))
        return .seconds(exponential * (1 - random * jitter))
    }

    private func serverDelay(headers: [String: String], now: Date) -> Double? {
        if let value = headers["retry-after-ms"], let milliseconds = Double(value), milliseconds.isFinite, milliseconds >= 0 {
            return milliseconds / 1_000
        }
        guard let value = headers["retry-after"] else { return nil }
        if let seconds = Double(value) { return seconds }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        return formatter.date(from: value).map { max(0, $0.timeIntervalSince(now)) }
    }
}

extension Duration {
    var seconds: Double {
        Double(components.seconds) + Double(components.attoseconds) / 1e18
    }

    func sleep() async throws {
        try Task.checkCancellation()
        try await Task.sleep(nanoseconds: UInt64(max(0, seconds) * 1_000_000_000))
    }
}
