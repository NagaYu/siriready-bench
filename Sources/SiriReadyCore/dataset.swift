import Foundation

/// A JSON scalar used for free-form `expected.params`.
public enum JSONScalar: Codable, Equatable, Sendable, CustomStringConvertible {
    case string(String), number(Double), bool(Bool), null

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let b = try? c.decode(Bool.self) { self = .bool(b) }
        else if let n = try? c.decode(Double.self) { self = .number(n) }
        else { self = .string(try c.decode(String.self)) }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .string(let s): try c.encode(s)
        case .number(let n): try c.encode(n)
        case .bool(let b): try c.encode(b)
        case .null: try c.encodeNil()
        }
    }

    public var description: String {
        switch self {
        case .string(let s): return s
        case .number(let n): return String(n)
        case .bool(let b): return String(b)
        case .null: return "null"
        }
    }
}

public struct PriorTurn: Codable, Equatable, Sendable {
    public var utterance: String
    public var intent: String
    public var entityId: String?

    enum CodingKeys: String, CodingKey { case utterance, intent, entityId = "entity_id" }
}

public struct CaseState: Codable, Equatable, Sendable {
    public var screen: String?
    public var visibleEntities: [String]
    public var priorTurn: PriorTurn?

    enum CodingKeys: String, CodingKey { case screen, visibleEntities = "visible_entities", priorTurn = "prior_turn" }
}

public struct ExpectedOutcome: Codable, Equatable, Sendable {
    public var intent: String
    public var entityId: String?
    public var params: [String: JSONScalar]
    /// `execute`, or `disambiguate` when asking the user is the correct behaviour.
    public var resolution: String
    public var candidates: [String]

    enum CodingKeys: String, CodingKey { case intent, entityId = "entity_id", params, resolution, candidates }
}

/// One line of `cases_*.jsonl`.
public struct BenchCase: Codable, Equatable, Sendable {
    public var caseId: String
    public var split: String
    public var appId: String
    public var domain: String
    public var locale: String
    public var utterance: String
    public var noise: String
    public var state: CaseState
    public var expected: ExpectedOutcome
    public var adversarial: Bool
    public var difficulty: String
    public var tags: [String]
    /// Dataset v1: surface string naming the target entity (nil for on-screen / previous-turn / create).
    public var mention: String? = nil
    /// Dataset v1: generator lineage (`v0-template`, `v1-para-A` …) used by the generator-holdout split.
    public var generator: String? = nil

    enum CodingKeys: String, CodingKey {
        case caseId = "case_id", split, appId = "app_id", domain, locale, utterance, noise, state, expected
        case adversarial, difficulty, tags, mention, generator
    }

    /// How the expected target is referred to, derived from the case (ground truth, not the resolver).
    public var referenceKind: ReferenceKind {
        if state.priorTurn != nil { return .priorTurn }
        let targets = expected.entityId.map { [$0] } ?? expected.candidates
        if targets.isEmpty { return .none }
        if !state.visibleEntities.isEmpty, Set(targets).isSubset(of: state.visibleEntities) || state.screen != nil {
            return .onScreen
        }
        return .name
    }
}

public enum ReferenceKind: String, Codable, Sendable {
    case none, name, onScreen = "on_screen", priorTurn = "prior_turn"
}

public struct EntityForm: Codable, Equatable, Sendable {
    public var text: String
    public var reading: String?
}

public struct CatalogEntity: Codable, Equatable, Sendable {
    public var id: String
    public var type: String
    public var locale: String
    public var forms: [EntityForm]
    public var qualifiers: [String]
    public var related: [String: String]
    public var attrs: [String: String]
}

/// Synthetic app content (`dataset/entities/<app_id>.json`) standing in for the app's data store.
public struct EntityCatalog: Codable, Sendable {
    public var appId: String
    public var domain: String
    public var synthetic: Bool
    public var datasetVersion: String
    public var intents: [String]
    public var entities: [CatalogEntity]

    enum CodingKeys: String, CodingKey {
        case appId = "app_id", domain, synthetic, datasetVersion = "dataset_version", intents, entities
    }

    public func entity(_ id: String) -> CatalogEntity? { entities.first { $0.id == id } }
}

public enum DatasetError: Error, CustomStringConvertible {
    case invalidLine(file: String, line: Int, underlying: String)

    public var description: String {
        switch self {
        case .invalidLine(let file, let line, let underlying): return "\(file):\(line): \(underlying)"
        }
    }
}

public enum DatasetLoader {
    public static func loadCases(_ url: URL) throws -> [BenchCase] {
        let text = try String(contentsOf: url, encoding: .utf8)
        let decoder = JSONDecoder()
        var cases: [BenchCase] = []
        for (i, line) in text.components(separatedBy: "\n").enumerated() where !line.trimmingCharacters(in: .whitespaces).isEmpty {
            do {
                cases.append(try decoder.decode(BenchCase.self, from: Data(line.utf8)))
            } catch {
                throw DatasetError.invalidLine(file: url.lastPathComponent, line: i + 1, underlying: String(describing: error))
            }
        }
        return cases
    }

    public static func loadCatalog(_ url: URL) throws -> EntityCatalog {
        try JSONDecoder().decode(EntityCatalog.self, from: Data(contentsOf: url))
    }

    /// FNV-1a 64-bit fingerprint (Foundation-only stand-in for a cryptographic hash; identifies inputs, not for security).
    public static func fingerprint(_ data: Data) -> String {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in data {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return String(format: "%016llx", hash)
    }
}
