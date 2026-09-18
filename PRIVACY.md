# Privacy and lifecycle review — experimental 0.1.0

Reviewed 2026-09-18 against Apple's [privacy manifest guidance](https://developer.apple.com/documentation/bundleresources/privacy_manifest_files) and [required-reason API guidance](https://developer.apple.com/documentation/bundleresources/describing-use-of-required-reason-api).

## SDK behavior

- Sends caller-provided state/questions, model selection, authentication, and ordinary HTTP/SDK-identification headers to the configured endpoint.
- Does not collect a persistent device/user identifier, location, contacts, advertising identifiers, installed-app information, or fingerprints.
- Uses an ephemeral URLSession with cookies, credential storage, and URL cache disabled. No SDK persistence, UserDefaults, file metadata access, disk-space inspection, or device boot-time inspection is implemented.
- Uses `Date` only for parsing server retry dates and a continuous-clock task sleep for deadlines. It does not read uptime values or call `mach_absolute_time`/`systemUptime` to gather device signals.
- Log handlers are optional. Bodies are off by default, and header/known-credential redaction is applied before callbacks. Opt-in bodies may still contain personal information.
- Raw responses and error diagnostics intentionally retain server bytes. Apps must avoid unredacted logging or sharing of those values.

The source review found no direct use of APIs requiring a reason declaration in the SDK. No manifest asserting that no user data is collected is shipped: the SDK can transmit arbitrary caller-provided personal data, and collection/retention depends on the application and service. This is not a statement that an integrating app needs no manifest or privacy disclosures. Reassess this decision when adding storage, metrics, dependencies, or when Apple updates its API categories.

Applications must review their own data categories, consent, service retention, tracking declarations, and App Store privacy labels. Framework internals and future OS/App Store validation are not certified by this source review. Do not treat this document as legal advice or a guarantee of App Store acceptance.

## Example and tests

The SwiftUI example reads a launch-environment key only in Debug simulator builds. The launch helper reads the ignored local `.env`; neither the helper nor `.env` is a shipped SDK resource. Unit, HTTP integration, documentation, and UI smoke tests never load this file or call the production API. Backend-proxy implementation and live API tests are out of scope for 0.1.0 by request.

## Concurrency and ownership audit

The immutable `Sendable` client owns a reference to an actor-isolated transport. Copies share that transport safely. URLSession's delegate does not reference the client; there is no client/session retain cycle. The final transport owner invalidates the session on deinitialization. Active calls retain the resources they need until completion.

Headers, codecs, retry counters, validation data, and log correlation IDs are local to each call. No mutable global SDK state or actor invariant spans a network suspension. Reentrant transport calls can overlap; no lock serializes network operations.

Attempt and total timers are structured child tasks. The SDK cancels and drains losing children before returning. Timer/backoff/network test gates verify success cleanup, caller cancellation priority, timeout cleanup, and deadline cancellation during retries without real-time sleeps. Loopback integration tests exercise actual URLSession cancellation and interrupted bodies. Log handlers must be thread-safe and nonblocking; a blocking handler cannot be forcibly preempted by a deadline.

The SDK contains no `@unchecked Sendable`, `nonisolated(unsafe)`, detached tasks, or manually managed continuations. The test clock uses continuations solely for deterministic scheduling.
