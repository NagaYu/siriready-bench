import Foundation

public let benchVersion = "0.1.0"
public let resolverVersion = "mock-rule-v0"

/// Conditions printed with every score. A MOCK score is only comparable to another score with the
/// same bench version, resolver version and dataset fingerprint; it is not an iOS measurement.
public struct BenchConditions: Codable, Sendable {
    public var mode = "MOCK"
    public var benchVersion = SiriReadyCore.benchVersion
    public var resolver = resolverVersion
    public var datasetVersion: String
    public var casesFile: String
    public var casesFingerprint: String
    public var catalogFile: String
    public var catalogFingerprint: String
    public var appFixture: String
    public var appId: String
    public var appDisplayName: String
    public var caseCount: Int
    public var skippedCases: Int
    public var locales: [String: Int]
    public var targetOS = "not measured (MOCK). Phase 2 records the iOS 27 device/simulator build."
    public var targetSDK = "not measured (MOCK). Phase 2 records the Xcode 27 / iOS 27 SDK build."
    public var hostOS: String
    public var reproduces = [
        "App Schema / App Shortcut discoverability as declared in source",
        "IndexedEntity adoption and indexAppEntities calls (static)",
        "View Annotation presence per declared screen (static)",
        "Disambiguation code paths (requestDisambiguation) and privacy-routing evidence (static)",
    ]
    public var doesNotReproduce = [
        "Siri's speech recognition, language understanding and planning",
        "The real Spotlight semantic index and its ranking",
        "Runtime behaviour of the app (intents are never executed)",
        "OS-version-specific behaviour: the score is not an absolute, OS-independent value",
    ]
}

public struct BenchResult: Codable, Sendable {
    public var conditions: BenchConditions
    public var audit: AuditReport
    public var score: ScoreBreakdown
    public var index: IndexSimulation
    public var failureCounts: [String: Int]
    public var outcomes: [CaseOutcome]
    /// Phase 2: six-component score with Parameter Accuracy and provenance tags (MOCK run).
    public var scoreV2: ScoreBreakdownV2? = nil
    public var params: [ParamOutcome]? = nil
    /// Phase 2: manual Siri spot checks, shown separately and never mixed into scores.
    public var spotcheck: SpotcheckLog? = nil
}

public enum Bench {
    public static func run(appDirectory: URL, casesURL: URL, catalogURL: URL? = nil) throws -> BenchResult {
        let model = try AppModelLoader.load(appDirectory: appDirectory)
        let audit = Auditor.audit(model)
        let allCases = try DatasetLoader.loadCases(casesURL)
        let cases = allCases.filter { $0.appId == model.manifest.appId }
        let catalogURL = catalogURL ?? defaultCatalog(casesURL: casesURL, appId: model.manifest.appId)
        let catalog = try DatasetLoader.loadCatalog(catalogURL)
        let resolver = MockResolver(model: model, catalog: catalog)

        let outcomes = cases.map { c -> CaseOutcome in
            let r = resolver.resolve(c)
            return CaseOutcome(benchCase: c, result: r, failure: Scorer.classify(c, r))
        }
        let index = Scorer.simulateIndex(model: model, catalog: catalog, coverage: audit.indexCoverage)
        let score = Scorer.score(outcomes: outcomes, audit: audit, index: index)
        var counts: [String: Int] = [:]
        for f in FailureClass.allCases { counts[f.rawValue] = 0 }
        for o in outcomes { if let f = o.failure { counts[f.rawValue, default: 0] += 1 } }
        var locales: [String: Int] = [:]
        for c in cases { locales[c.locale, default: 0] += 1 }

        let conditions = BenchConditions(
            datasetVersion: catalog.datasetVersion,
            casesFile: casesURL.lastPathComponent,
            casesFingerprint: DatasetLoader.fingerprint(try Data(contentsOf: casesURL)),
            catalogFile: "entities/" + catalogURL.lastPathComponent,
            catalogFingerprint: DatasetLoader.fingerprint(try Data(contentsOf: catalogURL)),
            appFixture: appDirectory.standardizedFileURL.lastPathComponent,
            appId: model.manifest.appId,
            appDisplayName: model.manifest.displayName,
            caseCount: cases.count,
            skippedCases: allCases.count - cases.count,
            locales: locales,
            hostOS: "macOS " + ProcessInfo.processInfo.operatingSystemVersionString)
        let (scoreV2, params) = ScorerV2.mockScore(v1: score, outcomes: outcomes, catalog: catalog)
        return BenchResult(conditions: conditions, audit: audit, score: score, index: index, failureCounts: counts, outcomes: outcomes,
                           scoreV2: scoreV2, params: params)
    }

    /// `<cases dir>/entities/<app_id>.json`
    public static func defaultCatalog(casesURL: URL, appId: String) -> URL {
        casesURL.deletingLastPathComponent().appendingPathComponent("entities").appendingPathComponent("\(appId).json")
    }

    public static func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(value)
    }
}
