func isProbability(_ value: Double) -> Bool {
    value.isFinite && (0...1).contains(value)
}

extension Question {
    func validate(id: String) throws {
        switch self {
        case .choice(_, let criteria) where criteria.isEmpty:
            throw TypeSafeError.invalidRequest("Choice question '\(id)' requires at least one criterion")
        case .score(_, let criteria) where criteria.count < 2:
            throw TypeSafeError.invalidRequest("Score question '\(id)' requires at least two criteria")
        default: break
        }
    }

    func validate(answer: Answer, id: String) throws {
        try validate(id: id)
        switch (self, answer) {
        case (.noul, .noul): return
        case (.choice(_, let criteria), .choice(let result)):
            guard criteria[result.choice] != nil, Set(result.probabilities.keys) == Set(criteria.keys) else {
                throw TypeSafeError.invalidResponse("Choice labels do not match the criteria for '\(id)'")
            }
        case (.score(_, let criteria), .score(let result)):
            let indices = Set(criteria.indices)
            guard Set(result.legend.keys) == indices, Set(result.probabilities.keys) == indices,
                  (0...Double(criteria.count - 1)).contains(result.score) else {
                throw TypeSafeError.invalidResponse("Score levels do not match the criteria for '\(id)'")
            }
        default:
            throw TypeSafeError.invalidResponse("Mismatched answer type for '\(id)'")
        }
    }
}
