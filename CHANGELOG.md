# Changelog

## 0.1.0 — Experimental (unreleased)

Initial experimental Swift port of the TypeSafe SDK. Public APIs and behavior may change before a stable release; this version is not yet tagged or published.

### Added

- Dependency-free Swift 6 package for iOS, iPadOS, macOS, Mac Catalyst, tvOS, watchOS, and visionOS.
- Async `systemOne` and model-listing APIs with a `Sendable` client and actor-owned URLSession transport.
- Choice, noul (yes/no probability), and score questions, including typed question handles and enum-backed choice answers.
- Structured JSON content, request/response validation, token usage, request IDs, HTTP metadata, and raw response bodies.
- Configurable retries with exponential backoff and server retry headers, per-attempt timeouts, optional total deadlines, and task cancellation.
- Opt-in structured logging with credential redaction and separately enabled bodies; detailed response-validation errors with metadata and field paths.
- DocC documentation with compiled examples and a documented privacy/lifecycle review.
- Swift Testing unit and local mock HTTP server integration tests, Apple-platform build checks, and CI configuration.
- SwiftUI Support Inbox example demonstrating all question types, model selection, request/response inspection, and local simulator credential injection.

### Known limitations

- Public custom transport configuration, backend-proxy authentication, client-default headers, and live API tests are intentionally outside this experimental release.
- Some nullability and score-criteria rules differ across the reference SDKs and public OpenAPI contract; full compatibility is not claimed.
- Remote CI/Swift 6.0 verification and release tagging are pending. Minimum-OS runtime certification is not claimed; library builds use those minimum deployment targets.
- Do not embed privileged API keys in distributed apps. The example's direct-key setup is for local simulator development only.

See [COMPATIBILITY.md](COMPATIBILITY.md) for behavior differences and [PLAN.md](PLAN.md) for remaining work.
