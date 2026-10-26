import Foundation

/// Failure taxonomy (first failing stage wins; see `Scorer.classify`).
public enum FailureClass: String, Codable, CaseIterable, Comparable, Sendable {
    case f1 = "F1", f2 = "F2", f3 = "F3", f4 = "F4", f5 = "F5", f6 = "F6", f7 = "F7", f8 = "F8"

    public var title: String {
        switch self {
        case .f1: return "Not Discovered"
        case .f2: return "Wrong Target"
        case .f3: return "Entity Misresolution"
        case .f4: return "Not Indexed"
        case .f5: return "Disambiguation Failure"
        case .f6: return "On-screen Reference Failure"
        case .f7: return "Context Loss"
        case .f8: return "Privacy Routing Mismatch"
        }
    }

    public var definition: String {
        switch self {
        case .f1: return "No App Intent of the app is reachable for the requested action."
        case .f2: return "A different intent than the expected one was selected."
        case .f3: return "The right intent was reached but a named target resolved to the wrong entity (or to none although it is indexed)."
        case .f4: return "The target's entity type is not in the semantic index and has no string query, so a name cannot be resolved."
        case .f5: return "Ambiguous targets were not clarified (picked one silently), or the system asked although the target was unambiguous."
        case .f6: return "An on-screen reference (\"this\", \"the second one\") could not be resolved, e.g. the view has no View Annotation."
        case .f7: return "A reference to the previous turn could not be carried over."
        case .f8: return "Everything resolved, but execution would leave the device although the intent is declared on_device_only."
        }
    }

    public static func < (a: FailureClass, b: FailureClass) -> Bool { a.rawValue < b.rawValue }
}

public enum ScoreComponent: String, Codable, CaseIterable, Sendable {
    case discoverability = "Discoverability"
    case entityResolution = "Entity Resolution"
    case indexRecall = "Index Recall"
    case onScreenMultiTurn = "On-screen & Multi-turn"
    case staticHealth = "Static Health"
}

/// Siri Visibility Score weights (sum = 1). Fixed by tests; change only with a bench version bump.
public let scoreWeights: [ScoreComponent: Double] = [
    .discoverability: 0.25,
    .entityResolution: 0.25,
    .indexRecall: 0.15,
    .onScreenMultiTurn: 0.15,
    .staticHealth: 0.20,
]

/// Audit health penalty per finding (Static Health starts at 100, floored at 0).
public let severityPenalty: [Severity: Double] = [.critical: 30, .high: 15, .medium: 7, .low: 2]

/// Static Health = auditHealthShare × audit health + (1 − auditHealthShare) × privacy-routing conformance.
public let auditHealthShare = 0.7

/// Index Recall (Phase 1 stand-in) = coverageShare × C2 coverage + (1 − coverageShare) × simulated recall.
public let indexCoverageShare = 0.5

public struct ComponentScore: Codable, Equatable, Sendable {
    public var component: ScoreComponent
    /// 0–100, or nil when no case exercises the component (its weight is then redistributed).
    public var value: Double?
    public var weight: Double
    public var passed: Int
    public var total: Int
    public var note: String
}

public struct ScoreBreakdown: Codable, Equatable, Sendable {
    /// Siri Visibility Score (MOCK), 0–100.
    public var overall: Double
    public var components: [ComponentScore]
}

public struct IndexSimulation: Codable, Equatable, Sendable {
    public var coverage: Double
    public var queries: Int
    public var hits: Int
    public var simulatedRecall: Double { queries == 0 ? 0 : Double(hits) / Double(queries) }
}

public struct CaseOutcome: Codable, Sendable {
    public var benchCase: BenchCase
    public var result: MockResolution
    public var failure: FailureClass?
}

public enum Scorer {
    public static func classify(_ c: BenchCase, _ r: MockResolution) -> FailureClass? {
        guard let intent = r.intent else { return .f1 }
        if intent != c.expected.intent { return .f2 }
        let needsEntity = c.expected.entityId != nil || c.expected.resolution == "disambiguate"
        if needsEntity {
            if r.notes.contains(.screenNotDeclared) || r.notes.contains(.viewNotAnnotated) || r.notes.contains(.visibleTypeMismatch) { return .f6 }
            if r.notes.contains(.priorTurnUnresolvable) { return .f7 }
            if r.notes.contains(.entityTypeNotIndexed) { return .f4 }
            let modeFailure: FailureClass = r.referenceMode == .onScreen ? .f6 : r.referenceMode == .priorTurn ? .f7 : .f3
            if c.expected.resolution == "disambiguate" {
                if r.resolution == "none" { return modeFailure }
                if r.resolution != "disambiguate" || !Set(c.expected.candidates).isSubset(of: r.candidates) { return .f5 }
            } else {
                if r.resolution == "disambiguate" { return .f5 }
                if r.entityId != c.expected.entityId { return modeFailure }
            }
        }
        if r.notes.contains(.routingMismatch) { return .f8 }
        return nil
    }

    /// Lexical/phonetic retrieval over every catalog entity of the app's entity types, querying
    /// each form (and kana reading). Phase 1 stand-in for measuring the real Spotlight index.
    public static func simulateIndex(model: AppModel, catalog: EntityCatalog, coverage: Double) -> IndexSimulation {
        let declaredTypes = Set(model.entities.map(\.name))
        let indexed = model.indexedEntityTypes
        var queries = 0, hits = 0
        for entity in catalog.entities where declaredTypes.contains(entity.type) {
            let pool = catalog.entities.filter { $0.type == entity.type }
            var probes = entity.forms.map(\.text)
            probes += entity.forms.compactMap(\.reading)
            for probe in probes {
                queries += 1
                guard indexed.contains(entity.type) else { continue }
                if EntityMatcher.search(probe, in: pool, semantic: true).contains(where: { $0.id == entity.id }) { hits += 1 }
            }
        }
        return IndexSimulation(coverage: coverage, queries: queries, hits: hits)
    }

    static func fails(_ o: CaseOutcome, _ classes: Set<FailureClass>) -> Bool {
        o.failure.map(classes.contains) ?? false
    }

    public static func auditHealth(_ audit: AuditReport) -> Double {
        max(0, 100 - audit.findings.reduce(0) { $0 + (severityPenalty[$1.severity] ?? 0) })
    }

    public static func score(outcomes: [CaseOutcome], audit: AuditReport, index: IndexSimulation) -> ScoreBreakdown {
        func ratio(_ subset: [CaseOutcome], pass: (CaseOutcome) -> Bool) -> (Double?, Int, Int) {
            let passed = subset.filter(pass).count
            return (subset.isEmpty ? nil : 100 * Double(passed) / Double(subset.count), passed, subset.count)
        }
        let isDiscovered: (CaseOutcome) -> Bool = { $0.failure != .f1 && $0.failure != .f2 }
        let discovered = outcomes.filter(isDiscovered)

        let d = ratio(outcomes, pass: isDiscovered)
        let named = discovered.filter { $0.benchCase.referenceKind == .name }
        let e = ratio(named) { !Self.fails($0, [.f3, .f4, .f5]) }
        let contextual = discovered.filter { $0.benchCase.referenceKind == .onScreen || $0.benchCase.referenceKind == .priorTurn }
        let o = ratio(contextual) { !Self.fails($0, [.f3, .f5, .f6, .f7]) }

        let indexValue = 100 * (indexCoverageShare * index.coverage + (1 - indexCoverageShare) * index.simulatedRecall)
        let health = auditHealth(audit)
        let routed = discovered.filter { $0.result.declaredRouting != nil }
        let privacy = ratio(routed) { !$0.result.notes.contains(.routingMismatch) }
        let staticValue = auditHealthShare * health + (1 - auditHealthShare) * (privacy.0 ?? 100)

        let components = [
            ComponentScore(component: .discoverability, value: d.0, weight: scoreWeights[.discoverability]!, passed: d.1, total: d.2,
                           note: "cases whose action reached the expected App Intent (not F1/F2)"),
            ComponentScore(component: .entityResolution, value: e.0, weight: scoreWeights[.entityResolution]!, passed: e.1, total: e.2,
                           note: "name-referenced cases without F3/F4/F5, among discovered cases"),
            ComponentScore(component: .indexRecall, value: indexValue, weight: scoreWeights[.indexRecall]!, passed: index.hits, total: index.queries,
                           note: String(format: "Phase 1 stand-in: %.0f%% × C2 coverage (%.0f%%) + %.0f%% × simulated recall (%.0f%%); not a Spotlight measurement",
                                        indexCoverageShare * 100, index.coverage * 100, (1 - indexCoverageShare) * 100, index.simulatedRecall * 100)),
            ComponentScore(component: .onScreenMultiTurn, value: o.0, weight: scoreWeights[.onScreenMultiTurn]!, passed: o.1, total: o.2,
                           note: "on-screen and previous-turn cases without F3/F5/F6/F7, among discovered cases"),
            ComponentScore(component: .staticHealth, value: staticValue, weight: scoreWeights[.staticHealth]!, passed: privacy.1, total: privacy.2,
                           note: String(format: "%.0f%% × audit health (%.0f) + %.0f%% × privacy-routing conformance (%.0f%%)",
                                        auditHealthShare * 100, health, (1 - auditHealthShare) * 100, privacy.0 ?? 100)),
        ]
        let available = components.filter { $0.value != nil }
        let weightSum = available.reduce(0) { $0 + $1.weight }
        let overall = weightSum == 0 ? 0 : available.reduce(0) { $0 + $1.weight * $1.value! } / weightSum
        return ScoreBreakdown(overall: overall, components: components)
    }
}
