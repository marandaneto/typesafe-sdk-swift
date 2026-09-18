# TypeSafe Swift SDK

A Swift-native SDK for the [TypeSafe AI API](https://typesafe.ai), using Swift Package Manager, Swift 6 concurrency, and URLSession.

> **Under development.** Both endpoints, typed question handles, response validation, retries, timeouts, cancellation, and mock-server tests are implemented. Release gates and additional configuration features remain open. See [PLAN.md](PLAN.md) and [COMPATIBILITY.md](COMPATIBILITY.md).

## Requirements

- Swift 6.0 or later, Swift 6 language mode.
- iOS/iPadOS 16, macOS 13, Mac Catalyst 16, tvOS 16, watchOS 9, or visionOS 1.
- No third-party runtime dependencies. The minimum OS versions reflect the use of Swift `Duration`.

macOS and iOS Simulator tests pass locally. Library compilation has been checked for all six Apple platform families at their minimum deployment targets using Swift 6.4; that is not a runtime test on each minimum OS. CI is configured to also verify Swift 6.0 and the runner's newest stable Xcode.

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

For the unreleased development branch, use:

```swift
.package(url: "https://github.com/marandaneto/typesafe-sdk-swift.git", branch: "main")
```

There is no versioned release yet; `main` may change.

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

Questions and choice criteria must be nonempty; score questions require at least two criteria. Unknown response fields are ignored. Missing or mismatched requested answers produce an error. Decoding validates finite probability/confidence ranges, nonnegative token counts, and score bounds/levels; request validation checks returned probability keys against the requested criteria. Approximate probability sums are accepted.

## Typed questions and answers

Use handles when the set of choices is known at compile time:

```swift
enum Category: String, CaseIterable, Sendable {
    case billing, technical, other
}

let category = ChoiceQuestion<Category>(
    id: "category",
    instructions: "Which team should handle this request?"
)
let refund = NoulQuestion(id: "refund", instructions: "Is the customer requesting a refund?")
let urgency = ScoreQuestion(id: "urgency", criteria: ["Routine", "Urgent"])

let response = try await client.systemOne(
    state: "Please refund this duplicate charge.",
    questions: [
        category.eraseToAnyQuestion(),
        refund.eraseToAnyQuestion(),
        urgency.eraseToAnyQuestion()
    ]
)

let answer = try response.answer(for: category)
let selected: Category = answer.choice
let billingProbability: Double? = answer.probabilities[.billing]
let refundProbability = try response.answer(for: refund).noul
let expectedUrgency = try response.answer(for: urgency).score
```

The `CaseIterable` initializer includes all cases with null descriptions. For descriptions or a subset, pass `criteria: [.billing: "Payments and refunds", .technical: "Broken functionality"]`. String-backed enum choices and probability keys stay strongly typed.

Duplicate IDs are rejected before networking. Missing answers, wrong types, or incompatible label/level sets throw rather than force-cast or return defaults. `response.value.answer(for:)` also works. Handles match by ID and shape, not request identity or rubric wording; retain the handles used to make your request.

## Structured content

State and question descriptions can encode text, JSON objects, arrays, and explicit null. Omitted optional instructions are distinct from `.null`. Null state/score descriptions follow JavaScript's SDK types but disagree with published OpenAPI; service acceptance is not guaranteed. See [compatibility decisions](COMPATIBILITY.md).

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

`timeout` covers the entire HTTP attempt, including the response body, and restarts for each attempt. Set `totalTimeout: .seconds(20)` on the client or request options to bound all attempts and retry waits together. The total timer starts after local encoding/validation. Nil per-call values inherit client defaults; a nil client total timeout means no total deadline.

Attempt timeouts throw `.timeout`; total expiry throws `.deadlineExceeded` and is never retried. Deadlines are cooperative: cancelled child tasks are drained before returning, and synchronous decoding or user callbacks cannot be forcibly preempted. **Retries can repeat processing or billing.** Exactly-once execution is not guaranteed.

## Errors and cancellation

Networking uses `async throws`. `TypeSafeError` distinguishes invalid configuration, invalid requests, HTTP errors, connection errors, attempt timeouts, total deadlines, and invalid responses. HTTP errors include status, raw response bytes, and metadata. `invalidResponse(message, details:)` can include `ResponseValidationDetails` with the raw body, HTTP metadata, and field path. These diagnostics are sensitive and are not automatically redacted.

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

Client string descriptions redact the key. See [PRIVACY.md](PRIVACY.md) for the source-level privacy/lifecycle review and its limitations.

## Logging

Logging is disabled by default. Supply a short, thread-safe `@Sendable` handler to receive structured events:

```swift
let client = try TypeSafeClient(
    apiKey: apiKey,
    logging: LoggingOptions { event in
        print(event.kind.rawValue, event.path, event.statusCode ?? 0)
    }
)
```

The default minimum level is `.info`; `.debug` also emits request events. Each request has a correlation UUID shared across retries. Headers use a safe-value allowlist; other values and known credentials are redacted. Bodies remain absent even at debug level unless `includeBodies: true` is explicitly set. Opt-in bodies redact recognized credential fields but may still contain personal information; redaction is not a general PII detector. Never log raw response/error bodies indiscriminately.

## Example app

[Support Inbox Triage](Examples/SupportInbox/README.md) is a SwiftUI iPhone/iPad app that demonstrates all three question types, model selection, timeout/retry configuration, cancellation, and request/response inspection. It uses this checkout through SPM. The example README explains how to inject your ignored `.env` key into a Debug simulator build without bundling it.

## Tests

SDK unit/integration and sample feature tests use [Swift Testing](https://github.com/swiftlang/swift-testing), bundled with Swift 6. No separate testing dependency is necessary. The example's UI smoke test uses Apple's XCTest UI automation.

```sh
swift build
swift test
swift test --filter TypeSafeTests
swift test --filter TypeSafeIntegrationTests
```

Unit tests cover JSON, request validation, wire encoding, response validation, and deterministic retry calculations. Integration tests use a local Network.framework mock HTTP server with real URLSession requests to test authentication, responses, HTTP failures, retries, interrupted bodies, timeouts, cancellation, redirects, and concurrency. They require neither API credentials nor external services.

The server binds only to `127.0.0.1` on an automatically assigned port. Each test owns and shuts down its server and connections. Live API tests are deliberately excluded from this experimental release; normal tests never use credentials.

### CI and Apple builds

`.github/workflows/ci.yml` tests Xcode 16.2 (Swift 6.0) and the newest stable Xcode installed on the GitHub macOS runner. SDK tests, example tests, compiled documentation examples, DocC, Thread Sanitizer, simulator tests, and each platform/toolchain build run as independent jobs. There are no job dependencies or aggregate gate; each job can pass or fail independently. Actual concurrency depends on GitHub's available macOS runner capacity. Checkout/setup actions and the tooling jobs use Node 24.

```sh
# Point to an installed Xcode; this example uses the normal default path.
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer bash scripts/build-apple-platforms.sh

# Build just one platform, as each CI matrix job does.
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer bash scripts/build-apple-platforms.sh ios

# Requires xcodebuildmcp 2.3.2 and an installed iPhone simulator.
python3 scripts/test-ios-simulator.py
```

The simulator wrapper checks both the CLI exit status and tool-level/test-summary failures, so a failed test cannot pass CI just because the CLI exited successfully. Normal CI never reads `.env` or calls the real TypeSafe API.

## Documentation

The DocC catalog is in `Sources/TypeSafe/TypeSafe.docc`. In Xcode, use **Product → Build Documentation**, or run:

```sh
python3 scripts/build-documentation.py
python3 scripts/check-documentation-examples.py
```

The generated archive is under `.build/documentation`. The example checker compiles the Swift snippets without executing them or reading `.env`.

## References

- [Python SDK](https://github.com/typesafe-ai/typesafe-sdk-python)
- [JavaScript SDK](https://github.com/typesafe-ai/typesafe-sdk-js)
- [TypeSafe documentation](https://docs.typesafe.ai/)

## Changelog

See [CHANGELOG.md](CHANGELOG.md) for the initial experimental `0.1.0` version and known limitations. It is not yet tagged or published.

## License

[MIT](LICENSE).
