# MOCK divergence log

The MOCK resolver (`mock-rule-v0`) decides F1/F2 and stands in for every stage that has no real
measurement. The Phase 2 simulator runs showed where its rules disagree with the real system. This log
lists each divergence, the evidence, the current rule, and how a future resolver version should handle it.

**Policy.** Divergences are not removed by quietly editing the MOCK. A rule change ships as a new resolver
version (`mock-rule-v1`, …) and is recorded here *before* it is applied, together with the cases whose
class it changes. Committed results (`results/`) are never rewritten; they keep the resolver version they
were produced with. The per-case list for the current version is generated into
[`mock-divergence-cases.md`](mock-divergence-cases.md) by `scripts/make_benchmarks.sh`.

Current version: **`mock-rule-v0`** (unchanged since Phase 1). No version bump has been made.

| # | Divergence | Real evidence (Phase 2, dataset v1) | MOCK rule today (`mock-rule-v0`) | Plan for the next version |
|---|---|---|---|---|
| D1 | **Fuzzy / phonetic name matching** | ok apps: 65 typo or sound-alike requests ("Ktaherine Osei", "Sean Patel", "Design Revue") got nothing from `spotlightQuery` or `entities(matching:)` → real F3 | For indexed entity types, accept OSA-distance-1 typos, Soundex matches and kana readings | `mock-rule-v1`: no fuzzy or phonetic matching unless an app opts into it in `siriready.yaml`; typo / ASR cases become F3 for the reference apps (case list: "pass → F3 — expected entity not returned…") |
| D2 | **Qualifiers vs app-side disambiguation** | ok apps: 101 named requests ("Thursday's Team Sync", "Sam Lee from work") made `perform()` ask anyway → real F5 | Qualifiers narrow candidates on the Siri side; an intent with `requestDisambiguation` only asks when more than one candidate is left | Model the app: if `perform()` asks on name collisions (detected statically), qualified requests are F5. Needs a new static signal (whether disambiguation depends on the parameter value or on store collisions) |
| D3 | **String query fallback is broader than "exact canonical name"** | messages_broken: name-only `EntityStringQuery` (forced by Xcode 27.1) resolved full names and partial names ("Alex" → "Alex Rivera") → F4 204 → 112 | Without an index, only an exact canonical-name match counts | Model `localizedCaseInsensitiveContains` semantics for string queries (substring of the canonical name); aliases and readings still need the index |
| D4 | **Possessive titles and katakana punctuation** | Spotlight probes did not return "Jon's Birthday Dinner", "Bryce's Farewell Party", … for their own text; "全社ミーティング" also missed | Possessive `'s` is stripped; middle dots and long vowels are normalized away | Keep the normalization (it is the user's intent), but score Index Recall from real probes when available. v1.1 adds cases for these titles |
| D5 | **Readings and aliases of non-primary entities** | Conversation readings (13 probes) and calendar aliases (仕事, プライベート) are not indexed | Every catalog form counts as searchable once the entity type is IndexedEntity | Only the properties an entity actually indexes (`indexingKey`) should be searchable; requires reading the indexing keys in the static scan |
| D6 | **Privacy routing is input-dependent** | calendar_broken: remote geocoder runs only with a location; no v1 case has one → real F8 = 0 vs MOCK F8 = 72. Phase 3 (v1.1): the 24 location-bearing creates give real F8 = 24 / 24; the MOCK still flags all 108 creates | Any network evidence in an `on_device_only` intent marks every call F8 | Keep C4 as a static finding, but in the MOCK flag F8 only for cases that supply the parameter guarding the call (needs a static guard analysis). v1.1 adds location-bearing cases so F8 is observable |
| D7 | **Same-title silent pick** | calendar_broken updated the Tuesday "Vendor Sync" when Friday's was named (15 cases) | Qualifiers resolve the target before the app runs; an app without disambiguation is only wrong when the request is ambiguous | Model "first match by title" apps: a qualified request still executes on the first same-title entity (F5) |
| D8 | **Alias-level homophones** | 瑞希 / 美月: Spotlight returned one conversation and the app (which compares full readings) did not ask → F5 | Sound-alike expansion over every form, then app disambiguation | Expand only over indexed forms; app-side disambiguation compares full names / readings |
| D9 | **On-screen ambiguity is not observable on the app side** | 12 calendar_broken "Cancel this" cases pass in real (all candidates annotated) but are MOCK F5 | App without disambiguation picks the first visible item | Measurement limit, not a MOCK error: keep the MOCK verdict but report these cases as "not observable" in mixed reports |

## Recording a resolver change

1. Describe the rule change in a new row or under the existing row.
2. Run the new resolver against the committed `results/<phase>` plans and generate the list of cases whose
   class changes (compare with `mock-divergence-cases.md`). Commit that list.
3. Bump `resolverVersion` in `Sources/SiriReadyCore/bench.swift`; reports carry the version, and scores
   from different resolver versions are never compared.
