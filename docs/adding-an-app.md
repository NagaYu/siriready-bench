# Adding an app to SiriReady Bench

SiriReady Bench measures how well an iOS app's App Intents surface works with the new Siri. You can
take part with **a built app and a `siriready.yaml`**. The real-run harness needs only the app's
**bundle identifier**: it discovers intents and entities through AppIntentsTesting at run time and
never imports or compiles your source code.

## What you provide

| Item | Required | Purpose |
|---|---|---|
| A simulator build of the app (`.app`, Debug, iOS 27 SDK) | yes | Installed on an iOS 27 simulator and driven by the harness |
| Bundle identifier | yes | `IntentDefinitions(bundleIdentifier:)` in the harness |
| `siriready.yaml` | yes | Declares what the source cannot show: indexed entities, annotated views, per-intent privacy routing, screens and the entity types they display (format in the main README) |
| Synthetic seed data and an entity catalog (`entities/<app_id>.json`) | yes | The app must start with invented content the dataset can refer to. **No real personal data.** |
| Test-only hooks (see below) | yes, for the real run | Let the harness put the app into a screen state and read what an intent persisted |
| Source code | **no** | Only needed if you also want the static audit (C1–C5) and the MOCK resolver; without it those components are reported as `n/a` |

## Test-only hooks (DEBUG builds only)

Follow the test-only intent pattern from WWDC26 session 295 (`isDiscoverable = false`, `#if DEBUG`):

1. **Screen state from launch arguments** — `-siriready-screen <name> -siriready-ids <id,id,…>` shows the
   listed entities on the named screen, so `viewAnnotations()` can be measured.
2. **`DebugProbeIntent`** — returns, as a JSON string, the side effects your intents persisted since the last
   call (`intent`, `target` id, parameter values) and the hosts the app tried to reach; then resets them.
3. **Local egress recording** — register a `URLProtocol` that answers every HTTP(S) request locally and records
   the host, so F8 (privacy routing) can be observed without data leaving the machine.

`Apps/Common/BenchSupport.swift` is a reference implementation of all three.

## How a run works

```bash
siriready plan   --app <dir with siriready.yaml> --cases <jsonl> --bundle-id <id> --out plan.json
# install the .app on an iOS 27 simulator, then run the UI-testing harness (Apps/Harness) with
#   TEST_RUNNER_SIRIREADY_PLAN=plan.json TEST_RUNNER_SIRIREADY_OUT=raw.json
siriready ingest --app <dir> --cases <jsonl> --plan plan.json --raw raw.json --out <dir>
```

`scripts/real_run.sh` does all three for the reference apps. For a third-party app, the harness target is
built against your bundle ID only; your app is installed separately.

## What is and is not measured for your app

- **Measured (real):** entity lookup through your `EntityStringQuery` and Spotlight, View Annotations on the
  declared screens, intent execution, persisted parameters, attempted network egress, and the Spotlight index
  over every form in your catalog.
- **Not measured:** whether real users' utterances reach your intents (F1/F2) — that is the MOCK resolver, or
  a manual spot check on a device (`docs/spotcheck-protocol.md`). Physical devices are not part of the
  automatic run.
- Results are tied to the OS build, Xcode build and simulator runtime of the run and are reported with them.

## Submission checklist

- [ ] Seed data and catalog are invented (no real people, accounts or messages)
- [ ] `siriready.yaml` describes the intended indexing, annotations and privacy routing
- [ ] DEBUG hooks present and excluded from release builds
- [ ] The app builds for the iOS 27 simulator without a development team
- [ ] You agree to publication of the scores together with their sources (real / mock / static) and conditions
