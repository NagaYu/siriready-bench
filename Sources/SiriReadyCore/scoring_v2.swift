import Foundation

// Phase 2 scoring profile.
//
// The Phase 1 score (`Scorer.score`, `scoreWeights`, five components) is unchanged and still
// reported. Phase 2 adds Parameter Accuracy as a sixth component in a separate, versioned profile
// and tags every component with where its evidence came from.

/// Where a number came from. `static` is source analysis (the C1–C5 audit); it is neither a MOCK
/// simulation nor a measurement of the running app.
public enum Provenance: String, Codable, CaseIterable, Sendable {
    case real, mock, spotcheck
    case staticAnalysis = "static"
}

public struct ProvenanceShare: Codable, Equatable, Sendable {
    public var source: Provenance
    public var share: Double

    public init(_ source: Provenance, _ share: Double) {
        self.source = source
        self.share = share
    }
}

public enum ComponentV2: String, Codable, CaseIterable, Sendable {
    case discoverability = "Discoverability"
    case entityResolution = "Entity Resolution"
    case parameterAccuracy = "Parameter Accuracy"
    case indexRecall = "Index Recall"
    case onScreenMultiTurn = "On-screen & Multi-turn"
    case staticHealth = "Static Health"
}

/// Siri Visibility Score v2 weights (sum = 1). Fixed by tests; change only with a profile bump.
public let scoreWeightsV2: [ComponentV2: Double] = [
    .discoverability: 0.20,
    .entityResolution: 0.20,
    .parameterAccuracy: 0.10,
    .indexRecall: 0.15,
    .onScreenMultiTurn: 0.15,
    .staticHealth: 0.20,
]

public struct ComponentScoreV2: Codable, Equatable, Sendable {
    public var component: ComponentV2
    public var value: Double?
    public var weight: Double
    public var passed: Int
    public var total: Int
    public var note: String
    public var provenance: [ProvenanceShare]
}

public struct ScoreBreakdownV2: Codable, Equatable, Sendable {
    public var profile = "v2"
    public var overall: Double
    public var components: [ComponentScoreV2]
    /// Weighted mix of the components' sources (shares sum to 1 over the components that have a value).
    public var provenance: [ProvenanceShare]

    /// One-line label such as "real 47% · mock 30% · static 23%".
    public var provenanceLabel: String { ProvenanceShare.label(provenance) }
}

extension ProvenanceShare {
    public static func label(_ shares: [ProvenanceShare]) -> String {
        shares.filter { $0.share > 0 }.map { String(format: "%@ %.0f%%", $0.source.rawValue, $0.share * 100) }.joined(separator: " · ")
    }

    static func combine(_ components: [(weight: Double, shares: [ProvenanceShare])]) -> [ProvenanceShare] {
        let total = components.reduce(0) { $0 + $1.weight }
        guard total > 0 else { return [] }
        return Provenance.allCases.compactMap { source in
            let share = components.reduce(0.0) { acc, c in acc + c.weight * c.shares.filter { $0.source == source }.reduce(0) { $0 + $1.share } } / total
            return share > 0 ? ProvenanceShare(source, share) : nil
        }
    }
}

/// Per-case parameter verdicts.
public struct ParamOutcome: Codable, Equatable, Sendable {
    public var caseId: String
    public var extracted: [String: String]
    /// MOCK slot filling matched `expected.params`.
    public var extractionCorrect: Bool
    /// Real runs only: the app persisted the expected values (nil when not measured).
    public var executionCorrect: Bool?
}

public enum ScorerV2 {
    /// Phase 1 provenance of each component in a MOCK-only run.
    public static let mockProvenance: [ComponentV2: [ProvenanceShare]] = [
        .discoverability: [ProvenanceShare(.mock, 1)],
        .entityResolution: [ProvenanceShare(.mock, 1)],
        .parameterAccuracy: [ProvenanceShare(.mock, 1)],
        .indexRecall: [ProvenanceShare(.staticAnalysis, indexCoverageShare), ProvenanceShare(.mock, 1 - indexCoverageShare)],
        .onScreenMultiTurn: [ProvenanceShare(.mock, 1)],
        .staticHealth: [ProvenanceShare(.staticAnalysis, auditHealthShare), ProvenanceShare(.mock, 1 - auditHealthShare)],
    ]

    /// MOCK parameter verdicts for cases whose expected intent was reached and that expect parameters.
    public static func mockParams(_ outcomes: [CaseOutcome], catalog: EntityCatalog? = nil) -> [ParamOutcome] {
        outcomes.compactMap { o in
            guard o.failure != .f1, o.failure != .f2, !o.benchCase.expected.params.isEmpty else { return nil }
            let extracted = ParamExtractor.extract(o.benchCase.utterance, intent: o.result.intent, catalog: catalog)
            return ParamOutcome(caseId: o.benchCase.caseId, extracted: extracted,
                                extractionCorrect: ParamExtractor.matches(expected: o.benchCase.expected.params, actual: extracted),
                                executionCorrect: nil)
        }
    }

    /// v2 score from the Phase 1 (v1) breakdown plus parameter verdicts.
    /// `provenance` and `paramPass` decide how each component is labelled and how params count.
    public static func score(v1: ScoreBreakdown, params: [ParamOutcome], provenance: [ComponentV2: [ProvenanceShare]],
                             paramPass: (ParamOutcome) -> Bool, paramNote: String) -> ScoreBreakdownV2 {
        let byName = Dictionary(uniqueKeysWithValues: v1.components.map { ($0.component.rawValue, $0) })
        var components: [ComponentScoreV2] = []
        for c in ComponentV2.allCases {
            if c == .parameterAccuracy {
                let passed = params.filter(paramPass).count
                components.append(ComponentScoreV2(
                    component: c, value: params.isEmpty ? nil : 100 * Double(passed) / Double(params.count),
                    weight: scoreWeightsV2[c]!, passed: passed, total: params.count, note: paramNote, provenance: provenance[c] ?? []))
            } else if let old = byName[c.rawValue] {
                components.append(ComponentScoreV2(component: c, value: old.value, weight: scoreWeightsV2[c]!, passed: old.passed,
                                                   total: old.total, note: old.note, provenance: provenance[c] ?? []))
            }
        }
        let available = components.filter { $0.value != nil }
        let weightSum = available.reduce(0) { $0 + $1.weight }
        let overall = weightSum == 0 ? 0 : available.reduce(0) { $0 + $1.weight * $1.value! } / weightSum
        return ScoreBreakdownV2(overall: overall, components: components,
                                provenance: ProvenanceShare.combine(available.map { ($0.weight, $0.provenance) }))
    }

    public static func mockScore(v1: ScoreBreakdown, outcomes: [CaseOutcome], catalog: EntityCatalog? = nil) -> (ScoreBreakdownV2, [ParamOutcome]) {
        let params = mockParams(outcomes, catalog: catalog)
        let score = score(v1: v1, params: params, provenance: mockProvenance, paramPass: \.extractionCorrect,
                          paramNote: "reached cases with expected params whose MOCK slot filling matches expected.params")
        return (score, params)
    }
}
