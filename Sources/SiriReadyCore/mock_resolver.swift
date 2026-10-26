import Foundation

// MOCK resolver.
//
// This is NOT a reproduction of Siri. It is a deterministic, rule-based stand-in that only uses
// what the static audit extracted from the app (schemas, App Shortcuts, IndexedEntity adoption,
// string queries, View Annotations, disambiguation calls, privacy routing) plus the synthetic
// entity catalog. Its job is to make "a static gap causes a resolution failure" visible offline.
// Measuring the real system (AppIntentsTesting, Spotlight, Siri) is Phase 2.

public enum MockNote: String, Codable, Sendable {
    case noConceptRecognised = "no_concept_recognised"
    case noIntentForConcept = "no_intent_for_concept"
    case entityTypeNotIndexed = "entity_type_not_indexed"
    case noEntityMatch = "no_entity_match"
    case screenNotDeclared = "screen_not_declared"
    case viewNotAnnotated = "view_not_annotated"
    case visibleTypeMismatch = "visible_type_mismatch"
    case priorTurnUnresolvable = "prior_turn_unresolvable"
    case pickedFirstWithoutDisambiguation = "picked_first_without_disambiguation"
    case routingMismatch = "routing_mismatch"
}

public struct MockResolution: Codable, Equatable, Sendable {
    public var concept: String?
    public var intent: String?
    public var entityId: String?
    /// `execute`, `disambiguate` or `none` (no target could be resolved).
    public var resolution: String
    public var candidates: [String]
    public var referenceMode: ReferenceKind
    /// Simulated routing from source evidence: `on_device` or `cloud`.
    public var routing: String?
    public var declaredRouting: String?
    public var notes: [MockNote]
    public var trace: [String]
}

struct ConceptRule {
    var concept: String
    /// Single words are matched as tokens of the reference segment; phrases against the whole utterance.
    var english: [String]
    /// Substrings of the reference segment.
    var japanese: [String]
}

/// Action lexicon per domain, checked in order (more specific actions first).
let conceptLexicon: [String: [ConceptRule]] = [
    "messages": [
        ConceptRule(concept: "messages.draftMessage", english: ["draft", "dont send", "do not send"], japanese: ["下書き", "送らないで"]),
        ConceptRule(concept: "messages.setMessageReadStatus", english: ["mark", "as read"], japanese: ["既読"]),
        ConceptRule(concept: "open.conversation", english: ["open", "show"], japanese: ["開いて", "見せて", "表示"]),
        ConceptRule(concept: "messages.sendMessage", english: ["send", "text", "message", "tell", "reply"], japanese: ["送", "返信", "伝えて", "メッセージ"]),
    ],
    "calendar": [
        ConceptRule(concept: "share.event", english: ["share"], japanese: ["共有"]),
        ConceptRule(concept: "calendar.deleteEvent", english: ["cancel", "delete", "remove"], japanese: ["キャンセル", "削除", "消して"]),
        ConceptRule(concept: "calendar.updateEvent", english: ["move", "reschedule", "push"], japanese: ["変更", "ずらして", "移動", "動かして"]),
        ConceptRule(concept: "open.event", english: ["open", "show"], japanese: ["開いて", "見せて", "表示"]),
        ConceptRule(concept: "calendar.createEvent", english: ["add", "schedule", "create", "put"], japanese: ["入れて", "作って", "追加", "登録"]),
    ],
]

let englishOrdinals: [String: Int] = ["first": 0, "top": 0, "second": 1, "third": 2, "last": -1, "bottom": -1]
let japaneseOrdinals: [(String, Int)] = [("一番上", 0), ("最初", 0), ("1番目", 0), ("一番目", 0), ("2番目", 1), ("二番目", 1),
                                          ("3番目", 2), ("三番目", 2), ("最後", -1), ("一番下", -1)]
let englishDeixis: Set<String> = ["this", "these"]
let japaneseDeixis = ["これ", "この", "こちら"]
let englishAnaphora: Set<String> = ["them", "it", "him", "her", "they"]
let englishAnaphoraPhrases = ["that person", "that one", "that event"]
let japaneseAnaphora = ["その", "それ", "同じ人", "さっき", "彼女", "彼"]

public struct MockResolver: Sendable {
    public let model: AppModel
    public let catalog: EntityCatalog

    public init(model: AppModel, catalog: EntityCatalog) {
        self.model = model
        self.catalog = catalog
    }

    // MARK: Concept and intent

    public func concept(for utterance: String) -> String? {
        let segment = TextMatching.referenceSegment(utterance)
        let tokens = Set(TextMatching.asciiTokens(segment))
        let fullPhrase = " " + TextMatching.asciiTokens(utterance).joined(separator: " ") + " "
        for rule in conceptLexicon[model.manifest.domain] ?? [] {
            let english = rule.english.contains { word in
                word.contains(" ") ? fullPhrase.contains(" \(word) ") : tokens.contains(word)
            }
            if english || rule.japanese.contains(where: { segment.contains($0) }) { return rule.concept }
        }
        return nil
    }

    /// `OpenEventIntent` → `open.event`; used for intents without an App Schema.
    static func derivedConcept(_ intentName: String) -> String {
        let base = intentName.hasSuffix("Intent") ? String(intentName.dropLast(6)) : intentName
        guard let split = base.dropFirst().firstIndex(where: \.isUppercase) else { return base.lowercased() }
        let verb = base[..<split].lowercased()
        let noun = base[split...]
        return verb + "." + noun.prefix(1).lowercased() + noun.dropFirst()
    }

    /// Schema-adopting intents are discoverable through their schema; other intents only when
    /// registered as App Shortcuts (MOCK discovery rule).
    public func intent(forConcept concept: String) -> IntentInfo? {
        if let schemaIntent = model.intents.first(where: { $0.schema == concept }) { return schemaIntent }
        return model.intents.first {
            $0.schema == nil && Self.derivedConcept($0.name) == concept && model.appShortcutIntents.contains($0.name)
        }
    }

    // MARK: Resolution

    public func resolve(_ c: BenchCase) -> MockResolution {
        var r = MockResolution(concept: nil, intent: nil, entityId: nil, resolution: "none", candidates: [],
                               referenceMode: .none, routing: nil, declaredRouting: nil, notes: [], trace: [])
        guard let concept = concept(for: c.utterance) else {
            r.notes.append(.noConceptRecognised)
            r.trace.append("no action keyword recognised")
            return r
        }
        r.concept = concept
        guard let intent = intent(forConcept: concept) else {
            r.notes.append(.noIntentForConcept)
            r.trace.append("concept \(concept): no App Intent adopts this schema or is registered as an App Shortcut")
            return r
        }
        r.intent = intent.name
        r.trace.append("concept \(concept) → \(intent.name)\(intent.schema.map { " (schema .\($0))" } ?? " (App Shortcut)")")

        let declared = model.manifest.routing(for: intent.name)
        r.routing = intent.networkEvidence.isEmpty ? "on_device" : "cloud"
        r.declaredRouting = declared?.rawValue
        if declared == .onDeviceOnly && r.routing == "cloud" {
            r.notes.append(.routingMismatch)
            r.trace.append("declared on_device_only but implementation sends data off device (\(intent.networkEvidence.joined(separator: ", ")))")
        }

        guard let targetType = model.targetEntityType(of: intent) else {
            r.resolution = "execute"
            r.trace.append("no entity parameter; executes with slot values only")
            return r
        }
        resolveTarget(c, intent: intent, targetType: targetType, into: &r)
        return r
    }

    private func resolveTarget(_ c: BenchCase, intent: IntentInfo, targetType: String, into r: inout MockResolution) {
        let segment = TextMatching.referenceSegment(c.utterance)
        let tokens = TextMatching.asciiTokens(segment)
        let tokenSet = Set(tokens)
        let joined = " " + tokens.joined(separator: " ") + " "
        let ja = TextMatching.japaneseNormalized(segment)

        var ordinal: Int?
        for t in tokens { if let o = englishOrdinals[t] { ordinal = o; break } }
        if ordinal == nil { ordinal = japaneseOrdinals.first { ja.contains($0.0) }?.1 }
        let deixis = !tokenSet.isDisjoint(with: englishDeixis) || japaneseDeixis.contains { ja.contains($0) }
        let anaphora = !tokenSet.isDisjoint(with: englishAnaphora) || englishAnaphoraPhrases.contains { joined.contains(" \($0) ") }
            || japaneseAnaphora.contains { ja.contains($0) }

        if (ordinal != nil || deixis) && !c.state.visibleEntities.isEmpty {
            r.referenceMode = .onScreen
            resolveOnScreen(c, ordinal: ordinal, intent: intent, targetType: targetType, into: &r)
        } else if anaphora, let prior = c.state.priorTurn {
            r.referenceMode = .priorTurn
            resolvePriorTurn(prior, targetType: targetType, into: &r)
        } else {
            r.referenceMode = .name
            resolveByName(segment, intent: intent, targetType: targetType, into: &r)
        }
    }

    private func resolveOnScreen(_ c: BenchCase, ordinal: Int?, intent: IntentInfo, targetType: String, into r: inout MockResolution) {
        guard let screenName = c.state.screen, let screen = model.manifest.screen(named: screenName) else {
            r.notes.append(.screenNotDeclared)
            r.trace.append("screen \(c.state.screen ?? "nil") is not declared in siriready.yaml")
            return
        }
        let visible = c.state.visibleEntities.compactMap(catalog.entity)
        guard let view = model.view(named: screen.view),
              !visible.isEmpty, visible.allSatisfy({ view.annotatedEntityTypes.contains($0.type) }) else {
            r.notes.append(.viewNotAnnotated)
            r.trace.append("\(screen.view) exposes no View Annotation for \(Set(visible.map(\.type)).sorted().joined(separator: ", ")); on-screen reference cannot be resolved")
            return
        }
        var picked: [CatalogEntity]
        if let ordinal {
            let index = ordinal < 0 ? visible.count + ordinal : ordinal
            picked = visible.indices.contains(index) ? [visible[index]] : []
            r.trace.append("ordinal → item \(index + 1) of \(visible.count) annotated items on \(screen.view)")
        } else {
            picked = visible
            r.trace.append("deictic reference → \(visible.count) annotated item(s) on \(screen.view)")
        }
        let mapped = picked.flatMap { $0.type == targetType ? [$0] : related($0, toType: targetType) }
        guard !mapped.isEmpty else {
            r.notes.append(.visibleTypeMismatch)
            r.trace.append("visible \(picked.map(\.type).joined(separator: ", ")) cannot be related to \(targetType)")
            return
        }
        settle(mapped, intent: intent, into: &r)
    }

    private func resolvePriorTurn(_ prior: PriorTurn, targetType: String, into r: inout MockResolution) {
        guard let id = prior.entityId, let previous = catalog.entity(id), model.entity(named: targetType)?.queryType != nil else {
            r.notes.append(.priorTurnUnresolvable)
            r.trace.append("prior-turn entity cannot be re-fetched by identifier")
            return
        }
        let mapped = previous.type == targetType ? [previous] : related(previous, toType: targetType)
        guard let target = mapped.first else {
            r.notes.append(.priorTurnUnresolvable)
            r.trace.append("prior-turn \(previous.type) has no relation to \(targetType)")
            return
        }
        r.entityId = target.id
        r.resolution = "execute"
        r.trace.append("carried over \(previous.id)\(target.id == previous.id ? "" : " → \(target.id)") from the previous turn")
    }

    private func resolveByName(_ segment: String, intent: IntentInfo, targetType: String, into r: inout MockResolution) {
        let indexed = model.indexedEntityTypes.contains(targetType)
        let stringQuery = model.entity(named: targetType)?.hasStringQuery ?? false
        guard indexed || stringQuery else {
            r.notes.append(.entityTypeNotIndexed)
            r.trace.append("\(targetType) is neither indexed nor searchable by string query; names cannot be resolved")
            return
        }
        let pool = catalog.entities.filter { $0.type == targetType }
        let matches = EntityMatcher.search(segment, in: pool, semantic: indexed)
        r.trace.append(indexed ? "semantic index lookup (MOCK lexical/phonetic)" : "EntityStringQuery fallback (exact canonical name only)")
        guard !matches.isEmpty else {
            r.notes.append(.noEntityMatch)
            r.trace.append("no \(targetType) matched")
            return
        }
        settle(matches, intent: intent, into: &r)
    }

    private func settle(_ candidates: [CatalogEntity], intent: IntentInfo, into r: inout MockResolution) {
        if candidates.count == 1 {
            r.entityId = candidates[0].id
            r.resolution = "execute"
        } else if intent.hasDisambiguation {
            r.resolution = "disambiguate"
            r.candidates = candidates.map(\.id)
            r.trace.append("\(candidates.count) candidates; \(intent.name) asks the user to choose")
        } else {
            r.entityId = candidates[0].id
            r.resolution = "execute"
            r.notes.append(.pickedFirstWithoutDisambiguation)
            r.trace.append("\(candidates.count) candidates but \(intent.name) has no disambiguation; picked \(candidates[0].id)")
        }
    }

    func related(_ entity: CatalogEntity, toType type: String) -> [CatalogEntity] {
        let forward = entity.related.values.sorted().compactMap(catalog.entity).filter { $0.type == type }
        if !forward.isEmpty { return forward }
        return catalog.entities.filter { $0.type == type && $0.related.values.contains(entity.id) }
    }
}

/// Lexical/phonetic entity lookup shared by the resolver and the Index Recall simulation.
public enum EntityMatcher {
    struct Hit {
        var entity: CatalogEntity
        var level: Int
        var length: Int
        var key: String
    }

    /// Returns the best-matching entities. With `semantic` (indexed types), fuzzy, phonetic and
    /// reading matches, aliases and spoken-alike expansion apply; without it only an exact match
    /// on the canonical name counts (EntityStringQuery fallback).
    public static func search(_ text: String, in pool: [CatalogEntity], semantic: Bool) -> [CatalogEntity] {
        let tokens = TextMatching.asciiTokens(text)
        let ja = TextMatching.japaneseNormalized(text)
        let jaReading = TextMatching.reading(text)
        var best: [String: Hit] = [:]
        for entity in pool {
            let forms = semantic ? entity.forms : Array(entity.forms.prefix(1))
            for form in forms {
                guard let hit = match(form, entity: entity, tokens: tokens, ja: ja, jaReading: jaReading, semantic: semantic) else { continue }
                if let current = best[entity.id], (current.length, current.level) >= (hit.length, hit.level) { continue }
                best[entity.id] = hit
            }
        }
        // The most specific span wins (longest, measured in tokens or kana), then the strongest match level.
        guard let longest = best.values.map(\.length).max() else { return [] }
        var hits = best.values.filter { $0.length == longest }
        let top = hits.map(\.level).max() ?? 0
        hits = hits.filter { $0.level == top }
        var ids = Set(hits.map(\.entity.id))
        if semantic {
            // Spoken-alike expansion: voice input cannot tell "Jon"/"John" or 講演/公演 apart.
            let keys = Set(hits.map(\.key))
            for entity in pool where !ids.contains(entity.id) && entity.forms.contains(where: { keys.contains(key(of: $0)) }) {
                ids.insert(entity.id)
            }
        }
        var candidates = pool.filter { ids.contains($0.id) }
        if candidates.count > 1 {
            let tokenSet = Set(tokens)
            let qualified = candidates.filter { e in
                e.qualifiers.contains { q in TextMatching.containsJapanese(q) ? ja.contains(TextMatching.japaneseNormalized(q)) : tokenSet.contains(q.lowercased()) }
            }
            if !qualified.isEmpty { candidates = qualified }
        }
        return candidates
    }

    static func key(of form: EntityForm) -> String {
        if TextMatching.containsJapanese(form.text) {
            return "ja:" + TextMatching.japaneseNormalized(form.reading ?? form.text)
        }
        return "en:" + TextMatching.asciiTokens(form.text).map(TextMatching.soundex).joined(separator: " ")
    }

    static func match(_ form: EntityForm, entity: CatalogEntity, tokens: [String], ja: String, jaReading: String, semantic: Bool) -> Hit? {
        if TextMatching.containsJapanese(form.text) {
            let text = TextMatching.japaneseNormalized(form.text)
            let reading = TextMatching.japaneseNormalized(form.reading ?? form.text)
            if !text.isEmpty && ja.contains(text) { return Hit(entity: entity, level: 3, length: reading.count, key: key(of: form)) }
            guard semantic else { return nil }
            if !reading.isEmpty && jaReading.contains(reading) { return Hit(entity: entity, level: 2, length: reading.count, key: key(of: form)) }
            return nil
        }
        let ft = TextMatching.asciiTokens(form.text)
        guard !ft.isEmpty, ft.count <= tokens.count else { return nil }
        var bestLevel = 0
        for start in 0...(tokens.count - ft.count) {
            let window = Array(tokens[start..<(start + ft.count)])
            if window == ft { bestLevel = 3; break }
            guard semantic else { continue }
            let fuzzy = zip(window, ft).allSatisfy { a, b in a == b || (min(a.count, b.count) >= 4 && TextMatching.osaDistance(a, b) <= 1) }
            if fuzzy { bestLevel = max(bestLevel, 2); continue }
            let phonetic = zip(window, ft).allSatisfy { a, b in a == b || (a.count >= 3 && b.count >= 3 && TextMatching.soundex(a) == TextMatching.soundex(b)) }
            if phonetic { bestLevel = max(bestLevel, 1) }
        }
        return bestLevel == 0 ? nil : Hit(entity: entity, level: bestLevel, length: ft.count, key: key(of: form))
    }
}
