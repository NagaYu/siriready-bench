# SiriReady Bench report — Orbit Calendar (synthetic calendar app) [`calendar_broken`] (MOCK + REAL)

> **MOCK + REAL result.** Components tagged `real` were measured against the built reference app with AppIntentsTesting (entity queries, Spotlight, View Annotations, intent execution and its side effects). Components tagged `mock` come from SiriReady's rule-based MOCK resolver — in particular F1/F2 (does the utterance reach the intent?) is always MOCK, because AppIntentsTesting cannot observe Siri's language understanding. `static` is the source audit. None of this is a measurement of Siri itself.

## Siri Visibility Score v2 (MOCK + REAL): **83.4 / 100**

Sources: real 54% · mock 25% · static 21%

| Component | Weight | Score | Passed / Total | Source | How it is computed |
|---|---:|---:|---:|---|---|
| Discoverability | 20% | 83.8 | 543 / 648 | mock | cases whose action reached the expected App Intent (not F1/F2) |
| Entity Resolution | 20% | 66.7 | 210 / 315 | real | name-referenced cases without F3/F4/F5, among discovered cases |
| Parameter Accuracy | 10% | 98.4 | 242 / 246 | mock 50% · real 50% | executed cases: MOCK slot filling matches expected.params AND the app persisted those values (observed effect) |
| Index Recall | 15% | 95.0 | 134 / 149 | static 50% · real 50% | 50% × C2 coverage (static, 100%) + 50% × Spotlight probe recall (real, 134/149 = 90%) |
| On-screen & Multi-turn | 15% | 100.0 | 120 / 120 | real | on-screen and previous-turn cases without F3/F5/F6/F7, among discovered cases |
| Static Health | 20% | 71.4 | 519 / 543 | static 70% · real 30% | 70% × audit health (61) + 30% × privacy-routing conformance (96%) |

For comparison, the MOCK-only v2 score for the same cases is **84.9** (mock 78% · static 21%); the Phase 1 (v1, five components) MOCK score is 83.2.

## Failures by class (648 cases; 543 executed against the app, 105 stopped at MOCK F1/F2, 0 not measured)

| Class | Name | MOCK only | MOCK + REAL | decided by real | Representative real cases |
|---|---|---:|---:|---:|---|
| F1 | Not Discovered | 105 | 105 | 0 |  |
| F2 | Wrong Target | 0 | 0 | 0 |  |
| F3 | Entity Misresolution | 10 | 42 | 42 | `calendar-en-029` “Cancel Qaurterly Business Review” — expected entity not returned by Spotlight or the string query<br>`calendar-en-030` “Delete Design Revue from my calendar” — expected entity not returned by Spotlight or the string query |
| F4 | Not Indexed | 0 | 0 | 0 |  |
| F5 | Disambiguation Failure | 60 | 63 | 63 | `calendar-en-057` “Move Thursday's Team Sync to 10:30am” — app acted on ev_sync_mon instead of ev_sync_thu<br>`calendar-en-059` “Open Team Sync on Thursday” — app acted on ev_sync_mon instead of ev_sync_thu |
| F6 | On-screen Reference Failure | 0 | 0 | 0 |  |
| F7 | Context Loss | 0 | 0 | 0 |  |
| F8 | Privacy Routing Mismatch | 108 | 24 | 24 | `calendar-en-301` “I need you to add Coffee with the design team on tomorrow at 1pm at Harbor Clinic” — declared on_device_only but the app attempted to reach geo.orbit.example (intercepted locally)<br>`calendar-en-302` “Schedule Coffee with the design team for next Monday at 9am at Northside Studio, thanks” — declared on_device_only but the app attempted to reach geo.orbit.example (intercepted locally) |

## Where the real run disagrees with the MOCK (143 cases)

| MOCK → REAL | Cases | Examples |
|---|---:|---|
| F5 → pass | 12 | `calendar-en-087` “Cancel this” — all visible entities are annotated; the system can ask which one (app side not observable)<br>`calendar-en-088` “Delete this one” — all visible entities are annotated; the system can ask which one (app side not observable)<br>`calendar-en-187` “I need you to cancel this” — all visible entities are annotated; the system can ask which one (app side not observable) |
| F8 → pass | 84 | `calendar-en-001` “Add Budget check on tomorrow at 4:30pm” — executed<br>`calendar-en-002` “Schedule Dentist appointment for Wednesday at 9am” — executed<br>`calendar-en-003` “Put Dentist appointment on my calendar for next Monday at 10:30am” — executed |
| pass → F3 | 32 | `calendar-en-029` “Cancel Qaurterly Business Review” — expected entity not returned by Spotlight or the string query<br>`calendar-en-030` “Delete Design Revue from my calendar” — expected entity not returned by Spotlight or the string query<br>`calendar-en-031` “Reschedule Daily Satndup to Wednesday at 5pm” — expected entity not returned by Spotlight or the string query |
| pass → F5 | 15 | `calendar-en-057` “Move Thursday's Team Sync to 10:30am” — app acted on ev_sync_mon instead of ev_sync_thu<br>`calendar-en-059` “Open Team Sync on Thursday” — app acted on ev_sync_mon instead of ev_sync_thu<br>`calendar-en-157` “I need you to move Friday's Vendor Sync to 10:30am” — app acted on ev_vendor_tue instead of ev_vendor_fri |

## Parameters

246 executed cases expect parameters (cases stopped at entity resolution or by a disambiguation request are not counted twice). MOCK slot filling matched expected.params in 246; the app persisted the expected values in 242 (observed effect, real).

## Index

Spotlight probes (real): 134 / 149 returned the probed entity (90%). Entity types with any hit: CalendarEntity, EventEntity. C2 coverage (static): 100%.

## Static audit (C1–C5) — 4 finding(s)

IndexedEntity coverage (C2): **100%** · View Annotations coverage (C3): **100%**

Ordered by impact on discoverability (severity, then check). Suggestions are text only; SiriReady never edits the app.

1. **[C5 SiriKit remnants · high]** `Sources/LegacySiriKit/IntentHandler.swift:1` → expected to surface as F1
   - Reason: SiriKit remains in Sources/LegacySiriKit/IntentHandler.swift (INExtension, INIntent, SiriKit intent handling protocol, import Intents; lines 1, 5, 6, 14). SiriKit is legacy; the new Siri integrates through App Intents. ShareEventIntent has no App Intent counterpart, so the new Siri cannot discover it.
   - Suggestion: Re-implement ShareEventIntent as an App Intent (and register it in an AppShortcutsProvider), then delete the SiriKit extension.
2. **[C4 Privacy manifest consistency · high]** `Sources/Intents.swift:5` → expected to surface as F8
   - Reason: CreateEventIntent is declared on_device_only, but its implementation shows off-device transmission (URLSession, remote URL literal).
   - Suggestion: Either keep the work on device (e.g. a local geocoder/cache) or declare the intent cloud_allowed and disclose it in the privacy manifest.
3. **[C5 SiriKit remnants · medium]** `Sources/LegacySiriKit/Intents.intentdefinition:1` → expected to surface as F1
   - Reason: SiriKit remains in Sources/LegacySiriKit/Intents.intentdefinition (SiriKit intent definition file; lines 1). SiriKit is legacy; the new Siri integrates through App Intents.
   - Suggestion: Re-implement ShareEventIntent as an App Intent (and register it in an AppShortcutsProvider), then delete the SiriKit extension.
4. **[C4 Privacy manifest consistency · low]** `siriready.yaml`
   - Reason: siriready.yaml privacy declares ShareEventIntent, but no App Intent with that name exists (it only exists as a SiriKit intent).
   - Suggestion: Remove the stale declaration or implement ShareEventIntent as an App Intent.

## Measurement conditions

| Field | Value |
|---|---|
| Mode | **MOCK + REAL** (resolver `mock-rule-v0`, bench 0.1.0, harness protocol `siriready-harness-v1`) |
| Real stages ran on | iOS Simulator, iOS 27.0.0 — reference app built from Apps/ (see Apps/README.md) |
| MOCK stages used | source fixture `calendar_broken` (same declarations as the built app) |
| Cases | 648 from `cases_eval.jsonl` (fingerprint `b3a65282c8774a52`) |
| Entity catalog | `entities/calendar.json` (fingerprint `079017454805982b`, dataset v1.2, synthetic) |
| Host | macOS Version 27.0.1 (Build 26A434) |
| Not measured | Siri speech recognition / language understanding (F1/F2 are MOCK), system-level disambiguation UI, physical devices |
