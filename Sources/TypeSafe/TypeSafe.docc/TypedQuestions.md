# Typed questions

Retain question handles to retrieve correctly typed answers without casts.

## Enum-backed choices

```swift
enum Team: String, CaseIterable, Sendable {
    case billing, technical, account
}

let team = ChoiceQuestion<Team>(id: "team", instructions: "Which support team should respond?")
let urgency = ScoreQuestion(id: "urgency", criteria: ["Routine", "Urgent"])
let response = try await client.systemOne(
    state: .object(["message": .string("I cannot log in before a presentation.")]),
    questions: [team.eraseToAnyQuestion(), urgency.eraseToAnyQuestion()]
)
let selected: Team = try response.answer(for: team).choice
let expectedScore = try response.answer(for: urgency).score
```

The `CaseIterable` initializer includes every case with null descriptions. To supply descriptions or restrict the allowed choices, pass a dictionary such as `criteria: [.billing: "Payments and refunds", .technical: "Broken functionality"]`.

``AnyQuestion`` erases the answer type only while assembling the heterogeneous request array. The original handle retains its type for answer lookup. Duplicate IDs fail before networking. Missing answers, mismatched types, and incompatible choice/score sets throw errors rather than returning defaults.

Handles identify answers by ID and compatible shape. They do not prove request identity or verify that rubric wording was identical. Reuse the handles you submitted.

## Dynamic questions

The dictionary overload accepts `[String: Question]` for questions whose names and choices are known only at runtime. Inspect the tagged ``Answer`` enum or use a matching ``AnyQuestion`` handle.

`Content` represents text, object, array, or explicit null. Optional instructions set to `nil` are omitted; `.null` is encoded as JSON null. Null state and score descriptions follow JavaScript SDK behavior but disagree with published OpenAPI, so the service may reject them.

The Swift SDK requires at least two score levels and nonempty choice criteria. This is deliberately stricter than some reference schemas. Unknown response fields are ignored, but unknown answer discriminators are rejected.
