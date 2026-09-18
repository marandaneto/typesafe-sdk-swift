# Swift SDK implementation plan

## Goal

Port TypeSafe's API to an idiomatic, dependency-free Swift 6 library for Apple platforms. Preserve wire compatibility, not Python/JavaScript syntax. Use SPM, structured concurrency, and compiler-checked thread safety.

## Reference snapshots

- Python: `typesafe-ai/typesafe-sdk-python@2ce5c65f13646cab6e6f782328194c9d85f3300a`
- JavaScript: `typesafe-ai/typesafe-sdk-js@66880ccded6cb642dc1809620c2b108c33730214`

Initial API scope: `POST /v1/systemone` and `GET /v1/models`. No streaming, synchronous networking, Objective-C wrappers, Combine wrappers, macros, or Linux support in the initial release.

## Current progress

The initial client, models, retrying transport, deterministic unit tests, and loopback HTTP integration tests are implemented. See [COMPATIBILITY.md](COMPATIBILITY.md) for explicit current behavior and remaining differences. Live service verification, typed question handles, full validation, total deadlines, logging, and the platform/CI release gates remain open.

The original deployment proposal was raised to iOS/iPadOS/Catalyst/tvOS 16, macOS 13, and watchOS 9 because `Duration` is unavailable on the earlier OS versions. visionOS remains at 1.

## 0. Repository foundation

- [x] Add Apple/Swift `.gitignore` and MIT license attributed to marandaneto.
- [x] Create SPM library product `TypeSafe`, Swift tools 6.0, Swift 6 language mode.
- [x] Declare iOS/iPadOS 16, macOS 13, Catalyst 16, tvOS 16, watchOS 9, visionOS 1 minimums.
- [x] Document intended API and explicitly mark unimplemented examples.
- [x] Implement a `Sendable`, `Codable` JSON value foundation with unit tests.

## 1. Freeze the contract and public API

Initial decisions are recorded in `COMPATIBILITY.md`; the complete service-contract comparison remains pending.

- [ ] Compare the reference implementations, their tests, and the service's OpenAPI contract.
- [ ] Commit a compatibility matrix and sanitized request/response fixtures.
- [ ] Resolve nullability, omitted fields, score criteria minimum length, and score legend nulls. Python's generated schema differs from the handwritten SDK contracts.
- [ ] Decide retry-budget semantics: Python has a default retry budget; JavaScript has no total budget and caps server-directed retry delays.
- [ ] Define protected headers, SDK identification, request-ID extraction, and base-path joining.
- [ ] Specify custom proxy authentication separately from direct TypeSafe bearer authentication.
- [ ] Compile basic and typed-question API examples as tests once their declarations exist.

Gate: documented behavior for every difference; no accidental compatibility claims.

## 2. Models and validation

- [ ] Add `Content` restricted to text, object, array, and null, with ergonomic literals where unambiguous.
- [ ] Add question/answer tagged enums and strongly typed question handles with explicit type erasure.
- [x] Add response, model, token usage, and response metadata value types.
- [x] Preserve Swift camelCase properties via explicit wire coding keys.
- [x] Keep noul probability and expected score as `Double`; expose score map keys as integers through explicit conversion.
- [ ] Validate questions before networking; reject duplicate typed-handle IDs.
- [ ] Validate required response fields and answer discriminators, while tolerating unknown fields.
- [ ] Validate typed answer lookup against the request: missing IDs, wrong variants, unknown labels, and inconsistent criteria.
- [ ] Define an explicit extra-body escape hatch only if parity requires it; document collisions with standard fields.

Gate: fixture encoding/decoding tests plus malformed payload and typed-lookup tests; no `[String: Any]` or force casts in the public API.

## 3. Client and transport

- [ ] Implement immutable `Sendable` client configuration, request options, and client value type.
- [x] Define an internal injectable `Sendable` transport protocol and an actor-backed URLSession implementation.
- [x] Implement both endpoints and response metadata.
- [ ] Add structured `Sendable` errors for configuration, HTTP, connection, timeout, and decoding failures; preserve caller `CancellationError`.
- [ ] Merge headers case-insensitively, protect required headers, and preserve custom base-path prefixes.
- [ ] Restrict authenticated cross-origin redirects and validate base URLs.
- [ ] Define session ownership/lifecycle; do not invalidate caller-owned resources.
- [x] Use request-local codecs and state; do not mark the SDK `@MainActor`.

Gate: deterministic mock-transport tests and actual URLSession adapter tests, including redirects and response-body failures.

## 4. Reliability and concurrency

- [x] Default to two retries, statuses 408/429/500–599, 500 ms initial backoff, 5-second cap, and 25% downward jitter.
- [x] Support `Retry-After`, `retry-after-ms`, and bounded server-directed delays.
- [x] Implement a 10-second complete-attempt timeout; do not equate URLSession inactivity timeouts with a wall-clock deadline.
- [ ] Offer an optional total deadline with explicit semantics, separate from per-attempt timeout.
- [ ] Inject sleeping/clock and randomness for deterministic tests.
- [x] Propagate cancellation during requests and backoff; never retry caller cancellation.
- [ ] Verify timeout/cancellation races and cancellation of losing timeout tasks.
- [ ] Prove concurrent calls overlap without leaking headers, retries, answers, or credentials between requests.
- [ ] Audit actor reentrancy and lifecycle behavior across suspension points.
- [ ] Add `Sendable` logging hooks with body logging disabled and credential redaction.

Gate: strict Swift 6 compilation, deterministic race/retry tests, and sanitizer runs where supported. No SDK-owned `@unchecked Sendable`, `nonisolated(unsafe)`, detached tasks, or blocking waits.

## 5. Apple integration and release

- [ ] Add CI for Swift 6.0 and the latest supported Swift 6 toolchain.
- [ ] Run macOS and iOS simulator tests; build all advertised Apple platforms.
- [ ] Verify minimum deployment targets and integration from a main-actor-isolated app.
- [x] Add a SwiftUI example using app-owned UI isolation and cancellation; verified all three question types and model listing against the real API in the iOS Simulator.
- [ ] Add DocC documentation and compiled documentation examples.
- [ ] Document backend-proxy setup, direct-key risks, retry billing implications, and intentional SDK differences.
- [ ] Add opt-in live endpoint tests using CI secrets; never require credentials for normal tests.
- [ ] Review Apple privacy-manifest requirements against the actual implementation.
- [ ] Establish release URL, semantic versioning, changelog, and remote SPM installation instructions.

Release gate: verified platform matrix, zero concurrency diagnostics, passing tests, no exposed credentials, and API documentation that matches implemented behavior.
