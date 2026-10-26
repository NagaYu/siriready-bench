# SiriReady Bench

**Does your iOS app actually reach the new Siri?** Since WWDC26, App Intents — App Schemas, `IndexedEntity`
and View Annotations — are how apps integrate with Siri. Xcode tells you whether an implementation conforms
to a schema. SiriReady Bench asks the next question: will a request phrased the way people really talk reach
the right intent, act on the right entity, ask when it should, and keep data where you said it stays?

It combines a static audit of your App Intents source, a bilingual (English / Japanese) utterance dataset,
and a real-run harness that drives a built app through **AppIntentsTesting on an iOS simulator**. Every
number it reports carries its source: `real`, `mock`, `static` or `spotcheck`.

## What is measured — and what is not

| Stage | How | Source |
|---|---|---|
| Does the utterance reach the right intent? (F1/F2) | Rule-based MOCK resolver over the app's declarations | **mock** — AppIntentsTesting calls intents directly and never exercises Siri's speech recognition or language understanding |
| Is the intent in the built app? | AppIntentsTesting metadata | real |
| Name → entity (F3/F4) | `entities(matching:)` and `spotlightQuery(_:)` against the running app | real |
| Asking when ambiguous (F5) | Whether `run()` stops with an app-requested disambiguation; which entity the app actually acted on | real |
| On-screen references (F6) | `viewAnnotations()` on a prepared screen state | real |
| Previous-turn references (F7) | `entities(identifiers:)` | real |
| Privacy routing (F8) | Network attempts recorded inside the app (intercepted locally, never sent) | real |
| Parameters | MOCK slot filling, then what the app persisted | mock + real |
| Index recall | Spotlight probes for every form of every entity + static coverage | real + static |
| Source audit C1–C5 (companion schemas, indexing, annotations, privacy declarations, SiriKit remnants) | Text analysis of Swift source and `siriready.yaml` | static |
| Physical-device Siri | Manual protocol in `docs/spotcheck-protocol.md` | spotcheck — **protocol only; no device run has been recorded yet** |

Scores depend on the OS build, Xcode build, simulator runtime and locale. They are not absolute,
OS-independent values, and MOCK-only scores are never mixed with real ones without a source label.

## Headline results

Four reference apps built for this benchmark (two correct, two intentionally broken), 624 (messages) or 648
(calendar) cases each (dataset v1.2), measured with AppIntentsTesting on an iOS 27.0 simulator built with
Xcode 27.1 / iOS 27.1 SDK. Every MOCK + REAL score is composed of **real 54% · mock 25% · static 21%**.

| App | MOCK only | MOCK + REAL | Main real failure classes |
|---|---:|---:|---|
| messages_ok | 99.5 | **95.0** | F5 = 56 (over-asking), F3 = 52 (typos / sound-alikes / unindexed readings) |
| messages_broken | 66.2 | **68.8** | F1 = 168 (mock), F4 = 112, F6 = 30 |
| calendar_ok | 99.3 | **94.0** | F5 = 54, F3 = 45 |
| calendar_broken | 84.9 | **83.4** | F1 = 105 (mock), F5 = 63, F3 = 42, F8 = 24 |

What the real runs showed that the MOCK did not: correct apps over-ask after a request already named one
entity; Spotlight and string queries do not match typos or sound-alike spellings; possessive titles,
conversation readings and calendar aliases fall out of the index; a broken app silently acts on a same-name
sibling; the toolchain itself forced a string query into a broken app; and a static privacy finding is
input-dependent — the broken calendar app's off-device call is observed in 24 of 24 location-bearing requests
(intercepted locally) and in none of the others, and the correct app never makes one. Full tables, conditions and
findings: **[BENCHMARKS.md](BENCHMARKS.md)**.

Earlier dataset versions (v0, v1, v1.1) and their raw results contain names that were replaced before
publication, so they are kept in the development repository and not published here. Dataset v1.2 differs from
v1.1 only by those renames, and its scores are identical.

Every disagreement with the MOCK is logged in [docs/mock-divergence.md](docs/mock-divergence.md).

## Run it

Requirements: macOS with Xcode 27 (XCTest is not in the Command Line Tools), Python 3.12 for the dataset
tools (standard library only), pytest for the Python tests, and an iOS 27 simulator runtime for real runs.
No signing identity is needed for the simulator.

```bash
# Offline: build, unit tests, dataset validation, reproducibility checks (same as the CI offline job)
scripts/ci_local.sh

# Static audit and MOCK scoring of a source fixture
swift build
.build/debug/siriready audit --app Fixtures/apps/messages_broken
.build/debug/siriready bench --app Fixtures/apps/messages_broken --cases dataset/v1.2/cases_dev.jsonl --out out/messages_broken

# Real run on an iOS 27 simulator (8–10 minutes per app)
scripts/real_run.sh calendar_broken --dataset v1.2

# Rebuild reports and BENCHMARKS.md from the committed raw observations
scripts/reingest.sh && scripts/make_benchmarks.sh
```

To benchmark your own app you only need a simulator build, its bundle identifier and a `siriready.yaml`
— the harness never imports your source. See [docs/adding-an-app.md](docs/adding-an-app.md).

## Repository map

| Path | Contents |
|---|---|
| `Sources/SiriReadyCore`, `Sources/siriready` | Audit, MOCK resolver, scoring (v1 and v2 profiles), real-run plan / ingest, reports, CLI |
| `Fixtures/apps/` | Source fixtures of the four reference apps (input of the audit and the MOCK) |
| `Apps/` | The same four apps as buildable Xcode projects, plus the AppIntentsTesting harness ([Apps/README.md](Apps/README.md)) |
| `dataset/` | Generator and validator; dataset v1.2 (1,272 cases); [BENCH_CARD.md](dataset/BENCH_CARD.md) |
| `results/phase4/` | Plans and raw observations of the real runs on dataset v1.2, with MOCK + REAL reports |
| `hf/` | Hugging Face dataset package (dev split only), built by `hf/build_hf.py` |
| `docs/` | Spot-check protocol, adding an app, MOCK divergence log, name review, detailed Japanese README (development history) |
| `.github/workflows/` | Offline CI gate and a manual real-run workflow |
| `pytests/`, `Tests/` | Python and XCTest suites |

## Status

Real runs: iOS simulator only. Physical-device Siri spot checks: protocol written, not yet performed.

## License

Published for evaluation; all rights reserved. You may view, download and run the code and benchmark to
evaluate it and cite the published results with attribution; redistribution, sublicensing and commercial use
need prior written permission. The project is available for transfer or licensing. See [LICENSE](LICENSE).

All people and organization names in the data are fictional, synthetic data and are not related to any real person or organization.
登場する人名・組織名はすべて架空の合成データであり、実在の人物・団体とは関係ありません。

Apple, Siri, iOS and Xcode are trademarks of Apple Inc.; this project is not affiliated with Apple.

Contact: <https://nagayu-portfolio.nagayu.workers.dev/en>
