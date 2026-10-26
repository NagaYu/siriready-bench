import XCTest
@testable import SiriReadyCore

/// Phase 2: raw harness observations → F-classes → v2 score, all offline with fixed inputs.
final class RealRunTests: XCTestCase {
    var catalog: EntityCatalog!

    override func setUpWithError() throws {
        catalog = try DatasetLoader.loadCatalog(Repo.root.appendingPathComponent("dataset/v1.2/entities/messages.json"))
    }

    func plan(_ c: BenchCase, intent: String? = nil, mode: ReferenceKind? = nil, target: String? = "c_alex", type: String = "ContactEntity",
              mockFailure: FailureClass? = nil, prior: String? = nil) -> PlanCase {
        PlanCase(caseId: c.caseId, mockFailure: mockFailure, intent: intent ?? c.expected.intent, targetType: type, mode: mode ?? c.referenceKind,
                 mention: "Alex Rivera", screen: c.state.screen, visible: c.state.visibleEntities, visibleType: "MessageEntity",
                 priorEntityId: prior, priorEntityType: prior == nil ? nil : "ContactEntity", targetId: target,
                 params: [:], expectDisambiguation: c.expected.resolution == "disambiguate")
    }

    func raw(_ id: String = "messages-en-001", spotlight: [String] = ["c_alex"], query: [String] = [], run: RunObservation? = RunObservation(ok: true),
             effects: [ObservedEffect]? = nil, egress: [String] = [], annotations: [String]? = nil, prior: [String]? = nil,
             available: Bool? = true) -> RawCaseResult {
        RawCaseResult(caseId: id, intentAvailable: available, stringQuery: LookupResult(ids: query), spotlight: LookupResult(ids: spotlight),
                      annotations: annotations.map { LookupResult(ids: $0) }, priorFetch: prior.map { LookupResult(ids: $0) }, run: run,
                      effects: effects ?? [ObservedEffect(intent: "SendMessageIntent", target: "c_alex", params: ["body": "hi"])],
                      egress: egress, notes: [])
    }

    static let disambiguationError = RunObservation(
        ok: false, targetId: "c_samlee_work", errorDomain: "AppIntentsServicesExecutionErrorDomain", errorCode: 206,
        errorMessage: "Unsupported operation: The App Intent requested disambiguation for parameter 'destination', which is not supported by the default delegate")

    func classify(_ c: BenchCase, _ p: PlanCase, _ r: RawCaseResult?, routing: PrivacyRouting? = .onDeviceOnly,
                  indexed: Set<String> = ["ContactEntity"]) -> RealCaseOutcome {
        RealScorer.classify(c, plan: p, raw: r, catalog: catalog, declaredRouting: routing, indexedTypes: indexed)
    }

    func testPassingCase() {
        let c = benchCase()
        let v = classify(c, plan(c), raw())
        XCTAssertNil(v.failure)
        XCTAssertNil(v.decidedBy)
        XCTAssertFalse(v.notMeasured)
    }

    func testMockStagesStayMock() {
        let c = benchCase()
        let v = classify(c, plan(c, mockFailure: .f2), nil)
        XCTAssertEqual(v.failure, .f2)
        XCTAssertEqual(v.decidedBy, .mock)
    }

    func testMissingIntentInBinaryIsRealF1() {
        let c = benchCase(intent: "DraftMessageIntent")
        let v = classify(c, plan(c), raw(run: RunObservation(ok: false, errorDomain: "AppIntentsServicesMetadataErrorDomain", errorCode: 401,
                                                         errorMessage: "dev.siriready.messages.broken does not expose any AppIntent named DraftMessageIntent"),
                                         available: false))
        XCTAssertEqual(v.failure, .f1)
        XCTAssertEqual(v.decidedBy, .real)
    }

    func testNotIndexedVersusMisresolved() {
        let c = benchCase()
        XCTAssertEqual(classify(c, plan(c), raw(spotlight: [], query: []), indexed: []).failure, .f4)
        XCTAssertEqual(classify(c, plan(c), raw(spotlight: [], query: [])).failure, .f3)
        XCTAssertEqual(classify(c, plan(c), raw(spotlight: ["c_anjali"], query: [])).failure, .f3)
        XCTAssertNil(classify(c, plan(c), raw(spotlight: [], query: ["c_alex"]), indexed: []).failure, "string query alone is enough")
    }

    func testDisambiguation() {
        let ambiguous = benchCase(entityId: nil, resolution: "disambiguate", candidates: ["c_samlee_work", "c_samlee_gym"])
        let p = plan(ambiguous, target: "c_samlee_work")
        XCTAssertNil(classify(ambiguous, p, raw(spotlight: ["c_samlee_work", "c_samlee_gym"], run: Self.disambiguationError)).failure)
        XCTAssertEqual(classify(ambiguous, p, raw(spotlight: ["c_samlee_work", "c_samlee_gym"],
                                                  effects: [ObservedEffect(intent: "SendMessageIntent", target: "c_samlee_work", params: [:])])).failure, .f5)
        // Asking although the request already named one entity is also a disambiguation failure.
        let named = benchCase(entityId: "c_samlee_work")
        XCTAssertEqual(classify(named, plan(named, target: "c_samlee_work"), raw(spotlight: ["c_samlee_work"], run: Self.disambiguationError)).failure, .f5)
    }

    func testActingOnAnotherEntity() {
        let c = benchCase(entityId: "c_samlee_work")
        let sibling = raw(spotlight: ["c_samlee_work"], effects: [ObservedEffect(intent: "SendMessageIntent", target: "c_samlee_gym", params: [:])])
        XCTAssertEqual(classify(c, plan(c, target: "c_samlee_work"), sibling).failure, .f5, "silently picked a same-name sibling")
        let other = raw(spotlight: ["c_samlee_work"], effects: [ObservedEffect(intent: "SendMessageIntent", target: "c_anjali", params: [:])])
        XCTAssertEqual(classify(c, plan(c, target: "c_samlee_work"), other).failure, .f3)
    }

    func testOnScreenAndPreviousTurn() {
        let screen = benchCase(intent: "SetMessageReadStatusIntent", entityId: "msg_en_01", screen: "message_detail", visible: ["msg_en_01"])
        let p = plan(screen, target: "msg_en_01", type: "MessageEntity")
        XCTAssertEqual(classify(screen, p, raw(annotations: [])).failure, .f6)
        XCTAssertNil(classify(screen, p, raw(effects: [ObservedEffect(intent: "SetMessageReadStatusIntent", target: "msg_en_01", params: [:])],
                                             annotations: ["msg_en_01"])).failure)
        let prior = benchCase(prior: PriorTurn(utterance: "Open my chat with Alex Rivera", intent: "OpenConversationIntent", entityId: "c_alex"))
        XCTAssertEqual(classify(prior, plan(prior, prior: "c_alex"), raw(prior: [])).failure, .f7)
        XCTAssertNil(classify(prior, plan(prior, prior: "c_alex"), raw(prior: ["c_alex"])).failure)
    }

    func testPrivacyRoutingUsesObservedEgress() {
        let c = benchCase()
        XCTAssertEqual(classify(c, plan(c), raw(egress: ["geo.orbit.example"])).failure, .f8)
        XCTAssertNil(classify(c, plan(c), raw(egress: ["invites.orbit.example"]), routing: .cloudAllowed).failure)
        XCTAssertNil(classify(c, plan(c), raw(egress: [])).failure, "declared on_device_only and nothing left the app")
    }

    func testParamsAreJudgedOnlyWhereTheIntentRan() throws {
        let app = Repo.fixture("messages_ok")
        let casesURL = Repo.root.appendingPathComponent("dataset/v1.2/cases_dev.jsonl")
        let mock = try Bench.run(appDirectory: app, casesURL: casesURL)
        let model = try AppModelLoader.load(appDirectory: app)
        let cases = try DatasetLoader.loadCases(casesURL)
        let plan = RunPlanner.plan(model: model, catalog: catalog, cases: cases, bundleIdentifier: "b", casesFingerprint: "x")
        let ids = ["messages-en-001", "messages-en-002", "messages-en-003", "messages-en-004"]
        let body = { (id: String) in cases.first { $0.caseId == id }!.expected.params["body"]!.description }
        let target = { (id: String) in cases.first { $0.caseId == id }!.expected.entityId }
        let raws = [
            raw(ids[0], spotlight: [target(ids[0])!], effects: [ObservedEffect(intent: "SendMessageIntent", target: target(ids[0]), params: ["body": body(ids[0])])]),
            raw(ids[1], spotlight: [target(ids[1])!], effects: [ObservedEffect(intent: "SendMessageIntent", target: target(ids[1]), params: ["body": "something else"])]),
            raw(ids[2], spotlight: [], run: nil, effects: []),                              // stopped at entity resolution
            raw(ids[3], spotlight: [target(ids[3])!], run: Self.disambiguationError, effects: []),  // asked
        ]
        let run = RawRun(protocolVersion: harnessProtocolVersion, bundleIdentifier: "b", device: "test", osVersion: "iOS 27.0", cases: raws, indexProbes: [])
        let mixed = RealScorer.ingest(mock: mock, model: model, catalog: catalog, plan: plan, raw: run)
        XCTAssertEqual(mixed.params.map(\.caseId), [ids[0], ids[1]])
        XCTAssertEqual(mixed.params.map(\.executionCorrect), [true, false])
        let accuracy = try XCTUnwrap(mixed.score.components.first { $0.component == .parameterAccuracy })
        XCTAssertEqual(accuracy.value, 50)
        XCTAssertEqual(accuracy.provenance, [ProvenanceShare(.mock, 0.5), ProvenanceShare(.real, 0.5)])
    }

    func testOtherExecutionErrorsAreReportedNotClassified() {
        let c = benchCase()
        let v = classify(c, plan(c), raw(run: RunObservation(ok: false, errorDomain: "SomeDomain", errorCode: 1, errorMessage: "boom")))
        XCTAssertNil(v.failure)
        XCTAssertEqual(v.executionError, "SomeDomain 1: boom")
    }

    func testRealHarnessOutputDecodes() throws {
        // First cases and probes of a real AppIntentsTesting run (results/phase4/messages_ok/raw.json), trimmed.
        let raw = try JSONDecoder().decode(RawRun.self, from: Data(contentsOf: Repo.root.appendingPathComponent("Tests/fixtures/raw_smoke_messages_ok.json")))
        XCTAssertEqual(raw.protocolVersion, harnessProtocolVersion)
        XCTAssertEqual(raw.bundleIdentifier, "dev.siriready.messages.ok")
        XCTAssertEqual(raw.cases.count, 3)
        XCTAssertTrue(raw.cases.allSatisfy { $0.run?.ok == true && $0.effects.count == 1 })
        XCTAssertFalse(raw.indexProbes.isEmpty)
    }

    func testIngestTagsProvenanceAndSkipsUnmeasuredCases() throws {
        let app = Repo.fixture("messages_ok")
        let cases = Repo.root.appendingPathComponent("dataset/v1.2/cases_dev.jsonl")
        let mock = try Bench.run(appDirectory: app, casesURL: cases)
        let model = try AppModelLoader.load(appDirectory: app)
        let plan = RunPlanner.plan(model: model, catalog: catalog, cases: try DatasetLoader.loadCases(cases),
                                   bundleIdentifier: "dev.siriready.messages.ok", casesFingerprint: "x")
        let raw = try JSONDecoder().decode(RawRun.self, from: Data(contentsOf: Repo.root.appendingPathComponent("Tests/fixtures/raw_smoke_messages_ok.json")))
        let mixed = RealScorer.ingest(mock: mock, model: model, catalog: catalog, plan: plan, raw: raw)

        XCTAssertEqual(mixed.real.filter { !$0.notMeasured && $0.decidedBy != .mock }.count, 3)
        XCTAssertEqual(mixed.params.count, 3, "only executed cases are scored for parameters")
        XCTAssertTrue(mixed.params.allSatisfy { $0.extractionCorrect && $0.executionCorrect == true })
        let source = Dictionary(uniqueKeysWithValues: mixed.score.components.map { ($0.component, $0.provenance) })
        XCTAssertEqual(source[.discoverability], [ProvenanceShare(.mock, 1)])
        XCTAssertEqual(source[.entityResolution], [ProvenanceShare(.real, 1)])
        XCTAssertEqual(source[.indexRecall], [ProvenanceShare(.staticAnalysis, 0.5), ProvenanceShare(.real, 0.5)])
        XCTAssertEqual(mixed.score.provenance.reduce(0) { $0 + $1.share }, 1, accuracy: 1e-9)
        XCTAssertTrue(mixed.score.components.first { $0.component == .indexRecall }!.note.contains("Spotlight probe recall (real"))

        let md = ReportRenderer.mixedMarkdown(mixed)
        XCTAssertTrue(md.contains("(MOCK + REAL)"))
        XCTAssertTrue(md.contains("| Entity Resolution | 20% |") && md.contains("| real |"))
        XCTAssertTrue(md.contains("F1/F2 (does the utterance reach the intent?) is always MOCK"))
    }

    func testPlanStopsAtMockF1AndCarriesSlots() throws {
        let cases = try DatasetLoader.loadCases(Repo.root.appendingPathComponent("dataset/v1.2/cases_dev.jsonl"))
        let broken = RunPlanner.plan(model: try Repo.model("messages_broken"), catalog: catalog, cases: cases,
                                     bundleIdentifier: "b", casesFingerprint: "x")
        let drafts = broken.cases.filter { id in cases.first { $0.caseId == id.caseId }?.expected.intent == "DraftMessageIntent" }
        XCTAssertTrue(drafts.allSatisfy { $0.mockFailure == .f1 })
        let cal = try DatasetLoader.loadCatalog(Repo.root.appendingPathComponent("dataset/v1.2/entities/calendar.json"))
        let eval = try DatasetLoader.loadCases(Repo.root.appendingPathComponent("dataset/v1.2/cases_eval.jsonl"))
        let p = RunPlanner.plan(model: try Repo.model("calendar_ok"), catalog: cal, cases: eval, bundleIdentifier: "c", casesFingerprint: "x")
        let first = try XCTUnwrap(p.cases.first { $0.caseId == "calendar-en-001" })
        XCTAssertEqual(first.intent, "CreateEventIntent")
        XCTAssertNotNil(first.params["start"])
        XCTAssertEqual(Set(p.indexProbes.map(\.entityType)), ["EventEntity", "CalendarEntity"])
        // A qualifier day picks the event; it is not the new date.
        let qualified = try XCTUnwrap(p.cases.first { $0.caseId == "calendar-en-157" })
        XCTAssertNil(qualified.params["day"])
        XCTAssertEqual(qualified.params["start"], "2026-11-13T10:30:00Z")
    }
}

final class ParamsAndProvenanceTests: XCTestCase {
    func testWeightsV2AreFixed() {
        XCTAssertEqual(scoreWeightsV2, [.discoverability: 0.20, .entityResolution: 0.20, .parameterAccuracy: 0.10,
                                        .indexRecall: 0.15, .onScreenMultiTurn: 0.15, .staticHealth: 0.20])
        XCTAssertEqual(scoreWeightsV2.values.reduce(0, +), 1, accuracy: 1e-12)
        XCTAssertEqual(scoreWeights.count, 5, "Phase 1 weights are untouched")
    }

    func testExtractionPositiveExamples() {
        XCTAssertEqual(ParamExtractor.extract("Send Alex Rivera a message saying see you at the station", intent: "SendMessageIntent"),
                       ["body": "see you at the station"])
        XCTAssertEqual(ParamExtractor.extract("Start a message to Alex saying lunch is on me today but don't send it", intent: "DraftMessageIntent"),
                       ["body": "lunch is on me today"])
        XCTAssertEqual(ParamExtractor.extract("高瀬美月に「10分遅れます」って送ってもらえる？", intent: "SendMessageIntent"), ["body": "10分遅れます"])
        XCTAssertEqual(ParamExtractor.extract("I need you to add Dentist appointment on Friday at 4:30pm", intent: "CreateEventIntent"),
                       ["title": "Dentist appointment", "day": "friday", "time": "4:30pm"])
        XCTAssertEqual(ParamExtractor.extract("明日10時半からヨガ教室の予定を作って", intent: "CreateEventIntent"),
                       ["title": "ヨガ教室", "day": "明日", "time": "10時半"])
        XCTAssertEqual(ParamExtractor.extract("Share Team Sync with Lena", intent: "ShareEventIntent"), ["invitee": "Lena"])
        XCTAssertEqual(ParamExtractor.extract("デザレビを吉田さんに共有して", intent: "ShareEventIntent"), ["invitee": "吉田さん"])
    }

    func testMatchingPositiveAndNegative() {
        let expected: [String: JSONScalar] = ["title": .string("Dentist appointment"), "day": .string("Friday"), "time": .string("4:30pm")]
        XCTAssertTrue(ParamExtractor.matches(expected: expected, actual: ["title": "dentist appointment", "day": "friday", "time": "4:30pm", "extra": "x"]))
        XCTAssertFalse(ParamExtractor.matches(expected: expected, actual: ["title": "Dentist", "day": "friday", "time": "4:30pm"]))
        XCTAssertFalse(ParamExtractor.matches(expected: expected, actual: ["title": "dentist appointment", "day": "friday"]), "missing key")
        XCTAssertTrue(ParamExtractor.matches(expected: ["is_read": .bool(true)], actual: ["is_read": "true"]))
    }

    func testStartDates() {
        XCTAssertEqual(ParamExtractor.startISO(day: "tomorrow", time: "3pm", fallbackDate: nil), "2026-11-02T15:00:00Z")
        XCTAssertEqual(ParamExtractor.startISO(day: "金曜", time: "16時半", fallbackDate: nil), "2026-11-06T16:30:00Z")
        XCTAssertEqual(ParamExtractor.startISO(day: "next Monday", time: "10:30am", fallbackDate: nil), "2026-11-09T10:30:00Z")
        XCTAssertEqual(ParamExtractor.startISO(day: nil, time: "9am", fallbackDate: "2026-11-05"), "2026-11-05T09:00:00Z")
        XCTAssertNil(ParamExtractor.startISO(day: "someday", time: "9am", fallbackDate: nil))
    }

    func testMockReportCarriesSourcesAndV2() throws {
        let r = try Repo.bench("calendar_broken")
        let v2 = try XCTUnwrap(r.scoreV2)
        XCTAssertEqual(v2.components.count, 6)
        XCTAssertFalse(v2.provenance.contains { $0.source == .real }, "a MOCK run never claims real evidence")
        XCTAssertEqual(v2.components.first { $0.component == .parameterAccuracy }?.provenance, [ProvenanceShare(.mock, 1)])
        let md = ReportRenderer.markdown(r)
        XCTAssertTrue(md.contains("| Source |"))
        XCTAssertTrue(md.contains("Siri Visibility Score v2 (MOCK, adds Parameter Accuracy)"))
        XCTAssertFalse(md.contains("| real |"))
    }

    func testProvenanceCombination() {
        let combined = ProvenanceShare.combine([(0.5, [ProvenanceShare(.real, 1)]), (0.5, [ProvenanceShare(.staticAnalysis, 0.5), ProvenanceShare(.mock, 0.5)])])
        XCTAssertEqual(combined, [ProvenanceShare(.real, 0.5), ProvenanceShare(.mock, 0.25), ProvenanceShare(.staticAnalysis, 0.25)])
        XCTAssertEqual(ProvenanceShare.label(combined), "real 50% · mock 25% · static 25%")
    }

    func testSpotcheckIsSeparateAndValidated() throws {
        let log = try SpotcheckLog.load(Repo.root.appendingPathComponent("docs/spotcheck-sample.json"))
        XCTAssertTrue(log.sample)
        XCTAssertEqual(log.results.count, 30)
        let ids = Set(try DatasetLoader.loadCases(Repo.root.appendingPathComponent("dataset/v1.2/cases_dev.jsonl")).map(\.caseId))
            .union(try DatasetLoader.loadCases(Repo.root.appendingPathComponent("dataset/v1.2/cases_eval.jsonl")).map(\.caseId))
        XCTAssertEqual(log.problems(knownCaseIDs: ids), [])
        var bad = log
        bad.protocolVersion = "x"
        bad.results[0].inputMode = "telepathy"
        bad.results.append(bad.results[1])
        XCTAssertEqual(bad.problems().count, 3)

        var r = try Repo.bench("messages_ok")
        let before = r.scoreV2?.overall
        r.spotcheck = log
        let md = ReportRenderer.markdown(r)
        XCTAssertTrue(md.contains("Spot checks (manual, provenance `spotcheck`; not part of any score)"))
        XCTAssertTrue(md.contains("**SAMPLE**"))
        XCTAssertEqual(r.scoreV2?.overall, before)
    }

    func testAppsAuditMatchesFixtures() throws {
        for (app, fixture) in [("Messages/OK", "messages_ok"), ("Messages/Broken", "messages_broken"),
                               ("Calendar/OK", "calendar_ok"), ("Calendar/Broken", "calendar_broken")] {
            let built = Auditor.audit(try AppModelLoader.load(appDirectory: Repo.root.appendingPathComponent("Apps/\(app)")))
            let source = Auditor.audit(try Repo.model(fixture))
            XCTAssertEqual(Set(built.findings.map(\.check)), Set(source.findings.map(\.check)), app)
            XCTAssertEqual(built.findings.filter { $0.severity == .high }.map(\.check).sorted { $0.rawValue < $1.rawValue },
                           source.findings.filter { $0.severity == .high }.map(\.check).sorted { $0.rawValue < $1.rawValue }, app)
        }
    }
}

final class BenchmarksTests: XCTestCase {
    func testBenchmarksMarkdownIsRegeneratedDeterministically() throws {
        let decoder = JSONDecoder()
        let primary = try decoder.decode(BenchmarkConditions.self, from: Data(contentsOf: Repo.root.appendingPathComponent("benchmarks/phase4-conditions.json")))
        let runs = try Benchmarks.load(root: Repo.root, conditions: primary)
        XCTAssertEqual(runs.map(\.variant), Benchmarks.variants)
        let followUps: [(BenchmarkConditions, [BenchmarkRun])] = []
        let first = Benchmarks.render(primary: primary, runs: runs, followUps: followUps)
        XCTAssertEqual(first, Benchmarks.render(primary: primary, runs: runs, followUps: followUps))
        XCTAssertEqual(first, try String(contentsOf: Repo.root.appendingPathComponent("BENCHMARKS.md"), encoding: .utf8),
                       "BENCHMARKS.md is stale; run scripts/make_benchmarks.sh")
        XCTAssertEqual(Benchmarks.divergenceAppendix(runs, conditions: primary),
                       try String(contentsOf: Repo.root.appendingPathComponent("docs/mock-divergence-cases.md"), encoding: .utf8))
        XCTAssertTrue(first.contains("real 54% · mock 25% · static 21%"))
        XCTAssertTrue(first.contains("Xcode 27.1 (27A9275)") && first.contains("iOS 27.0 simulator runtime (24A434)"))
        XCTAssertTrue(first.contains("F1/F2 (does an utterance reach the right intent?) is always MOCK"))
        XCTAssertFalse(first.contains("/Users/"), "no host paths in public output")
    }
}
