// SiriReady Bench real-run harness (Phase 2, Track B).
//
// UI-testing target shared by the four reference apps. It never imports app code: it discovers
// intents and entities through AppIntentsTesting.IntentDefinitions, executes the run plan written
// by `siriready plan`, and writes raw observations for `siriready ingest`. It does no
// classification or scoring (that lives in SiriReadyCore and is tested offline).
//
// Inputs (passed by scripts/real_run.sh through TEST_RUNNER_ environment variables):
//   SIRIREADY_PLAN  path of plan.json      SIRIREADY_OUT  path for raw.json
//   SIRIREADY_LIMIT optional case limit (smoke runs)
import AppIntentsTesting
import XCTest

// Wire format mirrors SiriReadyCore/realrun.swift (protocol siriready-harness-v1).
struct Plan: Decodable {
    struct Case: Decodable {
        var caseId: String
        var mockFailure: String?
        var intent: String?
        var targetType: String?
        var mode: String
        var mention: String?
        var screen: String?
        var visible: [String]
        var visibleType: String?
        var priorEntityId: String?
        var priorEntityType: String?
        var targetId: String?
        var params: [String: String]
        var expectDisambiguation: Bool
    }
    struct Probe: Decodable {
        var entityId: String
        var entityType: String
        var query: String
    }
    var protocolVersion: String
    var bundleIdentifier: String
    var cases: [Case]
    var indexProbes: [Probe]
}

struct Lookup: Encodable {
    var ids: [String]
    var error: String?
}

struct RunObservation: Encodable {
    var ok: Bool
    var targetId: String?
    var errorDomain: String?
    var errorCode: Int?
    var errorMessage: String?
}

struct Effect: Codable {
    var intent: String
    var target: String?
    var params: [String: String]
}

struct RawCase: Encodable {
    var caseId: String
    var intentAvailable: Bool?
    var stringQuery: Lookup?
    var spotlight: Lookup?
    var annotations: Lookup?
    var priorFetch: Lookup?
    var run: RunObservation?
    var effects: [Effect] = []
    var egress: [String] = []
    var notes: [String] = []
}

struct RawProbe: Encodable {
    var entityId: String
    var entityType: String
    var query: String
    var ids: [String]
    var error: String?
}

struct RawRun: Encodable {
    var protocolVersion = "siriready-harness-v1"
    var bundleIdentifier: String
    var device: String
    var osVersion: String
    var cases: [RawCase]
    var indexProbes: [RawProbe]
}

final class SiriReadyHarness: XCTestCase {
    func testRunPlan() async throws {
        let env = ProcessInfo.processInfo.environment
        guard let planPath = env["SIRIREADY_PLAN"], let outPath = env["SIRIREADY_OUT"] else {
            throw XCTSkip("SIRIREADY_PLAN / SIRIREADY_OUT not set; run scripts/real_run.sh")
        }
        let plan = try JSONDecoder().decode(Plan.self, from: Data(contentsOf: URL(fileURLWithPath: planPath)))
        XCTAssertEqual(plan.protocolVersion, "siriready-harness-v1")
        let limit = env["SIRIREADY_LIMIT"].flatMap(Int.init)
        let runner = Runner(plan: plan)
        let raw = try await runner.run(limit: limit)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(raw).write(to: URL(fileURLWithPath: outPath))
        print("SIRIREADY wrote \(raw.cases.count) cases and \(raw.indexProbes.count) index probes to \(outPath)")
    }
}

final class Runner {
    let plan: Plan
    let defs: IntentDefinitions
    var currentScreen: String?

    init(plan: Plan) {
        self.plan = plan
        self.defs = IntentDefinitions(bundleIdentifier: plan.bundleIdentifier)
    }

    func describe(_ error: Error) -> (String, Int, String) {
        let ns = error as NSError
        return (ns.domain, ns.code, ns.localizedDescription)
    }

    func ids(_ entities: [AnyAppEntity]) -> [String] { entities.map { $0.identifier.instanceIdentifier } }

    @MainActor
    func launch(screen: String?, ids: [String]) async throws {
        let key = (screen ?? "home") + "|" + ids.joined(separator: ",")
        if currentScreen == key { return }
        let app = XCUIApplication()
        app.terminate()
        app.launchArguments = screen.map { ["-siriready-screen", $0, "-siriready-ids", ids.joined(separator: ",")] } ?? []
        app.launch()
        _ = app.wait(for: .runningForeground, timeout: 10)
        try await Task.sleep(for: .seconds(1))
        currentScreen = key
    }

    func drain() async -> ([Effect], [String]) {
        struct Log: Decodable { var effects: [Effect]; var egress: [String] }
        guard let result = try? await defs.intents["DebugProbeIntent"].makeIntent().run(),
              let json = try? result.value as String,
              let log = try? JSONDecoder().decode(Log.self, from: Data(json.utf8)) else { return ([], []) }
        return (log.effects, log.egress)
    }

    func run(limit: Int?) async throws -> RawRun {
        try await launch(screen: nil, ids: [])
        // Let launch-time indexing finish: wait until any probe answers, at most ~20 s.
        if let first = plan.indexProbes.first {
            for _ in 0..<20 {
                if let hits = try? await defs.entities[first.entityType].spotlightQuery(first.query), !hits.isEmpty { break }
                try await Task.sleep(for: .seconds(1))
            }
        }
        _ = await drain()

        let started = Date()
        var probes: [RawProbe] = []
        for p in plan.indexProbes {
            do {
                probes.append(RawProbe(entityId: p.entityId, entityType: p.entityType, query: p.query,
                                       ids: ids(try await defs.entities[p.entityType].spotlightQuery(p.query)), error: nil))
            } catch {
                probes.append(RawProbe(entityId: p.entityId, entityType: p.entityType, query: p.query, ids: [], error: describe(error).2))
            }
        }

        print(String(format: "SIRIREADY index probes done: %d in %.0f s", probes.count, Date().timeIntervalSince(started)))
        var cases = plan.cases.filter { $0.mockFailure == nil }
        if let limit { cases = Array(cases.prefix(limit)) }
        // Group on-screen cases so the app is relaunched once per screen state.
        cases.sort { ($0.mode == "on_screen" ? 1 : 0, $0.screen ?? "", $0.visible.joined()) < ($1.mode == "on_screen" ? 1 : 0, $1.screen ?? "", $1.visible.joined()) }
        var raws: [RawCase] = []
        for (i, c) in cases.enumerated() {
            raws.append(try await runCase(c))
            if (i + 1) % 50 == 0 || i + 1 == cases.count {
                print(String(format: "SIRIREADY cases %d/%d at %.0f s", i + 1, cases.count, Date().timeIntervalSince(started)))
            }
        }
        return RawRun(bundleIdentifier: plan.bundleIdentifier, device: "iOS Simulator", osVersion: UIDeviceInfo.osVersion,
                      cases: raws, indexProbes: probes)
    }

    func lookup(_ body: () async throws -> [AnyAppEntity]) async -> Lookup {
        do { return Lookup(ids: ids(try await body()), error: nil) } catch { return Lookup(ids: [], error: describe(error).2) }
    }

    func runCase(_ c: Plan.Case) async throws -> RawCase {
        var raw = RawCase(caseId: c.caseId)
        var targetId = c.targetId
        if c.mode == "on_screen" {
            try await launch(screen: c.screen, ids: c.visible)
            if let type = c.visibleType {
                do {
                    raw.annotations = Lookup(ids: try await defs.entities[type].viewAnnotations().map { $0.entity.identifier.instanceIdentifier }, error: nil)
                } catch {
                    raw.annotations = Lookup(ids: [], error: describe(error).2)
                }
            }
            if !Set(c.visible).isSubset(of: Set(raw.annotations?.ids ?? [])) { targetId = nil }
        } else if c.mode == "prior_turn", let type = c.priorEntityType, let id = c.priorEntityId {
            raw.priorFetch = await lookup { try await self.defs.entities[type].entities(identifiers: [id]) }
            if raw.priorFetch?.ids.contains(id) != true { targetId = nil }
        } else if c.mode == "name", let type = c.targetType, let mention = c.mention {
            raw.stringQuery = await lookup { try await self.defs.entities[type].entities(matching: mention) }
            raw.spotlight = await lookup { try await self.defs.entities[type].spotlightQuery(mention) }
            let found = (raw.spotlight?.ids ?? []) + (raw.stringQuery?.ids ?? [])
            if let t = targetId, found.contains(t) {
                targetId = t
            } else {
                targetId = found.first
                raw.notes.append("MOCK target \(c.targetId ?? "nil") not returned; using \(found.first ?? "nothing")")
            }
        }

        guard let intent = c.intent else { return raw }
        var target: AnyAppEntity?
        if let type = c.targetType {
            guard let id = targetId else {
                raw.notes.append("no target entity; not executed")
                return raw
            }
            target = try? await defs.entities[type].entities(identifiers: [id]).first
        }
        do {
            try await execute(intent, target: target, params: c.params)
            raw.run = RunObservation(ok: true, targetId: targetId)
            raw.intentAvailable = true
        } catch {
            let (domain, code, message) = describe(error)
            raw.run = RunObservation(ok: false, targetId: targetId, errorDomain: domain, errorCode: code, errorMessage: message)
            raw.intentAvailable = !(domain == "AppIntentsServicesMetadataErrorDomain" && message.contains("does not expose"))
        }
        (raw.effects, raw.egress) = await drain()
        return raw
    }

    /// Parameter names follow the App Schemas each intent adopts in the reference apps.
    func execute(_ intent: String, target: AnyAppEntity?, params: [String: String]) async throws {
        let def = defs.intents[intent]
        let body = AttributedString(params["body"] ?? "")
        let start = params["start"].flatMap { ISO8601DateFormatter().date(from: $0) }
        switch intent {
        case "SendMessageIntent", "DraftMessageIntent":
            try await def.makeIntent(destination: target, content: body).run()
        case "SetMessageReadStatusIntent":
            try await def.makeIntent(message: target, isRead: true).run()
        case "OpenConversationIntent", "OpenEventIntent":
            try await def.makeIntent(target: target).run()
        case "CreateEventIntent":
            // A calendar named in the request is looked up for real (Spotlight); otherwise the app's default.
            var calendarID = "cal_work"
            if let mention = params["calendar_mention"] {
                let hits = (try? await defs.entities["CalendarEntity"].spotlightQuery(mention)) ?? []
                if let first = hits.first { calendarID = first.identifier.instanceIdentifier }
            }
            let calendar = try await defs.entities["CalendarEntity"].entities(identifiers: [calendarID]).first
            if let location = params["location"] {
                try await def.makeIntent(title: params["title"] ?? "", startDate: start ?? Date(), isAllDay: false, location: location,
                                         attendees: [AnyAppEntity](), calendar: calendar).run()
            } else {
                try await def.makeIntent(title: params["title"] ?? "", startDate: start ?? Date(), isAllDay: false,
                                         attendees: [AnyAppEntity](), calendar: calendar).run()
            }
        case "UpdateEventIntent":
            try await def.makeIntent(event: target, startDate: start).run()
        case "DeleteEventIntent":
            try await def.makeIntent(entity: target).run()
        case "ShareEventIntent":
            try await def.makeIntent(target: target, invitee: params["invitee"] ?? "").run()
        default:
            try await def.makeIntent().run()
        }
    }
}

enum UIDeviceInfo {
    static var osVersion: String {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return "iOS \(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"
    }
}
