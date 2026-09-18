public struct AnyQuestion: Sendable {
    public let id: String
    public let question: Question

    public init(id: String, question: Question) {
        self.id = id
        self.question = question
    }
}

public struct NoulQuestion: Sendable {
    public let id: String
    private let question: Question

    public init(id: String, instructions: Content? = nil, yes: Content? = nil, no: Content? = nil) {
        self.id = id
        question = .noul(instructions: instructions, yes: yes, no: no)
    }

    public func eraseToAnyQuestion() -> AnyQuestion { AnyQuestion(id: id, question: question) }
}

public struct ScoreQuestion: Sendable {
    public let id: String
    private let question: Question

    public init(id: String, instructions: Content? = nil, criteria: [Content]) {
        self.id = id
        question = .score(instructions: instructions, criteria: criteria)
    }

    public func eraseToAnyQuestion() -> AnyQuestion { AnyQuestion(id: id, question: question) }
}

public struct ChoiceQuestion<Choice: RawRepresentable & Hashable & Sendable>: Sendable where Choice.RawValue == String {
    public let id: String
    private let instructions: Content?
    private let criteria: [Choice: Content]

    public init(id: String, instructions: Content? = nil, criteria: [Choice: Content]) {
        self.id = id
        self.instructions = instructions
        self.criteria = criteria
    }

    public func eraseToAnyQuestion() -> AnyQuestion {
        let labels = criteria.reduce(into: [String: Content]()) { result, entry in
            result[entry.key.rawValue] = entry.value
        }
        return AnyQuestion(id: id, question: .choice(instructions: instructions, criteria: labels))
    }
}

extension ChoiceQuestion where Choice: CaseIterable {
    public init(id: String, instructions: Content? = nil) {
        self.init(id: id, instructions: instructions, criteria: Choice.allCases.reduce(into: [:]) { $0[$1] = .null })
    }
}

public struct TypedChoiceAnswer<Choice: Hashable & Sendable>: Sendable {
    public let choice: Choice
    public let confidence: Double
    public let probabilities: [Choice: Double]
}

extension SystemOneResponse {
    public func answer(for question: NoulQuestion) throws -> NoulAnswer {
        guard case .noul(let answer) = try answer(for: question.eraseToAnyQuestion()) else {
            throw TypeSafeError.invalidResponse("Expected a noul answer for '\(question.id)'")
        }
        return answer
    }

    public func answer(for question: ScoreQuestion) throws -> ScoreAnswer {
        guard case .score(let answer) = try answer(for: question.eraseToAnyQuestion()) else {
            throw TypeSafeError.invalidResponse("Expected a score answer for '\(question.id)'")
        }
        return answer
    }

    public func answer<Choice>(for question: ChoiceQuestion<Choice>) throws -> TypedChoiceAnswer<Choice> {
        guard case .choice(let answer) = try answer(for: question.eraseToAnyQuestion()),
              let selected = Choice(rawValue: answer.choice) else {
            throw TypeSafeError.invalidResponse("Expected a known choice for '\(question.id)'")
        }
        var probabilities: [Choice: Double] = [:]
        for (label, probability) in answer.probabilities {
            guard let choice = Choice(rawValue: label) else {
                throw TypeSafeError.invalidResponse("Unknown choice label for '\(question.id)'")
            }
            probabilities[choice] = probability
        }
        return TypedChoiceAnswer(choice: selected, confidence: answer.confidence, probabilities: probabilities)
    }

    public func answer(for question: AnyQuestion) throws -> Answer {
        guard let answer = answers[question.id] else {
            throw TypeSafeError.invalidResponse("Missing answer for '\(question.id)'")
        }
        try question.question.validate(answer: answer, id: question.id)
        return answer
    }
}

extension APIResponse where Value == SystemOneResponse {
    public func answer(for question: NoulQuestion) throws -> NoulAnswer { try value.answer(for: question) }
    public func answer(for question: ScoreQuestion) throws -> ScoreAnswer { try value.answer(for: question) }
    public func answer<Choice>(for question: ChoiceQuestion<Choice>) throws -> TypedChoiceAnswer<Choice> {
        try value.answer(for: question)
    }
    public func answer(for question: AnyQuestion) throws -> Answer { try value.answer(for: question) }
}
