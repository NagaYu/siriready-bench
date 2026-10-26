import XCTest
@testable import SiriReadyCore

final class ScoringTests: XCTestCase {
    func testWeightsAreFixed() {
        XCTAssertEqual(scoreWeights, [
            .discoverability: 0.25, .entityResolution: 0.25, .indexRecall: 0.15, .onScreenMultiTurn: 0.15, .staticHealth: 0.20,
        ])
        XCTAssertEqual(scoreWeights.values.reduce(0, +), 1, accuracy: 1e-12)
        XCTAssertEqual(severityPenalty, [.critical: 30, .high: 15, .medium: 7, .low: 2])
        XCTAssertEqual(auditHealthShare, 0.7)
        XCTAssertEqual(indexCoverageShare, 0.5)
        XCTAssertEqual(ScoreComponent.allCases.count, 5)
    }

    func audit(_ severities: [Severity]) -> AuditReport {
        AuditReport(appId: "messages", appPath: "x", findings: severities.map {
            Finding(check: .c2, severity: $0, location: nil, reason: "", suggestion: "", relatedFailure: nil)
        }, indexCoverage: 0.5, annotationCoverage: 1, counts: [:])
    }

    func testScoreMatchesHandComputedValue() {
        let named = benchCase(id: "messages-en-001")
        let onScreen = benchCase(id: "messages-en-002", screen: "contact_list", visible: ["c_alex"])
        let outcomes = [
            CaseOutcome(benchCase: named, result: resolution(), failure: nil),
            CaseOutcome(benchCase: named, result: resolution(notes: [.entityTypeNotIndexed]), failure: .f4),
            CaseOutcome(benchCase: onScreen, result: resolution(mode: .onScreen, notes: [.viewNotAnnotated]), failure: .f6),
            CaseOutcome(benchCase: named, result: resolution(intent: nil, declared: nil), failure: .f1),
        ]
        let score = Scorer.score(outcomes: outcomes, audit: audit([.high]), index: IndexSimulation(coverage: 0.5, queries: 4, hits: 3))
        let values = Dictionary(uniqueKeysWithValues: score.components.map { ($0.component, $0.value) })
        XCTAssertEqual(values[.discoverability]!!, 75, accuracy: 1e-9)      // 3 of 4 reached the intent
        XCTAssertEqual(values[.entityResolution]!!, 50, accuracy: 1e-9)     // 1 of 2 named cases
        XCTAssertEqual(values[.indexRecall]!!, 62.5, accuracy: 1e-9)        // 0.5·50 + 0.5·75
        XCTAssertEqual(values[.onScreenMultiTurn]!!, 0, accuracy: 1e-9)     // 0 of 1
        XCTAssertEqual(values[.staticHealth]!!, 89.5, accuracy: 1e-9)       // 0.7·85 + 0.3·100
        XCTAssertEqual(score.overall, 0.25 * 75 + 0.25 * 50 + 0.15 * 62.5 + 0.15 * 0 + 0.20 * 89.5, accuracy: 1e-9)
        XCTAssertEqual(score.overall, 58.525, accuracy: 1e-9)
    }

    func testComponentWithoutCasesIsRedistributed() {
        let outcomes = [CaseOutcome(benchCase: benchCase(), result: resolution(), failure: nil)]
        let score = Scorer.score(outcomes: outcomes, audit: audit([]), index: IndexSimulation(coverage: 1, queries: 1, hits: 1))
        XCTAssertNil(score.components.first { $0.component == .onScreenMultiTurn }?.value)
        XCTAssertEqual(score.overall, 100, accuracy: 1e-9)
    }

    func testPrivacyMismatchLowersStaticHealth() {
        let outcomes = [
            CaseOutcome(benchCase: benchCase(), result: resolution(), failure: nil),
            CaseOutcome(benchCase: benchCase(), result: resolution(notes: [.routingMismatch]), failure: .f8),
        ]
        let score = Scorer.score(outcomes: outcomes, audit: audit([.critical, .critical, .critical, .critical]), index: IndexSimulation(coverage: 1, queries: 0, hits: 0))
        let health = score.components.first { $0.component == .staticHealth }!.value!
        XCTAssertEqual(health, 0.7 * 0 + 0.3 * 50, accuracy: 1e-9, "audit health floors at 0")
    }

    func testClassification() {
        let named = benchCase()
        XCTAssertNil(Scorer.classify(named, resolution()))
        XCTAssertEqual(Scorer.classify(named, resolution(intent: nil)), .f1)
        XCTAssertEqual(Scorer.classify(named, resolution(intent: "DraftMessageIntent")), .f2)
        XCTAssertEqual(Scorer.classify(named, resolution(entityId: "c_anjali")), .f3)
        XCTAssertEqual(Scorer.classify(named, resolution(entityId: nil, resolution: "none", notes: [.entityTypeNotIndexed])), .f4)
        XCTAssertEqual(Scorer.classify(named, resolution(entityId: nil, resolution: "disambiguate", candidates: ["c_alex", "c_anjali"])), .f5,
                       "asking although unambiguous")
        let ambiguous = benchCase(entityId: nil, resolution: "disambiguate", candidates: ["c_samlee_work", "c_samlee_gym"])
        XCTAssertEqual(Scorer.classify(ambiguous, resolution(entityId: "c_samlee_work", notes: [.pickedFirstWithoutDisambiguation])), .f5)
        XCTAssertNil(Scorer.classify(ambiguous, resolution(entityId: nil, resolution: "disambiguate", candidates: ["c_samlee_work", "c_samlee_gym"])))
        let screen = benchCase(screen: "message_detail", visible: ["msg_en_01"])
        XCTAssertEqual(Scorer.classify(screen, resolution(entityId: nil, resolution: "none", mode: .onScreen, notes: [.viewNotAnnotated])), .f6)
        let prior = benchCase(prior: PriorTurn(utterance: "Open my chat with Alex Rivera", intent: "OpenConversationIntent", entityId: "conv_c_alex"))
        XCTAssertEqual(Scorer.classify(prior, resolution(entityId: nil, resolution: "none", mode: .priorTurn, notes: [.priorTurnUnresolvable])), .f7)
        XCTAssertEqual(Scorer.classify(named, resolution(notes: [.routingMismatch])), .f8)
        XCTAssertEqual(Scorer.classify(named, resolution(entityId: "c_anjali", notes: [.routingMismatch])), .f3, "the first failing stage wins")
    }

    func testReferenceKindIsDerivedFromTheCase() {
        XCTAssertEqual(benchCase().referenceKind, .name)
        XCTAssertEqual(benchCase(entityId: nil).referenceKind, .none)
        XCTAssertEqual(benchCase(screen: "message_detail", visible: ["msg_en_01"]).referenceKind, .onScreen)
        XCTAssertEqual(benchCase(prior: PriorTurn(utterance: "", intent: "SendMessageIntent", entityId: "c_alex")).referenceKind, .priorTurn)
    }

    func testReportsSayMockAndCarryConditions() throws {
        let ok = try Repo.bench("messages_ok")
        let broken = try Repo.bench("messages_broken")
        let md = ReportRenderer.markdown(broken)
        XCTAssertTrue(md.contains("(MOCK)"))
        XCTAssertTrue(md.contains("not** measurements of Siri"))
        XCTAssertTrue(md.contains("Target OS | not measured (MOCK)"))
        XCTAssertTrue(md.contains("| F4 | Not Indexed | 204 |"))
        XCTAssertTrue(md.contains("C1 Companion schema"))
        let compare = ReportRenderer.comparisonMarkdown(ok, broken)
        XCTAssertTrue(compare.contains("Siri Visibility Score (MOCK)"))
        XCTAssertFalse(compare.contains("not comparable"))
        let roundTrip = try JSONDecoder().decode(BenchResult.self, from: try Bench.encode(broken))
        XCTAssertEqual(ReportRenderer.markdown(roundTrip), md)
    }
}
