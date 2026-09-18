# Logging and privacy

Observe requests without logging credentials or content by default.

## Logging

Logging is disabled unless you supply ``LoggingOptions``. The handler is synchronous, `@Sendable`, and may be called concurrently; use a thread-safe sink and return promptly. The SDK does not store log history.

```swift
let client = try TypeSafeClient(
    apiKey: apiKey,
    logging: LoggingOptions { event in
        print(event.kind.rawValue, event.path, event.statusCode ?? 0)
    }
)
```

Each event includes an operation UUID shared across retries. Attempt numbers are zero-based; terminal failure summaries have no attempt number. Debug events describe requests, info events describe HTTP responses, warnings describe retries, and errors describe terminal network/decoding failures. Validation before networking and typed-answer lookup may throw without a network log event.

Bodies are omitted even at debug level unless `includeBodies: true` is explicitly set. The handler receives structured ``JSONValue`` rather than unfiltered bytes. Non-JSON bodies are omitted. API keys, sensitive request-header values, and recognized credential/password/token fields are redacted. Header values use a small allowlist; all others are redacted.

Body redaction is not a general personal-data detector. Opt-in bodies can still contain customer messages and other sensitive information. Avoid body logging in production. Error diagnostics and `APIResponse.rawBody` are not redacted automatically because they preserve the server's response; logging redaction applies only to log events.

## Credentials in apps

Never embed privileged shared API keys in a distributed app. App binaries and runtime credentials can be inspected; Keychain storage does not make a bundled shared secret safe. Use a backend for privileged operations. Direct keys are suitable only where the trust model permits them, such as trusted tools or user-supplied credentials.

The example's `.env` injection is limited to Debug simulator builds and does not bundle the key. Custom transport, client-default headers, backend-proxy authentication, and live API tests are deferred from the experimental release.

## Privacy review

The SDK sends only caller-provided content and the metadata necessary for HTTP/API operation. It does not add a stable user/device identifier, tracking SDK, persistence, UserDefaults, location access, or device fingerprinting. Logging is opt-in.

The repository's `PRIVACY.md` records the required-reason API review and its limits. Applications remain responsible for consent, App Store privacy declarations, and disclosures covering the content they send and the service's processing. No manifest claiming that no user data is collected is included: an arbitrary support message can contain personal data.
