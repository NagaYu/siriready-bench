# SiriReady Bench report — Relay (synthetic messages app) [`messages_broken`] (MOCK + REAL)

> **MOCK + REAL result.** Components tagged `real` were measured against the built reference app with AppIntentsTesting (entity queries, Spotlight, View Annotations, intent execution and its side effects). Components tagged `mock` come from SiriReady's rule-based MOCK resolver — in particular F1/F2 (does the utterance reach the intent?) is always MOCK, because AppIntentsTesting cannot observe Siri's language understanding. `static` is the source audit. None of this is a measurement of Siri itself.

## Siri Visibility Score v2 (MOCK + REAL): **68.8 / 100**

Sources: real 54% · mock 25% · static 21%

| Component | Weight | Score | Passed / Total | Source | How it is computed |
|---|---:|---:|---:|---|---|
| Discoverability | 20% | 72.6 | 453 / 624 | mock | cases whose action reached the expected App Intent (not F1/F2) |
| Entity Resolution | 20% | 51.4 | 168 / 327 | real | name-referenced cases without F3/F4/F5, among discovered cases |
| Parameter Accuracy | 10% | 100.0 | 136 / 136 | mock 50% · real 50% | executed cases: MOCK slot filling matches expected.params AND the app persisted those values (observed effect) |
| Index Recall | 15% | 58.9 | 178 / 348 | static 50% · real 50% | 50% × C2 coverage (static, 67%) + 50% × Spotlight probe recall (real, 178/348 = 51%) |
| On-screen & Multi-turn | 15% | 76.2 | 96 / 126 | real | on-screen and previous-turn cases without F3/F5/F6/F7, among discovered cases |
| Static Health | 20% | 68.5 | 453 / 453 | static 70% · real 30% | 70% × audit health (55) + 30% × privacy-routing conformance (100%) |

For comparison, the MOCK-only v2 score for the same cases is **66.2** (mock 78% · static 21%); the Phase 1 (v1, five components) MOCK score is 61.7.

## Failures by class (624 cases; 453 executed against the app, 171 stopped at MOCK F1/F2, 0 not measured)

| Class | Name | MOCK only | MOCK + REAL | decided by real | Representative real cases |
|---|---|---:|---:|---:|---|
| F1 | Not Discovered | 168 | 168 | 0 |  |
| F2 | Wrong Target | 3 | 3 | 0 |  |
| F3 | Entity Misresolution | 2 | 18 | 18 | `messages-en-037` “Open my conversation with Dnaiela Fischer” — expected entity not returned by Spotlight or the string query<br>`messages-en-038` “Show my chat with Markus Lindqvist” — expected entity not returned by Spotlight or the string query |
| F4 | Not Indexed | 204 | 112 | 112 | `messages-en-029` “Send Ktaherine Osei a message saying can you bring the charger” — ContactEntity has no Spotlight hits in this run and the string query missed<br>`messages-en-030` “Text Sean Patel saying see you at the station” — ContactEntity has no Spotlight hits in this run and the string query missed |
| F5 | Disambiguation Failure | 0 | 29 | 29 | `messages-en-057` “Send Sam Lee from work a message saying call me when you land” — app asked although the request named one entity<br>`messages-en-059` “Open my conversation with Sam Lee from work” — app asked although the request named one entity |
| F6 | On-screen Reference Failure | 30 | 30 | 30 | `messages-en-082` “Mark this as read” — visible entities are not all annotated<br>`messages-en-083` “Mark this message as read” — visible entities are not all annotated |
| F7 | Context Loss | 0 | 0 | 0 |  |
| F8 | Privacy Routing Mismatch | 0 | 0 | 0 |  |

## Where the real run disagrees with the MOCK (123 cases)

| MOCK → REAL | Cases | Examples |
|---|---:|---|
| F4 → F5 | 14 | `messages-en-057` “Send Sam Lee from work a message saying call me when you land” — app asked although the request named one entity<br>`messages-en-060` “Tell Sam Lee from the gym: can you bring the charger” — app asked although the request named one entity<br>`messages-en-072` “Tell John Parke from finance: see you at the station” — app asked although the request named one entity |
| F4 → pass | 78 | `messages-en-001` “Send Marcus Lindqvist a message saying thanks for yesterday” — executed<br>`messages-en-002` “Text Daniela Fischer saying lunch is on me today” — executed<br>`messages-en-003` “Message Omar Haddad: lunch is on me today” — executed |
| pass → F3 | 16 | `messages-en-037` “Open my conversation with Dnaiela Fischer” — expected entity not returned by Spotlight or the string query<br>`messages-en-038` “Show my chat with Markus Lindqvist” — expected entity not returned by Spotlight or the string query<br>`messages-en-137` “Could you please open my conversation with Ivan Sroensen” — expected entity not returned by Spotlight or the string query |
| pass → F5 | 15 | `messages-en-059` “Open my conversation with Sam Lee from work” — app asked although the request named one entity<br>`messages-en-062` “Show my chat with Sam Lee from the gym” — app asked although the request named one entity<br>`messages-en-159` “Could you please open my conversation with Chris Moreno from the studio” — app asked although the request named one entity |

## Parameters

136 executed cases expect parameters (cases stopped at entity resolution or by a disambiguation request are not counted twice). MOCK slot filling matched expected.params in 136; the app persisted the expected values in 136 (observed effect, real).

## Index

Spotlight probes (real): 178 / 348 returned the probed entity (51%). Entity types with any hit: ConversationEntity, MessageEntity. C2 coverage (static): 67%.

## Static audit (C1–C5) — 3 finding(s)

IndexedEntity coverage (C2): **67%** · View Annotations coverage (C3): **75%**

Ordered by impact on discoverability (severity, then check). Suggestions are text only; SiriReady never edits the app.

1. **[C1 Companion schema · high]** `Sources/Intents.swift:5` → expected to surface as F1
   - Reason: SendMessageIntent adopts .messages.sendMessage but no type adopts .messages.draftMessage. Basis: WWDC26 session 240 (Xcode reports draftMessage missing when sendMessage is adopted).
   - Suggestion: Add a type annotated with @AppIntent(schema: .messages.draftMessage) so Siri can reach the companion action/entity.
2. **[C2 IndexedEntity coverage · high]** `Sources/Entities.swift:7` → expected to surface as F4
   - Reason: ContactEntity is listed in siriready.yaml indexed_entities but does not conform to IndexedEntity, so it never reaches the semantic index.
   - Suggestion: Conform ContactEntity to IndexedEntity, mark searchable properties with @Property(indexingKey:), and index instances with CSSearchableIndex.indexAppEntities(_:).
3. **[C3 View Annotations coverage · high]** `Sources/Views.swift:39` → expected to surface as F6
   - Reason: MessageDetailView (screen message_detail) displays MessageEntity without a View Annotation, so "this" / "the second one" cannot be resolved on this screen.
   - Suggestion: Attach .appEntityIdentifier(EntityIdentifier(for: MessageEntity.self, identifier: item.id)) to each displayed item (or use NSUserActivity for a single primary item).

## Measurement conditions

| Field | Value |
|---|---|
| Mode | **MOCK + REAL** (resolver `mock-rule-v0`, bench 0.1.0, harness protocol `siriready-harness-v1`) |
| Real stages ran on | iOS Simulator, iOS 27.0.0 — reference app built from Apps/ (see Apps/README.md) |
| MOCK stages used | source fixture `messages_broken` (same declarations as the built app) |
| Cases | 624 from `cases_dev.jsonl` (fingerprint `4761627fb82683de`) |
| Entity catalog | `entities/messages.json` (fingerprint `f501847c15850ce7`, dataset v1.2, synthetic) |
| Host | macOS Version 27.0.1 (Build 26A434) |
| Not measured | Siri speech recognition / language understanding (F1/F2 are MOCK), system-level disambiguation UI, physical devices |
