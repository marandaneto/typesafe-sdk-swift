# Swift SDK implementation plan

## Goal and scope

An idiomatic, dependency-free Swift 6 SPM library for Apple platforms, preserving the TypeSafe wire API rather than Python/JavaScript syntax.

Initial endpoints: `POST /v1/systemone` and `GET /v1/models`. No streaming, synchronous networking, Objective-C/Combine wrappers, macros, or Linux support in the initial release.

References:
- Python `2ce5c65f13646cab6e6f782328194c9d85f3300a`
- JavaScript `66880ccded6cb642dc1809620c2b108c33730214`
- Public OpenAPI 3.1 / API version 0.2.0, captured in `Tests/TypeSafeTests/Fixtures/openapi.json`.

See [COMPATIBILITY.md](COMPATIBILITY.md) for differences, validation policy, and unresolved service questions. Checked boxes describe implemented work; CI configuration is not evidence of a successful remote run.

## 0. Repository foundation

- [x] Apple/Swift `.gitignore`, ignored `.env`, and MIT license attributed to marandaneto.
- [x] SPM `TypeSafe` product, tools version 6.0, Swift 6 language mode, no runtime dependencies.
- [x] iOS/iPadOS/Catalyst/tvOS 16, macOS 13, watchOS 9, visionOS 1 minimums (`Duration` availability).
- [x] `Codable`, `Sendable` JSON values and content types; explicit null distinct from omitted optional fields.
- [x] Public GitHub repository and README with local SPM setup.

## 1. Contract and API design

- [x] Inspect both pinned SDK implementations and compare their wire models to public OpenAPI.
- [x] Store the OpenAPI snapshot, synthetic golden request/response fixtures, and compatibility matrix.
- [x] Record score minimum-length, nullability, optional usage, future-answer, and release-date differences.
- [x] Record retry policy differences: Swift currently follows JavaScript's lack of a total budget.
- [x] Document protected headers, base-path preservation, request IDs, and redirect policy.
- [x] Compile and test the basic and typed-question APIs.
- [x] Resolve the experimental contract policy by documenting discrepancies and avoiding full-parity claims. Further live probes/tests are excluded by request; disputed service acceptance remains an explicit limitation.
- [x] Keep extra request-body fields out of 0.1.0; the request surface intentionally exposes only supported fields.

Gate: supported behavior is documented; unresolved schema/service differences must not be represented as verified parity.

## 2. Models, typed handles, and validation

- [x] `Content`, tagged question/answer enums, response/model/usage/metadata value types, and Swift wire coding keys.
- [x] Noul probabilities and expected scores remain `Double`; score maps have validated integer keys.
- [x] `NoulQuestion`, `ScoreQuestion`, and enum-backed `ChoiceQuestion` handles with explicit `AnyQuestion` erasure.
- [x] Throwing typed answer access on both `SystemOneResponse` and `APIResponse` without casts or fallback values.
- [x] Validate nonempty question sets, choice criteria, score criteria, and duplicate handle IDs before networking.
- [x] Required fields/discriminators, finite probability/confidence ranges, nonnegative usage, score bounds, and contiguous score levels.
- [x] Match requested answer IDs, types, choice probability keys, and score level keys; tolerate unknown JSON fields.
- [x] Preserve approximate distributions without requiring exact sums or recomputing the server's score/confidence.

Gate: fixture tests, invalid-payload tests, typed lookup tests, and loopback HTTP tests pass. Handle lookup validates IDs/types/label or level sets, not the provenance of a request or the wording of instructions/rubrics.

## 3. Client and transport

- [x] Immutable `Sendable` client; value-based per-request options.
- [x] Internal injectable `Sendable` transport and actor-owned ephemeral URLSession.
- [x] Both endpoints, raw response bytes, status/headers/request-ID metadata.
- [x] Structured `Sendable` configuration/request/HTTP/connection/timeout/response errors; caller `CancellationError` preserved.
- [x] Case-insensitive protected-header handling, custom base-path preservation, HTTPS validation, and refusal of redirects.
- [x] SDK session ownership and cleanup; codecs and retry state remain request-local; no main-actor requirement.
- Deferred by request: public custom transport/session configuration, client-default headers, and backend-proxy authentication.
- [x] Response-validation errors preserve body, HTTP metadata, and field paths.

## 4. Reliability and concurrency

- [x] Two retries; statuses 408/429/500–599; connection/timeout retries; bounded exponential backoff with jitter.
- [x] `Retry-After`, `retry-after-ms`, capped server delays, and deterministic injected sleep/time/randomness tests.
- [x] Per-attempt timeout includes the complete response body; caller cancellation interrupts requests and backoff.
- [x] Tests for interrupted bodies, timeout retries, cancellation, overlapping calls, and isolated request headers.
- [x] Swift 6 warnings-as-errors builds and local Thread Sanitizer testing.
- [x] Optional total deadline, including retry delays, distinct from attempt timeout.
- [x] Deterministic timeout/cancellation race tests, child-task cleanup tests, and lifecycle/reentrancy audit in `PRIVACY.md`.
- [x] `Sendable` logging hooks, credential redaction, and separately opt-in body logging.

Gate: no SDK-owned `@unchecked Sendable`, `nonisolated(unsafe)`, detached tasks, or blocking waits.

## 5. Apple integration, CI, and release

- [x] SwiftUI sample with all question types, model selection, request/response inspection, cancellation, and safe local key injection.
- [x] Manually verify all sample presets and model listing against the live service in iOS Simulator.
- [x] macOS tests and iOS Simulator SDK/HTTP/sample tests; sample UI runs with main-actor isolation.
- [x] Compile library for macOS, iOS, Catalyst, tvOS, watchOS, and visionOS at declared minimum deployment targets using the current local compiler.
- [x] Add CI for Xcode 16.2 / Swift 6.0 and the newest stable Xcode installed on the runner; strict tests, Apple builds, Thread Sanitizer, and simulator tests.
- [ ] Run the new workflow on GitHub and verify the Swift 6.0 baseline there; local builds used Swift 6.4.
- [ ] Runtime smoke tests on minimum OS versions and broader architectures; compilation alone is not runtime certification.
- [x] DocC catalog, archive build, and compile-only verification of the catalog's Swift examples.
- Deferred by request: backend-proxy implementation/guide and automated live API tests. No additional live API requests are required for this experimental version.
- [x] Apple privacy-manifest requirements review recorded in `PRIVACY.md`; no unsupported no-data-collection declaration is shipped.
- [x] Add a changelog for the initial experimental `0.1.0` version (not yet released).
- [ ] Release version/tag and versioned remote SPM installation instructions.

Release gate: verified CI/platform matrix, passing tests, no exposed credentials, documented compatibility decisions, and documentation matching implemented behavior.
