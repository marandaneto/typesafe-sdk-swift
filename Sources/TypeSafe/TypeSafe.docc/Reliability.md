# Timeouts, retries, and cancellation

Bound network work while preserving Swift structured concurrency.

## Attempt timeout and total deadline

`timeout` defaults to ten seconds and applies to each HTTP attempt, including delivery of the response body. `totalTimeout` is optional and bounds the network operation across all attempts, response decoding, and retry waits. It starts after local request validation/encoding. Local typed-answer lookup is not included.

```swift
let client = try TypeSafeClient(
    apiKey: apiKey,
    timeout: .seconds(10),
    totalTimeout: .seconds(20),
    retry: RetryPolicy(maxRetries: 2)
)
let models = try await client.models.list(
    options: RequestOptions(timeout: .seconds(5), totalTimeout: .seconds(12))
)
```

Unset per-call values inherit client defaults. A nil client total timeout means no total deadline. A configured total deadline cannot be disabled for a single call; use another client when that is required.

An exhausted attempt timeout throws `TypeSafeError.timeout`. A total deadline throws `TypeSafeError.deadlineExceeded` and is never retried. Both use monotonic continuous-clock sleeps rather than wall-clock timestamps.

Cancellation of the calling task throws `CancellationError`, cancels active URLSession work or retry sleeps, and is never retried. If caller cancellation is observed while a timer also completes, cancellation takes precedence. When attempt and total timers fire together without caller cancellation, either timeout may win; a total deadline still prevents further work.

Deadlines are cooperative, not hard real-time preemption. The call drains cancelled child tasks before returning. Synchronous decoding and user log handlers cannot be forcibly interrupted, so handlers must return promptly.

## Retry policy

The SDK retries 408, 429, 500–599, connection failures, and attempt timeouts. The default is two retries after the original attempt. Delays start at 500 ms, double up to five seconds, and subtract up to 25% jitter. Server `retry-after-ms` and `Retry-After` headers are honored up to sixty seconds; longer delays use backoff.

Set `maxRetries: 0` to disable SDK retries. Per-call retry policies replace the complete policy. Redirects are not followed. Requests can incur charges; retrying a POST may repeat processing or billing. The SDK does not promise exactly-once execution or expose unverified idempotency behavior.

## Errors and diagnostics

HTTP errors contain status, raw body, and response metadata. An `invalidResponse` error may include ``ResponseValidationDetails`` containing the raw response, request ID/headers/status, and a coding path or requested-answer path. Treat those details as sensitive and redact them before sharing.

The transport/session is SDK-owned. Copying a client shares its safe transport but not request-local headers, retry state, or codecs. Concurrent requests can overlap. The session is invalidated when its final owning transport is released; there is no separate close method.
