import Foundation

// Real-run pipeline (Phase 2, Track B).
//
//   plan    (host, here)      MOCK decides what Siri would have done up to "which intent, which
//                             target, which slot values"; F1/F2 stay MOCK by design.
//   harness (UI-testing)      executes the plan with AppIntentsTesting against the built app and
//                             returns raw observations only (Apps/Harness).
//   ingest  (host, here)      turns raw observations into F-classes and scores, tagging every
//                             component with its provenance (real / mock / static).
//
// The UI-testing target never classifies or scores; all of that is here and testable offline.

public let harnessProtocolVersion = "siriready-harness-v1"

public struct PlanCase: Codable, Equatable, Sendable {
    public var caseId: String
    /// MOCK verdict before any real stage; F1/F2 cases are not executed.
    public var mockFailure: FailureClass?
    public var intent: String?
    public var targetType: String?
    public var mode: ReferenceKind
    public var mention: String?
    public var screen: String?
    public var visible: [String]
    public var visibleType: String?
    public var priorEntityId: String?
    public var priorEntityType: String?
    /// Entity the MOCK chose (qualifier / ordinal / relation logic); the harness passes it to run().
    public var targetId: String?
    /// Slot values from MOCK slot filling; `start` is an ISO-8601 date for calendar intents.
    public var params: [String: String]
    public var expectDisambiguation: Bool
}

public struct IndexProbe: Codable, Equatable, Sendable {
    public var entityId: String
    public var entityType: String
    public var query: String
}

public struct RunPlan: Codable, Sendable {
    public var protocolVersion = harnessProtocolVersion
    public var appFixture: String
    public var bundleIdentifier: String
    public var casesFingerprint: String
    public var cases: [PlanCase]
    public var indexProbes: [IndexProbe]
}

public struct LookupResult: Codable, Equatable, Sendable {
    public var ids: [String]
    public var error: String?

    public init(ids: [String], error: String? = nil) {
        self.ids = ids
        self.error = error
    }
}

public struct RunObservation: Codable, Equatable, Sendable {
    public var ok: Bool
    public var targetId: String?
    public var errorDomain: String?
    public var errorCode: Int?
    public var errorMessage: String?

    /// AppIntents reports app-requested disambiguation as an execution error in a test context.
    public var requestedDisambiguation: Bool {
        errorDomain == "AppIntentsServicesExecutionErrorDomain" && (errorMessage ?? "").contains("disambiguation")
    }
}

public struct ObservedEffect: Codable, Equatable, Sendable {
    public var intent: String
    public var target: String?
    public var params: [String: String]
}

public struct RawCaseResult: Codable, Equatable, Sendable {
    public var caseId: String
    public var intentAvailable: Bool?
    public var stringQuery: LookupResult?
    public var spotlight: LookupResult?
    public var annotations: LookupResult?
    public var priorFetch: LookupResult?
    public var run: RunObservation?
    public var effects: [ObservedEffect]
    public var egress: [String]
    public var notes: [String]
}

public struct RawIndexProbe: Codable, Equatable, Sendable {
    public var entityId: String
    public var entityType: String
    public var query: String
    public var ids: [String]
    public var error: String?
}

public struct RawRun: Codable, Sendable {
    public var protocolVersion: String
    public var bundleIdentifier: String
    public var device: String
    public var osVersion: String
    public var cases: [RawCaseResult]
    public var indexProbes: [RawIndexProbe]
}

// MARK: - Plan

public enum RunPlanner {
    public static func plan(model: AppModel, catalog: EntityCatalog, cases: [BenchCase], bundleIdentifier: String,
                            casesFingerprint: String) -> RunPlan {
        let resolver = MockResolver(model: model, catalog: catalog)
        let planCases = cases.filter { $0.appId == model.manifest.appId }.map { c -> PlanCase in
            let r = resolver.resolve(c)
            let failure = Scorer.classify(c, r)
            let target = model.intent(named: r.intent ?? "").flatMap(model.targetEntityType(of:))
            let visibleType = c.state.visibleEntities.first.flatMap(catalog.entity)?.type
            let prior = c.state.priorTurn?.entityId.flatMap(catalog.entity)
            var params = ParamExtractor.extract(c.utterance, intent: r.intent, catalog: catalog)
            let targetId = r.entityId ?? r.candidates.first
            if r.intent == "UpdateEventIntent", let day = params["day"],
               let target = targetId.flatMap(catalog.entity),
               target.qualifiers.contains(where: { ParamExtractor.normalize($0) == ParamExtractor.normalize(day) }) {
                // "Move Friday's Vendor Sync to 3pm": the day names which event, not the new date.
                params["day"] = nil
            }
            if r.intent == "CreateEventIntent" || r.intent == "UpdateEventIntent" {
                let fallback = targetId.flatMap(catalog.entity)?.attrs["date"]
                params["start"] = ParamExtractor.startISO(day: params["day"], time: params["time"], fallbackDate: fallback)
            }
            return PlanCase(
                caseId: c.caseId, mockFailure: failure == .f1 || failure == .f2 ? failure : nil, intent: r.intent,
                targetType: target, mode: c.referenceKind, mention: c.mention, screen: c.state.screen,
                visible: c.state.visibleEntities, visibleType: visibleType, priorEntityId: prior?.id, priorEntityType: prior?.type,
                targetId: targetId, params: params, expectDisambiguation: c.expected.resolution == "disambiguate")
        }
        let types = Set(model.entities.map(\.name))
        var probes: [IndexProbe] = []
        for e in catalog.entities where types.contains(e.type) {
            var queries: [String] = []
            for f in e.forms {
                queries.append(f.text)
                if let r = f.reading { queries.append(r) }
            }
            var seen = Set<String>()
            for q in queries where seen.insert(q).inserted {
                probes.append(IndexProbe(entityId: e.id, entityType: e.type, query: q))
            }
        }
        return RunPlan(appFixture: model.root.lastPathComponent, bundleIdentifier: bundleIdentifier,
                       casesFingerprint: casesFingerprint, cases: planCases, indexProbes: probes)
    }
}

// MARK: - Ingest

/// A case after real evidence was applied.
public struct RealCaseOutcome: Codable, Sendable {
    public var caseId: String
    public var failure: FailureClass?
    /// Stage whose evidence decided the verdict: mock (F1/F2), real, or nil for a pass.
    public var decidedBy: Provenance?
    public var executionError: String?
    public var notMeasured: Bool
    public var trace: [String]
}

public struct MixedResult: Codable, Sendable {
    public var conditions: BenchConditions
    public var device: String
    public var osVersion: String
    public var mock: BenchResult
    public var real: [RealCaseOutcome]
    public var params: [ParamOutcome]
    public var index: IndexSimulation
    public var realIndexRecall: Double
    public var indexedTypesObserved: [String]
    public var score: ScoreBreakdownV2
    public var failureCounts: [String: Int]
    public var spotcheck: SpotcheckLog?
}

public enum RealScorer {
    static let realProvenance: [ComponentV2: [ProvenanceShare]] = [
        .discoverability: [ProvenanceShare(.mock, 1)],
        .entityResolution: [ProvenanceShare(.real, 1)],
        .parameterAccuracy: [ProvenanceShare(.mock, 0.5), ProvenanceShare(.real, 0.5)],
        .indexRecall: [ProvenanceShare(.staticAnalysis, indexCoverageShare), ProvenanceShare(.real, 1 - indexCoverageShare)],
        .onScreenMultiTurn: [ProvenanceShare(.real, 1)],
        .staticHealth: [ProvenanceShare(.staticAnalysis, auditHealthShare), ProvenanceShare(.real, 1 - auditHealthShare)],
    ]

    /// Classify one case from raw observations. `indexedTypes` are entity types for which at least
    /// one Spotlight probe returned a hit in this run (observed, not declared).
    public static func classify(_ c: BenchCase, plan: PlanCase, raw: RawCaseResult?, catalog: EntityCatalog,
                                declaredRouting: PrivacyRouting?, indexedTypes: Set<String>) -> RealCaseOutcome {
        var trace: [String] = []
        if let f = plan.mockFailure {
            return RealCaseOutcome(caseId: c.caseId, failure: f, decidedBy: .mock, executionError: nil, notMeasured: false,
                                   trace: ["MOCK: utterance did not reach \(c.expected.intent) (\(f.rawValue)); not executed"])
        }
        guard let raw else {
            return RealCaseOutcome(caseId: c.caseId, failure: nil, decidedBy: nil, executionError: nil, notMeasured: true,
                                   trace: ["no raw result from the harness"])
        }
        func outcome(_ f: FailureClass?, _ note: String? = nil, error: String? = nil) -> RealCaseOutcome {
            if let note { trace.append(note) }
            return RealCaseOutcome(caseId: c.caseId, failure: f, decidedBy: f == nil ? nil : .real, executionError: error, notMeasured: false, trace: trace)
        }
        if raw.intentAvailable == false {
            return outcome(.f1, "\(plan.intent ?? "?") is not exposed by the app binary (AppIntentsTesting metadata)")
        }
        let expected = c.expected.entityId
        let needsEntity = expected != nil || c.expected.resolution == "disambiguate"
        let run = raw.run

        if needsEntity {
            switch plan.mode {
            case .onScreen:
                let annotated = Set(raw.annotations?.ids ?? [])
                trace.append("viewAnnotations(): \(annotated.sorted().joined(separator: ", "))")
                if !Set(plan.visible).isSubset(of: annotated) { return outcome(.f6, "visible entities are not all annotated") }
                if c.expected.resolution == "disambiguate" {
                    return outcome(nil, "all visible entities are annotated; the system can ask which one (app side not observable)")
                }
            case .priorTurn:
                let fetched = raw.priorFetch?.ids ?? []
                if let p = plan.priorEntityId, !fetched.contains(p) { return outcome(.f7, "previous-turn entity \(p) could not be re-fetched") }
            case .name:
                let found = (raw.spotlight?.ids ?? []) + (raw.stringQuery?.ids ?? [])
                trace.append("spotlightQuery: [\((raw.spotlight?.ids ?? []).joined(separator: ", "))] entities(matching:): [\((raw.stringQuery?.ids ?? []).joined(separator: ", "))]")
                let wanted = expected.map { [$0] } ?? c.expected.candidates
                if !wanted.contains(where: found.contains) {
                    let type = plan.targetType ?? ""
                    return outcome(indexedTypes.contains(type) ? .f3 : .f4,
                                   indexedTypes.contains(type) ? "expected entity not returned by Spotlight or the string query"
                                                               : "\(type) has no Spotlight hits in this run and the string query missed")
                }
            case .none:
                break
            }
            if c.expected.resolution == "disambiguate", plan.mode != .onScreen {
                if run?.requestedDisambiguation == true { return outcome(nil, "app requested disambiguation") }
                return outcome(.f5, "ambiguous request executed without disambiguation")
            }
            if run?.requestedDisambiguation == true { return outcome(.f5, "app asked although the request named one entity") }
            if let effectTarget = raw.effects.first?.target, let expected, effectTarget != expected {
                let siblings = catalog.entity(expected).map { e in catalog.entities.filter { $0.type == e.type && $0.forms.first?.text == e.forms.first?.text }.map(\.id) } ?? []
                let f: FailureClass = siblings.contains(effectTarget) ? .f5 : (plan.mode == .onScreen ? .f6 : plan.mode == .priorTurn ? .f7 : .f3)
                return outcome(f, "app acted on \(effectTarget) instead of \(expected)")
            }
        }
        if let run, !run.ok, !run.requestedDisambiguation {
            let message = "\(run.errorDomain ?? "error") \(run.errorCode.map(String.init) ?? ""): \(run.errorMessage ?? "")"
            return outcome(nil, "run() failed", error: message)
        }
        if declaredRouting == .onDeviceOnly && !raw.egress.isEmpty {
            return outcome(.f8, "declared on_device_only but the app attempted to reach \(raw.egress.joined(separator: ", ")) (intercepted locally)")
        }
        return outcome(nil, run == nil ? "no execution recorded" : "executed")
    }

    /// Expected effect values for the parameters the app persists.
    static func expectedEffect(_ c: BenchCase, catalog: EntityCatalog) -> [String: String] {
        var out: [String: String] = [:]
        for (k, v) in c.expected.params where ["body", "title", "invitee", "is_read", "location", "calendar"].contains(k) { out[k] = v.description }
        if c.expected.intent == "CreateEventIntent" || c.expected.intent == "UpdateEventIntent" {
            let p = c.expected.params
            let fallback = c.expected.entityId.flatMap(catalog.entity)?.attrs["date"]
            out["start"] = ParamExtractor.startISO(day: p["day"]?.description, time: p["time"]?.description, fallbackDate: fallback)
        }
        return out
    }

    public static func ingest(mock: BenchResult, model: AppModel, catalog: EntityCatalog, plan: RunPlan, raw: RawRun,
                              spotcheck: SpotcheckLog? = nil) -> MixedResult {
        let rawByCase = Dictionary(raw.cases.map { ($0.caseId, $0) }, uniquingKeysWith: { a, _ in a })
        let planByCase = Dictionary(uniqueKeysWithValues: plan.cases.map { ($0.caseId, $0) })
        var indexedTypes = Set<String>()
        var hits = 0
        for p in raw.indexProbes where p.ids.contains(p.entityId) {
            hits += 1
            indexedTypes.insert(p.entityType)
        }
        let realRecall = raw.indexProbes.isEmpty ? 0 : Double(hits) / Double(raw.indexProbes.count)

        var real: [RealCaseOutcome] = []
        var params: [ParamOutcome] = []
        var mixedOutcomes: [CaseOutcome] = []
        for o in mock.outcomes {
            let c = o.benchCase
            guard let p = planByCase[c.caseId] else { continue }
            let r = rawByCase[c.caseId]
            let verdict = classify(c, plan: p, raw: r, catalog: catalog, declaredRouting: model.manifest.routing(for: p.intent ?? ""),
                                   indexedTypes: indexedTypes)
            real.append(verdict)
            // Mixed scores cover only cases with evidence: executed against the app, or stopped at MOCK F1/F2.
            if !verdict.notMeasured {
                var mixed = o
                mixed.failure = verdict.failure
                // Static Health's routing share counts real egress, not the MOCK's source evidence.
                mixed.result.notes.removeAll { $0 == .routingMismatch }
                if verdict.failure == .f8 { mixed.result.notes.append(.routingMismatch) }
                mixedOutcomes.append(mixed)
            }
            if p.mockFailure == nil, !c.expected.params.isEmpty, r != nil {
                let extracted = ParamExtractor.extract(c.utterance, intent: p.intent, catalog: catalog)
                let expectedEffect = expectedEffect(c, catalog: catalog)
                let effect = r?.effects.first { $0.intent == c.expected.intent }
                // Parameters are judged only where the intent actually ran (or failed for another reason);
                // cases stopped earlier already count against entity resolution and are not counted twice.
                let executed: Bool?
                if let run = r?.run, run.ok {
                    executed = effect.map { e in expectedEffect.allSatisfy { e.params[$0.key].map(ParamExtractor.normalize) == ParamExtractor.normalize($0.value) } } ?? false
                } else if let run = r?.run, !run.requestedDisambiguation {
                    executed = false
                } else {
                    executed = nil
                }
                if executed != nil {
                    params.append(ParamOutcome(caseId: c.caseId, extracted: extracted,
                                               extractionCorrect: ParamExtractor.matches(expected: c.expected.params, actual: extracted),
                                               executionCorrect: executed))
                }
            }
        }
        let index = IndexSimulation(coverage: mock.index.coverage, queries: raw.indexProbes.count, hits: hits)
        let v1 = Scorer.score(outcomes: mixedOutcomes, audit: mock.audit, index: index)
        var score = ScorerV2.score(v1: v1, params: params, provenance: realProvenance,
                                   paramPass: { $0.extractionCorrect && $0.executionCorrect == true },
                                   paramNote: "executed cases: MOCK slot filling matches expected.params AND the app persisted those values (observed effect)")
        if let i = score.components.firstIndex(where: { $0.component == .indexRecall }) {
            score.components[i].note = String(format: "%.0f%% × C2 coverage (static, %.0f%%) + %.0f%% × Spotlight probe recall (real, %d/%d = %.0f%%)",
                                              indexCoverageShare * 100, index.coverage * 100, (1 - indexCoverageShare) * 100,
                                              hits, raw.indexProbes.count, realRecall * 100)
        }
        var counts: [String: Int] = [:]
        for f in FailureClass.allCases { counts[f.rawValue] = 0 }
        for v in real { if let f = v.failure { counts[f.rawValue, default: 0] += 1 } }
        return MixedResult(conditions: mock.conditions, device: raw.device, osVersion: raw.osVersion, mock: mock, real: real,
                           params: params, index: index, realIndexRecall: realRecall, indexedTypesObserved: indexedTypes.sorted(),
                           score: score, failureCounts: counts, spotcheck: spotcheck)
    }
}
