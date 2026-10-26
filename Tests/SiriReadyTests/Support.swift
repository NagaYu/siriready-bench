import Foundation
@testable import SiriReadyCore

enum Repo {
    static let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    static func fixture(_ name: String) -> URL { root.appendingPathComponent("Fixtures/apps/\(name)") }
    static let devCases = root.appendingPathComponent("dataset/v1.2/cases_dev.jsonl")
    static let evalCases = root.appendingPathComponent("dataset/v1.2/cases_eval.jsonl")

    static func model(_ name: String) throws -> AppModel { try AppModelLoader.load(appDirectory: fixture(name)) }

    static func bench(_ name: String) throws -> BenchResult {
        try Bench.run(appDirectory: fixture(name), casesURL: name.hasPrefix("messages") ? devCases : evalCases)
    }
}

/// Writes a throwaway fixture (siriready.yaml + one Swift file) into a temporary directory.
func makeFixture(yaml: String, swift: String) throws -> URL {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("siriready-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    try yaml.write(to: dir.appendingPathComponent("siriready.yaml"), atomically: true, encoding: .utf8)
    try swift.write(to: dir.appendingPathComponent("App.swift"), atomically: true, encoding: .utf8)
    return dir
}

func benchCase(
    id: String = "messages-en-001", utterance: String = "Send Alex Rivera a message saying hi",
    intent: String = "SendMessageIntent", entityId: String? = "c_alex", resolution: String = "execute",
    candidates: [String] = [], screen: String? = nil, visible: [String] = [], prior: PriorTurn? = nil
) -> BenchCase {
    BenchCase(
        caseId: id, split: "dev", appId: "messages", domain: "messages", locale: "en-US", utterance: utterance, noise: "none",
        state: CaseState(screen: screen, visibleEntities: visible, priorTurn: prior),
        expected: ExpectedOutcome(intent: intent, entityId: entityId, params: [:], resolution: resolution, candidates: candidates),
        adversarial: false, difficulty: "easy", tags: ["test"])
}

func resolution(
    intent: String? = "SendMessageIntent", entityId: String? = "c_alex", resolution: String = "execute",
    candidates: [String] = [], mode: ReferenceKind = .name, notes: [MockNote] = [], declared: String? = "on_device_only"
) -> MockResolution {
    MockResolution(concept: nil, intent: intent, entityId: entityId, resolution: resolution, candidates: candidates,
                   referenceMode: mode, routing: "on_device", declaredRouting: declared, notes: notes, trace: [])
}
