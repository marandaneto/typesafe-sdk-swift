# Compatibility decisions

## Sources and evidence

- [Python snapshot](https://github.com/typesafe-ai/typesafe-sdk-python/tree/2ce5c65f13646cab6e6f782328194c9d85f3300a): public question/response types, question validation, retries, and tests.
- [JavaScript snapshot](https://github.com/typesafe-ai/typesafe-sdk-js/tree/66880ccded6cb642dc1809620c2b108c33730214): `types.ts`, `questions.ts`, client, retries, and tests.
- Public [OpenAPI](https://api.typesafe.ai/openapi.json), retrieved 2026-09-18: OpenAPI 3.1.0, API version 0.2.0.
- Pinned snapshot: `Tests/TypeSafeTests/Fixtures/openapi.json`; SHA-256 `032526ef1c1e00fc5330f66af5ee296c043355e10f1201983193ac6108b82975`.
- Golden fixtures are synthetic, credential-free examples, not recorded live responses. Tests compare the actual SDK request to a golden fixture and assert selected contract invariants; they are not a general JSON Schema validator.
- The Support Inbox example has exercised all question types and model listing against the live service. Disputed boundary cases below have not been live-tested.

## Wire differences requiring explicit choices

| Area | OpenAPI / Python / JavaScript | Swift decision |
| --- | --- | --- |
| Score criteria count | OpenAPI `minItems: 1`; Python rejects only empty scores; JavaScript requires at least two | Require at least two, retaining existing behavior and JavaScript parity. This is stricter than Python/OpenAPI. |
| Null state | OpenAPI and Python's public content type exclude top-level null; JavaScript accepts it | Preserve explicit `.null` for JavaScript compatibility. The service may reject it; not claimed as live-verified. |
| Null score criteria / legend | OpenAPI and Python exclude null entries; JavaScript types allow them | Preserve null descriptions and decode null legend entries. The service may reject such requests. |
| Optional instructions | OpenAPI allows omitted or null; Python model serialization omits `None` at the outer field; JavaScript helpers default instructions to null | `nil` omits instructions; `Content.null` explicitly encodes JSON null. |
| Choice criteria | OpenAPI has no minimum size; reference validators don't reject an empty choice map | Swift rejects empty choices as unusable questions. |
| Usage | OpenAPI/JavaScript require both integer counts; Python permits missing/null counts | Require both counts and reject negative values. No silent zero defaults. |
| Future answer types | Python drops unrecognized types; JavaScript does not validate runtime shape | Unknown fields are ignored, but unknown answer discriminators fail decoding. A typed answer must never silently become a default value. |
| Release date | Schema describes `YYYY-MM-DD`; the live service returned ISO timestamps | Preserve the server string without timezone conversion or format assumptions. |
| Response consistency | OpenAPI descriptions define probability and rubric semantics; numerical bounds are not schema constraints | Swift additionally checks finite 0…1 probabilities/confidences, contiguous score keys and bounds, and requested label/level sets. No exact distribution sum, argmax, or weighted-average check, to accommodate rounding. |

The null and score-count discrepancies need service confirmation or upstream clarification before claiming full parity. Swift validates label/level sets, not equality of rubric wording. Typed handles identify answers by ID and validate their shape; they are not proof that a handle came from a particular request.

## Implemented SDK behavior

| Area | Swift behavior |
| --- | --- |
| Endpoints | `POST /v1/systemone`, `GET /v1/models` |
| Authentication | Explicit bearer API key; no implicit environment lookup |
| Defaults | `https://api.typesafe.ai`, `jev-latest`, 10-second complete-attempt timeout |
| Questions | Dictionary API plus heterogeneous typed handles; duplicate handle IDs fail before networking |
| Typed choices | String-backed `RawRepresentable`, `Hashable`, `Sendable` values; `CaseIterable` convenience includes all cases; explicit criteria permit described subsets |
| Typed answers | `response.answer(for: handle)` or `response.value.answer(for: handle)`; choice and probability keys are enum values, without force casts |
| Response metadata | `.value` contains the decoded response; `.metadata` carries status, lowercased headers, and request ID; `.rawBody` preserves response bytes |
| Retry policy | Two retries; 408, 429, 500–599; connection failures/timeouts; 500 ms initial / 5 s maximum backoff; 25% downward jitter |
| Retry headers | `retry-after-ms` before `Retry-After`; numeric seconds and IMF-fixdate; delays over 60 s fall back to backoff |
| Total budget | Optional `totalTimeout` cancels attempts and backoff together, with a distinct `.deadlineExceeded` error. Defaults to nil; unlike Python's scheduling budget, it also interrupts active requests. |
| Overrides | Per-call timeout, headers, and complete retry policy; policies replace rather than merge field-by-field |
| Cancellation | Swift task cancellation becomes `CancellationError`, including during backoff; never retried |
| Headers | Authorization, Accept, Content-Type/Length, Host, User-Agent, X-TypeSafe-SDK, and retry count are protected case-insensitively; a retry adds its attempt number |
| URL/redirects | Base-path prefixes are preserved; all redirects fail as HTTP errors to avoid credential forwarding or automatic POST redirect replay |
| Transport | SDK-owned ephemeral URLSession, no cookie/credential/cache persistence; HTTP only on loopback hosts |
| Limits | Timeout/delay configuration capped at one day; retry count capped at 100 |
| Logging | Disabled by default; `Sendable` structured callbacks, safe-header allowlist, credential redaction, and separately opt-in JSON bodies. Client descriptions redact the key. |
| Platforms | iOS/iPadOS/Catalyst/tvOS 16, macOS 13, watchOS 9, visionOS 1 (`Duration` availability) |

## Verification

Swift Testing covers golden requests, decoding, typed handles, semantic validation, retries, and real URLSession calls to an ephemeral loopback server. The iOS workspace test plan includes SDK unit/integration targets, example feature tests, and a credential-free XCTest UI smoke test. Swift Testing is bundled with Swift 6.

The mock server is deliberately limited: one Content-Length request per connection, scripted replies, and connection close after each response. It is not a production HTTP server or a complete service simulator.

CI is configured for Swift 6.0 (Xcode 16.2) and the newest stable Xcode installed on `macos-15`; SDK builds cover every advertised Apple platform at its declared minimum target. The platform script checks compilation, not execution on those minimum OS versions. A remote CI run is still required to verify runner/toolchain behavior.

## Experimental scope

Custom transport/session configuration, proxy authentication, client-default headers, and live API tests are explicitly deferred by request. Extra request-body fields are not exposed in 0.1.0; the supported endpoints have a deliberately closed request surface. Total deadlines, logging, detailed response-validation errors, deterministic race tests, and DocC are implemented. See [PRIVACY.md](PRIVACY.md) for the privacy/lifecycle audit.

Minimum-OS runtime certification remains distinct from minimum-target compilation; no runtime claim is made for OS versions unavailable in the test environment. See [PLAN.md](PLAN.md) for release verification status.
