# Initial compatibility decisions

References: Python `2ce5c65f13646cab6e6f782328194c9d85f3300a`, JavaScript `66880ccded6cb642dc1809620c2b108c33730214`.

This is an initial implementation, not a claim of complete SDK parity. The bundled response fixture is synthetic and follows the reference SDK types; it is not a recorded service response. Live OpenAPI/service verification remains a release gate.

| Area | Swift behavior |
| --- | --- |
| Endpoints | `POST /v1/systemone`, `GET /v1/models` |
| Authentication | Explicit bearer API key; no implicit environment lookup |
| Defaults | `https://api.typesafe.ai`, `jev-latest`, 10-second complete-attempt timeout |
| Questions | Nonempty dictionary; score criteria require at least two entries, matching handwritten SDK validation |
| Content | Text, object, array, explicit null; omitted optional instructions remain omitted |
| Response decoding | Required fields and tagged answer variants are decoded at runtime; unknown fields are ignored |
| Request/answer matching | Missing or wrong-type answers and selected choices absent from requested criteria are rejected; full probability/rubric consistency validation is pending |
| Score keys | Canonical nonnegative integer strings become `Int` keys; fractional expected scores remain `Double` |
| Model release date | Preserved as returned by the service, avoiding timezone conversion; live service testing returned ISO timestamps rather than the date-only strings described by the reference schema |
| Response metadata | `APIResponse.value` contains the decoded response; `.metadata` carries status, lowercased headers, and request ID; `.rawBody` preserves response bytes |
| Retry policy | Two retries; 408, 429, 500–599; connection failures and timeouts; 500 ms initial / 5 s maximum backoff, 25% downward jitter |
| Retry headers | `retry-after-ms` before `Retry-After`; numeric seconds and IMF-fixdate supported; delays over 60 s fall back to backoff |
| Total budget | No total deadline yet (like JavaScript); Python's retry budget is not ported |
| Overrides | Per-call timeout, headers, and complete retry policy; policy overrides replace the policy rather than merging individual fields |
| Cancellation | Swift task cancellation becomes `CancellationError`, including during backoff; never retried |
| Redirects | All redirects are surfaced as HTTP errors, preventing credential forwarding and automatic POST redirect replay |
| Transport | SDK-owned ephemeral URLSession, no cookie/credential/cache persistence; HTTP only permitted for loopback hosts |
| Limits | Timeout and delay configuration capped at one day; retry count capped at 100 |
| Logging | No SDK logging yet; client string descriptions redact the key |
| Platform minimums | iOS/iPadOS/Catalyst/tvOS 16, macOS 13, watchOS 9, visionOS 1, required by `Duration` |

## Still to implement

Typed question handles and answer accessors, public custom transport configuration, proxy authentication without a TypeSafe bearer key, client-default custom headers, optional total deadline, logging hooks, complete validation/error ergonomics, CI/platform matrix, and release packaging.

## Test boundary

Unit tests use injected transport/sleep/randomness. Integration tests use a Network.framework TCP server bound to an ephemeral IPv4 loopback port and real URLSession HTTP requests. No API credentials, external network service, Python runtime, or third-party server package is required. Swift Testing is bundled with the Swift 6 toolchain.

The mock server is deliberately test-only: one Content-Length request per connection, scripted replies, and connection close after each response. It is not a production HTTP server or a service-contract simulator.
