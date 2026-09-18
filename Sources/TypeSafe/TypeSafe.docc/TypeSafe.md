# ``TypeSafe``

A Swift 6 client for the TypeSafe AI API on Apple platforms.

## Overview

Use ``TypeSafeClient`` to evaluate text or structured JSON with choice, noul (yes/no probability), and score questions. Networking uses `async throws`, task cancellation, and immutable `Sendable` values. The SDK does not require main-actor isolation.

```swift
let client = try TypeSafeClient(
    apiKey: apiKey,
    timeout: .seconds(10),
    totalTimeout: .seconds(20)
)
let refund = NoulQuestion(id: "refund", instructions: "Is the customer asking for a refund?")
let response = try await client.systemOne(
    state: "Please refund my duplicate payment.",
    questions: [refund.eraseToAnyQuestion()]
)
let probability = try response.answer(for: refund).noul
```

Noul values are probabilities, not Booleans. Expected scores may be fractional. Do not automatically approve refunds or make other consequential decisions solely from an example's output.

Version 0.1.0 is experimental. Consult the repository's compatibility document for intentional differences from the reference SDKs and service schema.

## Topics

### Getting started

- <doc:TypedQuestions>
- <doc:Reliability>
- <doc:LoggingAndPrivacy>
- ``TypeSafeClient``
- ``RequestOptions``

### Questions and content

- ``Question``
- ``AnyQuestion``
- ``NoulQuestion``
- ``ChoiceQuestion``
- ``ScoreQuestion``
- ``Content``
- ``JSONValue``

### Answers and metadata

- ``APIResponse``
- ``SystemOneResponse``
- ``Answer``
- ``TypedChoiceAnswer``
- ``NoulAnswer``
- ``ChoiceAnswer``
- ``ScoreAnswer``
- ``ResponseMetadata``
- ``ModelsResponse``
- ``Model``
- ``Usage``

### Configuration and errors

- ``RetryPolicy``
- ``TypeSafeError``
- ``ResponseValidationDetails``
- ``LoggingOptions``
- ``LogEvent``
- ``LogLevel``
