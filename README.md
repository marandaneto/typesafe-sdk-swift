# TypeSafe Swift SDK

A Swift-native SDK for the [TypeSafe AI API](https://typesafe.ai), using Swift Package Manager, Swift 6 concurrency, and URLSession.

> **Under development.** Both endpoints, question/answer models, retries, timeouts, cancellation, and mock-server tests are implemented. Typed question handles and release/platform verification remain pending. See [PLAN.md](PLAN.md) and [COMPATIBILITY.md](COMPATIBILITY.md).

## Requirements

- Swift 6.0 or later, Swift 6 language mode.
- iOS/iPadOS 16, macOS 13, Mac Catalyst 16, tvOS 16, watchOS 9, or visionOS 1.
- No third-party runtime dependencies. The minimum OS versions reflect the use of Swift `Duration`.

macOS SDK tests and the iOS example's build/simulator tests have been run locally; the remaining Apple-platform matrix is not yet verified.

## Installation

Add this checkout as a local package in Xcode using **File → Add Package Dependencies → Add Local**, then select the `TypeSafe` library product.

For another local Swift package, add:

```swift
.package(path: "../typesafe-sdk-swift")
```

And add this dependency to the consuming target:

```swift
.product(name: "TypeSafe", package: "typesafe-sdk-swift")
```

Remote installation instructions will follow the first release.

## Evaluate content

```swift
import TypeSafe

let client = try TypeSafeClient(apiKey: apiKey)

let response = try await client.systemOne(
    state: .text("I was charged twice. Please fix this ASAP."),
    questions: [
        "category": .choice(
            instructions: "What is this ticket about?",
            criteria: ["billing": .null, "technical": .null, "other": .null]
        ),
        "urgent": .noul(instructions: "Does this need immediate attention?"),
        "priority": .score(
            instructions: "How urgent is this request?",
            criteria: ["Can wait", "Needs attention", "Urgent"]
        )
    ]
)

if case .choice(let answer) = response.value.answers["category"] {
    print(answer.choice)
    print(answer.confidence)
}

print(response.value.usage.inputTokens)
print(response.metadata.requestID ?? "No request ID")
```

`systemOne` calls `POST /v1/systemone`. The response includes the model, named answers, token usage, and HTTP metadata. `response.rawBody` contains the original server response bytes for inspection.

| Question | Answer |
| --- | --- |
| `noul` | Probability of yes/true, not a Boolean |
| `choice` | Selected label, confidence, and probabilities by label |
| `score` | Expected fractional score, confidence, legend, and probabilities keyed by integer score level |

Questions must be nonempty; score questions require at least two criteria. Unknown response fields are ignored. Missing or mismatched requested answers produce an error.

## Structured content

State and question descriptions support text, JSON objects, arrays, and explicit null. Omitted optional instructions are distinct from `.null`.

```swift
let state = Content.object([
    "document": .string("I was charged twice."),
    "attempts": .integer(2),
    "metadata": .null
])
```

`JSONValue` is `Codable`, `Equatable`, and `Sendable`, without `[String: Any]`. Signed 64-bit integers are preserved; other numbers use `Double`. Arbitrary-precision round trips are not guaranteed. Integral JSON numbers are normalized to `.integer` when representable; nonfinite numbers cannot be encoded.

## List models

```swift
let response = try await client.models.list()
for model in response.value.models {
    print(model.name, model.description, model.releaseDate)
}
```

This calls `GET /v1/models`. Release dates remain strings exactly as returned by the service, including timestamps.

## Configuration

```swift
let client = try TypeSafeClient(
    apiKey: apiKey,
    defaultModel: "jev-latest",
    timeout: .seconds(10),
    retry: RetryPolicy(maxRetries: 2)
)

let response = try await client.models.list(
    options: RequestOptions(
        timeout: .seconds(5),
        retry: RetryPolicy(maxRetries: 0),
        headers: ["X-Correlation-ID": "example"]
    )
)
```

The base URL defaults to `https://api.typesafe.ai`; a custom `URL` may include a path prefix. HTTPS is required except for loopback test servers. Authentication and protocol-critical headers cannot be overridden. Per-call retry settings replace the complete policy.

Default retries cover 408, 429, 500–599, connection failures, and timeouts. Backoff starts at 500 ms, doubles up to 5 seconds, and subtracts up to 25% jitter. Server retry headers are honored up to 60 seconds. Set `maxRetries: 0` to disable SDK retries.

The timeout covers the entire HTTP attempt, including delivery of the response body. It restarts for each attempt; there is no total deadline yet. **Retries can repeat server processing or billing.** Exactly-once execution is not guaranteed.

## Errors and cancellation

Networking uses `async throws`. `TypeSafeError` distinguishes invalid configuration, invalid requests, HTTP errors, connection errors, timeouts, and invalid responses. HTTP errors include status, raw response bytes, and metadata.

```swift
do {
    _ = try await client.models.list()
} catch is CancellationError {
    // The owning task was cancelled.
} catch TypeSafeError.http(let status, _, let metadata) {
    print(status, metadata.requestID ?? "No request ID")
}
```

Cancelling the calling task cancels active networking or retry waits and throws `CancellationError`; caller cancellation is never retried. All redirects are rejected rather than forwarding credentials or replaying POST requests.

## Concurrency

The client is immutable and `Sendable`, with an actor-owned URLSession. Requests have separate headers, codecs, and retry state. Concurrent calls can overlap. The SDK is not `@MainActor`; applications remain responsible for isolating UI updates.

## Security

**Do not embed a privileged TypeSafe API key in a distributed app.** App binaries and runtime credentials can be inspected. Keychain does not make a bundled shared secret safe.

Use a backend proxy for shared privileged credentials. Direct keys are appropriate only when the trust model permits them, such as trusted tools or user-supplied credentials. Custom proxy authentication is not implemented yet; custom base URLs currently still receive the configured bearer key.

There is no SDK logging yet. Client string descriptions redact the key; response bodies and headers may contain sensitive data and should not be logged indiscriminately.

## Example app

[Support Inbox Triage](Examples/SupportInbox/README.md) is a SwiftUI iPhone/iPad app that demonstrates all three question types, model selection, timeout/retry configuration, cancellation, and request/response inspection. It uses this checkout through SPM. The example README explains how to inject your ignored `.env` key into a Debug simulator build without bundling it.

## Tests

All tests use [Swift Testing](https://github.com/swiftlang/swift-testing), bundled with Swift 6. No separate testing dependency is necessary.

```sh
swift build
swift test
swift test --filter TypeSafeTests
swift test --filter TypeSafeIntegrationTests
```

Unit tests cover JSON, request validation, wire encoding, response validation, and deterministic retry calculations. Integration tests use a local Network.framework mock HTTP server with real URLSession requests to test authentication, responses, HTTP failures, retries, interrupted bodies, timeouts, cancellation, redirects, and concurrency. They require neither API credentials nor external services.

The server binds only to `127.0.0.1` on an automatically assigned port. Each test owns and shuts down its server and connections. Live service tests remain a future, opt-in release check.

## References

- [Python SDK](https://github.com/typesafe-ai/typesafe-sdk-python)
- [JavaScript SDK](https://github.com/typesafe-ai/typesafe-sdk-js)
- [TypeSafe documentation](https://docs.typesafe.ai/)

## License

[MIT](LICENSE).
