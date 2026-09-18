import Foundation

public enum Content: Sendable, Equatable, Encodable, ExpressibleByStringLiteral {
    case text(String)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    public init(stringLiteral value: String) { self = .text(value) }

    public func encode(to encoder: any Encoder) throws {
        let value: JSONValue
        switch self {
        case .text(let text): value = .string(text)
        case .object(let object): value = .object(object)
        case .array(let array): value = .array(array)
        case .null: value = .null
        }
        try value.encode(to: encoder)
    }
}

public enum Question: Sendable, Encodable {
    case noul(instructions: Content? = nil, yes: Content? = nil, no: Content? = nil)
    case choice(instructions: Content? = nil, criteria: [String: Content])
    case score(instructions: Content? = nil, criteria: [Content])

    private enum CodingKeys: String, CodingKey { case type, instructions, criteria }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .noul(let instructions, let yes, let no):
            try container.encode("noul", forKey: .type)
            try container.encodeIfPresent(instructions, forKey: .instructions)
            var criteria: [String: Content] = [:]
            criteria["true"] = yes
            criteria["false"] = no
            if !criteria.isEmpty { try container.encode(criteria, forKey: .criteria) }
        case .choice(let instructions, let criteria):
            try container.encode("choice", forKey: .type)
            try container.encodeIfPresent(instructions, forKey: .instructions)
            try container.encode(criteria, forKey: .criteria)
        case .score(let instructions, let criteria):
            try container.encode("score", forKey: .type)
            try container.encodeIfPresent(instructions, forKey: .instructions)
            try container.encode(criteria, forKey: .criteria)
        }
    }
}

public struct NoulAnswer: Decodable, Sendable {
    public let noul: Double

    private enum CodingKeys: String, CodingKey { case noul }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        noul = try container.decode(Double.self, forKey: .noul)
        guard isProbability(noul) else {
            throw DecodingError.dataCorruptedError(forKey: .noul, in: container, debugDescription: "Expected a finite probability from zero to one")
        }
    }
}

public struct ChoiceAnswer: Decodable, Sendable {
    public let choice: String
    public let confidence: Double
    public let probabilities: [String: Double]

    private enum CodingKeys: String, CodingKey { case choice, confidence, probabilities }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        choice = try container.decode(String.self, forKey: .choice)
        confidence = try container.decode(Double.self, forKey: .confidence)
        probabilities = try container.decode([String: Double].self, forKey: .probabilities)
        guard isProbability(confidence), probabilities.values.allSatisfy(isProbability), probabilities[choice] != nil else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Invalid choice confidence, probabilities, or selected label"))
        }
    }
}

public struct ScoreAnswer: Decodable, Sendable {
    public let score: Double
    public let confidence: Double
    public let legend: [Int: JSONValue]
    public let probabilities: [Int: Double]

    private enum CodingKeys: String, CodingKey { case score, confidence, legend, probabilities }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        score = try container.decode(Double.self, forKey: .score)
        confidence = try container.decode(Double.self, forKey: .confidence)
        legend = try Self.integerKeys(container.decode([String: JSONValue].self, forKey: .legend), decoder: decoder)
        probabilities = try Self.integerKeys(container.decode([String: Double].self, forKey: .probabilities), decoder: decoder)
        guard score.isFinite, score >= 0, isProbability(confidence),
              !legend.isEmpty, score <= Double(legend.count - 1),
              Set(legend.keys) == Set(0..<legend.count), Set(legend.keys) == Set(probabilities.keys),
              probabilities.values.allSatisfy(isProbability),
              legend.values.allSatisfy({ value in
                  switch value {
                  case .string, .object, .array, .null: true
                  default: false
                  }
              }) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Invalid score, confidence, legend, or probabilities"))
        }
    }

    private static func integerKeys<T>(_ values: [String: T], decoder: any Decoder) throws -> [Int: T] {
        var result: [Int: T] = [:]
        for (key, value) in values {
            guard let index = Int(key), index >= 0, String(index) == key else {
                throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Invalid score key: \(key)"))
            }
            result[index] = value
        }
        return result
    }
}

public enum Answer: Decodable, Sendable {
    case noul(NoulAnswer)
    case choice(ChoiceAnswer)
    case score(ScoreAnswer)

    private enum CodingKeys: String, CodingKey { case type }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(String.self, forKey: .type) {
        case "noul": self = .noul(try NoulAnswer(from: decoder))
        case "choice": self = .choice(try ChoiceAnswer(from: decoder))
        case "score": self = .score(try ScoreAnswer(from: decoder))
        default:
            throw DecodingError.dataCorruptedError(forKey: .type, in: container, debugDescription: "Unknown answer type")
        }
    }
}

public struct Usage: Decodable, Sendable {
    public let inputTokens: Int
    public let outputTokens: Int
    private enum CodingKeys: String, CodingKey {
        case inputTokens = "input_tokens", outputTokens = "output_tokens"
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        inputTokens = try container.decode(Int.self, forKey: .inputTokens)
        outputTokens = try container.decode(Int.self, forKey: .outputTokens)
        guard inputTokens >= 0, outputTokens >= 0 else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Token counts must not be negative"))
        }
    }
}

public struct SystemOneResponse: Decodable, Sendable {
    public let model: String
    public let answers: [String: Answer]
    public let usage: Usage

    private enum CodingKeys: String, CodingKey { case model, answers, usage }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        model = try container.decode(String.self, forKey: .model)
        answers = try container.decode([String: Answer].self, forKey: .answers)
        usage = try container.decode(Usage.self, forKey: .usage)
        guard !answers.isEmpty else {
            throw DecodingError.dataCorruptedError(forKey: .answers, in: container, debugDescription: "Answers must not be empty")
        }
    }
}

public struct Model: Decodable, Sendable {
    public let name: String
    public let description: String
    public let releaseDate: String
    private enum CodingKeys: String, CodingKey {
        case name, description, releaseDate = "release_date"
    }
}

public struct ModelsResponse: Decodable, Sendable {
    public let models: [Model]
}

public struct ResponseMetadata: Sendable {
    public let statusCode: Int
    public let headers: [String: String]
    public var requestID: String? { headers["x-typesafe-request-id"] }
}

public struct APIResponse<Value: Sendable>: Sendable {
    public let value: Value
    public let metadata: ResponseMetadata
    public let rawBody: Data
}

public struct ResponseValidationDetails: Sendable {
    public let metadata: ResponseMetadata
    public let body: Data
    public let fieldPath: [String]
}

public enum TypeSafeError: Error, Sendable {
    case invalidConfiguration(String)
    case invalidRequest(String)
    case http(statusCode: Int, body: Data, metadata: ResponseMetadata)
    case connection(code: Int)
    case timeout
    case deadlineExceeded
    case invalidResponse(String, details: ResponseValidationDetails? = nil)
}
