# SiriReady Bench report — Orbit Calendar (synthetic calendar app) [`calendar_ok`] (MOCK + REAL)

> **MOCK + REAL result.** Components tagged `real` were measured against the built reference app with AppIntentsTesting (entity queries, Spotlight, View Annotations, intent execution and its side effects). Components tagged `mock` come from SiriReady's rule-based MOCK resolver — in particular F1/F2 (does the utterance reach the intent?) is always MOCK, because AppIntentsTesting cannot observe Siri's language understanding. `static` is the source audit. None of this is a measurement of Siri itself.

## Siri Visibility Score v2 (MOCK + REAL): **94.0 / 100**

Sources: real 54% · mock 25% · static 21%

| Component | Weight | Score | Passed / Total | Source | How it is computed |
|---|---:|---:|---:|---|---|
| Discoverability | 20% | 100.0 | 648 / 648 | mock | cases whose action reached the expected App Intent (not F1/F2) |
| Entity Resolution | 20% | 74.2 | 285 / 384 | real | name-referenced cases without F3/F4/F5, among discovered cases |
| Parameter Accuracy | 10% | 98.6 | 290 / 294 | mock 50% · real 50% | executed cases: MOCK slot filling matches expected.params AND the app persisted those values (observed effect) |
| Index Recall | 15% | 95.0 | 134 / 149 | static 50% · real 50% | 50% × C2 coverage (static, 100%) + 50% × Spotlight probe recall (real, 134/149 = 90%) |
| On-screen & Multi-turn | 15% | 100.0 | 156 / 156 | real | on-screen and previous-turn cases without F3/F5/F6/F7, among discovered cases |
| Static Health | 20% | 100.0 | 648 / 648 | static 70% · real 30% | 70% × audit health (100) + 30% × privacy-routing conformance (100%) |

For comparison, the MOCK-only v2 score for the same cases is **99.3** (mock 78% · static 21%); the Phase 1 (v1, five components) MOCK score is 99.2.

## Failures by class (648 cases; 648 executed against the app, 0 stopped at MOCK F1/F2, 0 not measured)

| Class | Name | MOCK only | MOCK + REAL | decided by real | Representative real cases |
|---|---|---:|---:|---:|---|
| F1 | Not Discovered | 0 | 0 | 0 |  |
| F2 | Wrong Target | 0 | 0 | 0 |  |
| F3 | Entity Misresolution | 13 | 45 | 45 | `calendar-en-029` “Cancel Qaurterly Business Review” — expected entity not returned by Spotlight or the string query<br>`calendar-en-030` “Delete Design Revue from my calendar” — expected entity not returned by Spotlight or the string query |
| F4 | Not Indexed | 0 | 0 | 0 |  |
| F5 | Disambiguation Failure | 0 | 54 | 54 | `calendar-en-057` “Move Thursday's Team Sync to 10:30am” — app asked although the request named one entity<br>`calendar-en-058` “Cancel the Monday Team Sync” — app asked although the request named one entity |
| F6 | On-screen Reference Failure | 0 | 0 | 0 |  |
| F7 | Context Loss | 0 | 0 | 0 |  |
| F8 | Privacy Routing Mismatch | 0 | 0 | 0 |  |

## Where the real run disagrees with the MOCK (86 cases)

| MOCK → REAL | Cases | Examples |
|---|---:|---|
| pass → F3 | 32 | `calendar-en-029` “Cancel Qaurterly Business Review” — expected entity not returned by Spotlight or the string query<br>`calendar-en-030` “Delete Design Revue from my calendar” — expected entity not returned by Spotlight or the string query<br>`calendar-en-031` “Reschedule Daily Satndup to Wednesday at 5pm” — expected entity not returned by Spotlight or the string query |
| pass → F5 | 54 | `calendar-en-057` “Move Thursday's Team Sync to 10:30am” — app asked although the request named one entity<br>`calendar-en-058` “Cancel the Monday Team Sync” — app asked although the request named one entity<br>`calendar-en-059` “Open Team Sync on Thursday” — app asked although the request named one entity |

## Parameters

294 executed cases expect parameters (cases stopped at entity resolution or by a disambiguation request are not counted twice). MOCK slot filling matched expected.params in 294; the app persisted the expected values in 290 (observed effect, real).

## Index

Spotlight probes (real): 134 / 149 returned the probed entity (90%). Entity types with any hit: CalendarEntity, EventEntity. C2 coverage (static): 100%.

## Static audit (C1–C5) — 0 finding(s)

IndexedEntity coverage (C2): **100%** · View Annotations coverage (C3): **100%**

No findings.

## Measurement conditions

| Field | Value |
|---|---|
| Mode | **MOCK + REAL** (resolver `mock-rule-v0`, bench 0.1.0, harness protocol `siriready-harness-v1`) |
| Real stages ran on | iOS Simulator, iOS 27.0.0 — reference app built from Apps/ (see Apps/README.md) |
| MOCK stages used | source fixture `calendar_ok` (same declarations as the built app) |
| Cases | 648 from `cases_eval.jsonl` (fingerprint `b3a65282c8774a52`) |
| Entity catalog | `entities/calendar.json` (fingerprint `079017454805982b`, dataset v1.2, synthetic) |
| Host | macOS Version 27.0.1 (Build 26A434) |
| Not measured | Siri speech recognition / language understanding (F1/F2 are MOCK), system-level disambiguation UI, physical devices |
