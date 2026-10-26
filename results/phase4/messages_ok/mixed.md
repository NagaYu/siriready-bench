# SiriReady Bench report — Relay (synthetic messages app) [`messages_ok`] (MOCK + REAL)

> **MOCK + REAL result.** Components tagged `real` were measured against the built reference app with AppIntentsTesting (entity queries, Spotlight, View Annotations, intent execution and its side effects). Components tagged `mock` come from SiriReady's rule-based MOCK resolver — in particular F1/F2 (does the utterance reach the intent?) is always MOCK, because AppIntentsTesting cannot observe Siri's language understanding. `static` is the source audit. None of this is a measurement of Siri itself.

## Siri Visibility Score v2 (MOCK + REAL): **95.0 / 100**

Sources: real 54% · mock 25% · static 21%

| Component | Weight | Score | Passed / Total | Source | How it is computed |
|---|---:|---:|---:|---|---|
| Discoverability | 20% | 99.5 | 621 / 624 | mock | cases whose action reached the expected App Intent (not F1/F2) |
| Entity Resolution | 20% | 76.8 | 357 / 465 | real | name-referenced cases without F3/F4/F5, among discovered cases |
| Parameter Accuracy | 10% | 100.0 | 367 / 367 | mock 50% · real 50% | executed cases: MOCK slot filling matches expected.params AND the app persisted those values (observed effect) |
| Index Recall | 15% | 98.0 | 334 / 348 | static 50% · real 50% | 50% × C2 coverage (static, 100%) + 50% × Spotlight probe recall (real, 334/348 = 96%) |
| On-screen & Multi-turn | 15% | 100.0 | 156 / 156 | real | on-screen and previous-turn cases without F3/F5/F6/F7, among discovered cases |
| Static Health | 20% | 100.0 | 621 / 621 | static 70% · real 30% | 70% × audit health (100) + 30% × privacy-routing conformance (100%) |

For comparison, the MOCK-only v2 score for the same cases is **99.5** (mock 78% · static 21%); the Phase 1 (v1, five components) MOCK score is 99.3.

## Failures by class (624 cases; 621 executed against the app, 3 stopped at MOCK F1/F2, 0 not measured)

| Class | Name | MOCK only | MOCK + REAL | decided by real | Representative real cases |
|---|---|---:|---:|---:|---|
| F1 | Not Discovered | 0 | 0 | 0 |  |
| F2 | Wrong Target | 3 | 3 | 0 |  |
| F3 | Entity Misresolution | 10 | 52 | 52 | `messages-en-029` “Send Ktaherine Osei a message saying can you bring the charger” — expected entity not returned by Spotlight or the string query<br>`messages-en-030` “Text Sean Patel saying see you at the station” — expected entity not returned by Spotlight or the string query |
| F4 | Not Indexed | 0 | 0 | 0 |  |
| F5 | Disambiguation Failure | 0 | 56 | 56 | `messages-en-057` “Send Sam Lee from work a message saying call me when you land” — app asked although the request named one entity<br>`messages-en-058` “Write a draft to Sam Lee from the gym: I'm running ten minutes late” — app asked although the request named one entity |
| F6 | On-screen Reference Failure | 0 | 0 | 0 |  |
| F7 | Context Loss | 0 | 0 | 0 |  |
| F8 | Privacy Routing Mismatch | 0 | 0 | 0 |  |

## Where the real run disagrees with the MOCK (98 cases)

| MOCK → REAL | Cases | Examples |
|---|---:|---|
| pass → F3 | 42 | `messages-en-029` “Send Ktaherine Osei a message saying can you bring the charger” — expected entity not returned by Spotlight or the string query<br>`messages-en-030` “Text Sean Patel saying see you at the station” — expected entity not returned by Spotlight or the string query<br>`messages-en-033` “Write a draft to Marcus Lnidqvist: I'm running ten minutes late” — expected entity not returned by Spotlight or the string query |
| pass → F5 | 56 | `messages-en-057` “Send Sam Lee from work a message saying call me when you land” — app asked although the request named one entity<br>`messages-en-058` “Write a draft to Sam Lee from the gym: I'm running ten minutes late” — app asked although the request named one entity<br>`messages-en-059` “Open my conversation with Sam Lee from work” — app asked although the request named one entity |

## Parameters

367 executed cases expect parameters (cases stopped at entity resolution or by a disambiguation request are not counted twice). MOCK slot filling matched expected.params in 367; the app persisted the expected values in 367 (observed effect, real).

## Index

Spotlight probes (real): 334 / 348 returned the probed entity (96%). Entity types with any hit: ContactEntity, ConversationEntity, MessageEntity. C2 coverage (static): 100%.

## Static audit (C1–C5) — 0 finding(s)

IndexedEntity coverage (C2): **100%** · View Annotations coverage (C3): **100%**

No findings.

## Measurement conditions

| Field | Value |
|---|---|
| Mode | **MOCK + REAL** (resolver `mock-rule-v0`, bench 0.1.0, harness protocol `siriready-harness-v1`) |
| Real stages ran on | iOS Simulator, iOS 27.0.0 — reference app built from Apps/ (see Apps/README.md) |
| MOCK stages used | source fixture `messages_ok` (same declarations as the built app) |
| Cases | 624 from `cases_dev.jsonl` (fingerprint `4761627fb82683de`) |
| Entity catalog | `entities/messages.json` (fingerprint `f501847c15850ce7`, dataset v1.2, synthetic) |
| Host | macOS Version 27.0.1 (Build 26A434) |
| Not measured | Siri speech recognition / language understanding (F1/F2 are MOCK), system-level disambiguation UI, physical devices |
