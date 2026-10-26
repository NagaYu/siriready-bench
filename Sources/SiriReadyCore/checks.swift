import Foundation

public enum Severity: String, Codable, CaseIterable, Comparable, Sendable {
    case critical, high, medium, low

    var rank: Int {
        switch self {
        case .critical: return 0
        case .high: return 1
        case .medium: return 2
        case .low: return 3
        }
    }

    public static func < (a: Severity, b: Severity) -> Bool { a.rank < b.rank }
}

public enum CheckID: String, Codable, CaseIterable, Sendable {
    case c1 = "C1", c2 = "C2", c3 = "C3", c4 = "C4", c5 = "C5"

    public var title: String {
        switch self {
        case .c1: return "Companion schema"
        case .c2: return "IndexedEntity coverage"
        case .c3: return "View Annotations coverage"
        case .c4: return "Privacy manifest consistency"
        case .c5: return "SiriKit remnants"
        }
    }

    /// Tie-break order when severities are equal: how directly the check affects whether Siri
    /// can reach the app at all (discovery first, then resolution, then routing).
    var discoverabilityImpactOrder: Int {
        switch self {
        case .c1: return 0
        case .c5: return 1
        case .c2: return 2
        case .c3: return 3
        case .c4: return 4
        }
    }
}

/// One audit finding. Findings are advisory text; the tool never edits the audited app.
public struct Finding: Codable, Equatable, Sendable {
    public var check: CheckID
    public var severity: Severity
    public var location: SourceLocation?
    public var reason: String
    public var suggestion: String
    /// The F-class this finding is expected to surface as in the MOCK bench, if any.
    public var relatedFailure: String?
}

// MARK: - C1 companion table

public enum CompanionKind: String, Codable, Sendable { case intent, entity }

public struct CompanionRule: Sendable {
    public var domain: String
    public var trigger: String
    public var requires: String
    public var requiresKind: CompanionKind
    public var severity: Severity
    /// Where the rule comes from. `heuristic` rules are SiriReady's own judgement, not an Apple requirement.
    public var basis: String
    public var heuristic: Bool
}

/// Declarative C1 table. Schema identifiers follow the App Schema domain pages
/// (developer.apple.com/documentation/appintents/app-schema-domain-messages, ...-calendar).
public let companionRules: [CompanionRule] = [
    // WWDC26 "Build intelligent Siri experiences with App Schemas" (session 240): adopting
    // sendMessage without draftMessage is reported as missing by Xcode; Siri uses the draft
    // schema to compose and confirm before sending.
    CompanionRule(domain: "messages", trigger: "messages.sendMessage", requires: "messages.draftMessage", requiresKind: .intent,
                  severity: .high, basis: "WWDC26 session 240 (Xcode reports draftMessage missing when sendMessage is adopted)", heuristic: false),
    // Messages-domain intents act on schema-typed entities; without them Siri cannot hand the
    // intent a message/person it understands. SiriReady heuristic.
    CompanionRule(domain: "messages", trigger: "messages.sendMessage", requires: "messages.messagePerson", requiresKind: .entity,
                  severity: .medium, basis: "App Schema domain: Messages (messagePerson entity schema)", heuristic: true),
    CompanionRule(domain: "messages", trigger: "messages.setMessageReadStatus", requires: "messages.message", requiresKind: .entity,
                  severity: .medium, basis: "App Schema domain: Messages (message entity schema)", heuristic: true),
    CompanionRule(domain: "messages", trigger: "messages.editSentMessage", requires: "messages.sendMessage", requiresKind: .intent,
                  severity: .medium, basis: "App Schema domain: Messages", heuristic: true),
    CompanionRule(domain: "messages", trigger: "messages.unsendMessage", requires: "messages.sendMessage", requiresKind: .intent,
                  severity: .medium, basis: "App Schema domain: Messages", heuristic: true),
    // Calendar intents that modify an event need the event entity schema as their target.
    CompanionRule(domain: "calendar", trigger: "calendar.updateEvent", requires: "calendar.event", requiresKind: .entity,
                  severity: .high, basis: "App Schema domain: Calendar (event entity schema)", heuristic: true),
    CompanionRule(domain: "calendar", trigger: "calendar.deleteEvent", requires: "calendar.event", requiresKind: .entity,
                  severity: .high, basis: "App Schema domain: Calendar (event entity schema)", heuristic: true),
    CompanionRule(domain: "calendar", trigger: "calendar.createEvent", requires: "calendar.event", requiresKind: .entity,
                  severity: .medium, basis: "App Schema domain: Calendar (event entity schema)", heuristic: true),
    // An app that can create events but not change them forces "move my 3pm" requests to fail.
    CompanionRule(domain: "calendar", trigger: "calendar.createEvent", requires: "calendar.updateEvent", requiresKind: .intent,
                  severity: .medium, basis: "App Schema domain: Calendar", heuristic: true),
]

// MARK: - Audit

public struct AuditReport: Codable, Sendable {
    public var appId: String
    public var appPath: String
    public var findings: [Finding]
    /// C2: share of AppEntity types that reach the semantic index (0–1).
    public var indexCoverage: Double
    /// C3: share of entity-displaying screens whose view annotates every displayed entity type (0–1).
    public var annotationCoverage: Double
    public var counts: [String: Int]
}

public enum Auditor {
    public static func audit(_ model: AppModel) -> AuditReport {
        var findings = checkCompanions(model) + checkIndexCoverage(model).findings + checkAnnotations(model).findings
        findings += checkPrivacy(model) + checkSiriKit(model)
        findings.sort {
            if $0.severity != $1.severity { return $0.severity < $1.severity }
            if $0.check != $1.check { return $0.check.discoverabilityImpactOrder < $1.check.discoverabilityImpactOrder }
            return ($0.location?.file ?? "", $0.location?.line ?? 0) < ($1.location?.file ?? "", $1.location?.line ?? 0)
        }
        var counts: [String: Int] = [:]
        for f in findings { counts[f.check.rawValue, default: 0] += 1 }
        return AuditReport(
            appId: model.manifest.appId, appPath: model.root.lastPathComponent, findings: findings,
            indexCoverage: checkIndexCoverage(model).coverage, annotationCoverage: checkAnnotations(model).coverage, counts: counts)
    }

    static func checkCompanions(_ model: AppModel) -> [Finding] {
        let intentSchemas = Set(model.intents.compactMap(\.schema))
        let entitySchemas = Set(model.entities.compactMap(\.schema))
        var findings: [Finding] = []
        for rule in companionRules {
            guard let trigger = model.intents.first(where: { $0.schema == rule.trigger }) else { continue }
            let present = rule.requiresKind == .intent ? intentSchemas.contains(rule.requires) : entitySchemas.contains(rule.requires)
            if present { continue }
            let what = rule.requiresKind == .intent ? "@AppIntent(schema: .\(rule.requires))" : "@AppEntity(schema: .\(rule.requires))"
            findings.append(Finding(
                check: .c1, severity: rule.severity, location: trigger.location,
                reason: "\(trigger.name) adopts .\(rule.trigger) but no type adopts .\(rule.requires). Basis: \(rule.basis)\(rule.heuristic ? " [SiriReady heuristic]" : "").",
                suggestion: "Add a type annotated with \(what) so Siri can reach the companion action/entity.",
                relatedFailure: rule.requiresKind == .intent ? "F1" : nil))
        }
        return findings
    }

    static func checkIndexCoverage(_ model: AppModel) -> (coverage: Double, findings: [Finding]) {
        var findings: [Finding] = []
        let declared = Set(model.manifest.indexedEntities)
        for e in model.entities where !e.conformsToIndexedEntity {
            let promised = declared.contains(e.name)
            findings.append(Finding(
                check: .c2, severity: promised ? .high : .medium, location: e.location,
                reason: promised
                    ? "\(e.name) is listed in siriready.yaml indexed_entities but does not conform to IndexedEntity, so it never reaches the semantic index."
                    : "\(e.name) is an AppEntity that is not contributed to the Spotlight semantic index; Siri can only find it through an EntityQuery.",
                suggestion: "Conform \(e.name) to IndexedEntity, mark searchable properties with @Property(indexingKey:), and index instances with CSSearchableIndex.indexAppEntities(_:).",
                relatedFailure: "F4"))
        }
        for name in model.manifest.indexedEntities where model.entity(named: name) == nil {
            findings.append(Finding(
                check: .c2, severity: .high, location: nil,
                reason: "siriready.yaml indexed_entities lists \(name), but no AppEntity named \(name) was found in the sources.",
                suggestion: "Fix the declaration in siriready.yaml or add the entity.", relatedFailure: "F4"))
        }
        let indexedTypes = model.entities.filter(\.conformsToIndexedEntity)
        if !indexedTypes.isEmpty && !model.callsIndexAppEntities {
            findings.append(Finding(
                check: .c2, severity: .high, location: indexedTypes[0].location,
                reason: "Entities conform to IndexedEntity but indexAppEntities(_:) is never called, so nothing is actually indexed.",
                suggestion: "Call CSSearchableIndex.default().indexAppEntities(_:) when content is created or changed.",
                relatedFailure: "F4"))
        }
        let coverage = model.entities.isEmpty ? 1 : Double(model.indexedEntityTypes.count) / Double(model.entities.count)
        return (coverage, findings)
    }

    static func checkAnnotations(_ model: AppModel) -> (coverage: Double, findings: [Finding]) {
        var findings: [Finding] = []
        let promised = Set(model.manifest.annotatedViews)
        var screensWithEntities = 0
        var annotatedScreens = 0
        for (screen, decl) in model.manifest.screens where !decl.entities.isEmpty {
            screensWithEntities += 1
            guard let view = model.view(named: decl.view) else {
                findings.append(Finding(
                    check: .c3, severity: .medium, location: nil,
                    reason: "Screen \(screen) declares view \(decl.view), which was not found in the sources.",
                    suggestion: "Fix siriready.yaml screens.\(screen).view.", relatedFailure: "F6"))
                continue
            }
            let missing = decl.entities.filter { !view.annotatedEntityTypes.contains($0) }
            if missing.isEmpty { annotatedScreens += 1; continue }
            let wrong = view.annotatedEntityTypes.filter { !decl.entities.contains($0) }
            var reason = "\(view.name) (screen \(screen)) displays \(missing.joined(separator: ", ")) without a View Annotation"
            if !wrong.isEmpty { reason += "; it annotates \(wrong.joined(separator: ", ")) instead, which looks like the wrong identifier" }
            reason += ", so \"this\" / \"the second one\" cannot be resolved on this screen."
            findings.append(Finding(
                check: .c3, severity: promised.contains(view.name) ? .high : .medium, location: view.location,
                reason: reason,
                suggestion: "Attach .appEntityIdentifier(EntityIdentifier(for: \(missing[0]).self, identifier: item.id)) to each displayed item (or use NSUserActivity for a single primary item).",
                relatedFailure: "F6"))
        }
        let coverage = screensWithEntities == 0 ? 1 : Double(annotatedScreens) / Double(screensWithEntities)
        return (coverage, findings)
    }

    static func checkPrivacy(_ model: AppModel) -> [Finding] {
        var findings: [Finding] = []
        for intent in model.intents {
            switch model.manifest.routing(for: intent.name) {
            case .onDeviceOnly where !intent.networkEvidence.isEmpty:
                findings.append(Finding(
                    check: .c4, severity: .high, location: intent.location,
                    reason: "\(intent.name) is declared on_device_only, but its implementation shows off-device transmission (\(intent.networkEvidence.joined(separator: ", "))).",
                    suggestion: "Either keep the work on device (e.g. a local geocoder/cache) or declare the intent cloud_allowed and disclose it in the privacy manifest.",
                    relatedFailure: "F8"))
            case nil:
                findings.append(Finding(
                    check: .c4, severity: .low, location: intent.location,
                    reason: "\(intent.name) has no routing declared in siriready.yaml privacy.",
                    suggestion: "Declare on_device_only or cloud_allowed for \(intent.name).", relatedFailure: nil))
            default:
                break
            }
        }
        for (name, _) in model.manifest.privacy where model.intent(named: name) == nil {
            let legacy = model.legacySiriKitIntents.contains(name)
            findings.append(Finding(
                check: .c4, severity: .low, location: nil,
                reason: "siriready.yaml privacy declares \(name), but no App Intent with that name exists\(legacy ? " (it only exists as a SiriKit intent)" : "").",
                suggestion: "Remove the stale declaration or implement \(name) as an App Intent.", relatedFailure: nil))
        }
        return findings
    }

    static func checkSiriKit(_ model: AppModel) -> [Finding] {
        var byFile: [String: [SiriKitRemnant]] = [:]
        for r in model.siriKitRemnants { byFile[r.location.file, default: []].append(r) }
        var findings: [Finding] = []
        for file in byFile.keys.sorted() {
            let remnants = byFile[file]!.sorted { $0.location.line < $1.location.line }
            let kinds = Array(Set(remnants.map(\.kind))).sorted()
            let handlesIntents = remnants.contains { $0.kind == "SiriKit intent handling protocol" || $0.kind == "INExtension" }
            let unmigrated = model.legacySiriKitIntents.filter { model.intent(named: $0) == nil }
            var reason = "SiriKit remains in \(file) (\(kinds.joined(separator: ", ")); lines \(remnants.map { String($0.location.line) }.joined(separator: ", "))). SiriKit is legacy; the new Siri integrates through App Intents."
            if handlesIntents && !unmigrated.isEmpty {
                reason += " \(unmigrated.joined(separator: ", ")) has no App Intent counterpart, so the new Siri cannot discover it."
            }
            findings.append(Finding(
                check: .c5, severity: handlesIntents ? .high : .medium, location: remnants[0].location,
                reason: reason,
                suggestion: unmigrated.isEmpty
                    ? "Remove the leftover SiriKit code once its App Intent replacement ships."
                    : "Re-implement \(unmigrated.joined(separator: ", ")) as an App Intent (and register it in an AppShortcutsProvider), then delete the SiriKit extension.",
                relatedFailure: unmigrated.isEmpty ? nil : "F1"))
        }
        return findings
    }
}
