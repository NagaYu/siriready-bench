#!/usr/bin/env bash
# Real AppIntentsTesting run of one reference app on an iOS 27 simulator (Phase 2, Track B).
#
#   scripts/real_run.sh <messages_ok|messages_broken|calendar_ok|calendar_broken> [--dataset v1.2] [--limit N] [--out DIR]
#                       [--only only.json]   # run only listed cases / probe entities (JSON: {"cases": [...], "probe_entities": [...]})
#
# 1. siriready plan   — MOCK stages (F1/F2, target choice, slot filling) → plan.json
# 2. xcodebuild       — builds Apps/<Domain>/<Variant> and runs the UI-testing harness on it
# 3. siriready ingest — raw observations → F-classes, v2 score with real/mock/static provenance
#
# Needs Xcode 27 with an iOS 27 simulator runtime. No signing identity is required for the
# simulator. Nothing leaves the machine: the apps intercept their own network calls.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
VARIANT="${1:?usage: real_run.sh <variant> [--limit N] [--out DIR]}"; shift
LIMIT=""; OUT=""; DATASET="v1.2"; ONLY=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --limit) LIMIT="$2"; shift 2 ;;
    --dataset) DATASET="$2"; shift 2 ;;
    --only) ONLY="$(cd "$(dirname "$2")" && pwd)/$(basename "$2")"; shift 2 ;;
    --out) OUT="$2"; shift 2 ;;
    *) echo "unknown option $1" >&2; exit 2 ;;
  esac
done
case "$VARIANT" in
  messages_ok)     DIR=Apps/Messages/OK;     NAME=MessagesOK;     BUNDLE=dev.siriready.messages.ok;     CASES=dataset/$DATASET/cases_dev.jsonl ;;
  messages_broken) DIR=Apps/Messages/Broken; NAME=MessagesBroken; BUNDLE=dev.siriready.messages.broken; CASES=dataset/$DATASET/cases_dev.jsonl ;;
  calendar_ok)     DIR=Apps/Calendar/OK;     NAME=CalendarOK;     BUNDLE=dev.siriready.calendar.ok;     CASES=dataset/$DATASET/cases_eval.jsonl ;;
  calendar_broken) DIR=Apps/Calendar/Broken; NAME=CalendarBroken; BUNDLE=dev.siriready.calendar.broken; CASES=dataset/$DATASET/cases_eval.jsonl ;;
  *) echo "unknown variant $VARIANT" >&2; exit 2 ;;
esac
OUT="${OUT:-out/real/$VARIANT}"
mkdir -p "$OUT"
OUT="$(cd "$OUT" && pwd)"

if [[ -z "${DEVELOPER_DIR:-}" && -d /Applications/Xcode.app/Contents/Developer ]]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi
SIM="${SIRIREADY_SIM_ID:-$(xcrun simctl list devices available -j | python3 -c '
import json, sys
d = json.load(sys.stdin)["devices"]
ids = [dev["udid"] for rt, devs in sorted(d.items()) if "iOS-27" in rt for dev in devs if dev["name"].startswith("iPhone")]
print(ids[0] if ids else "")')}"
[[ -n "$SIM" ]] || { echo "no iOS 27 iPhone simulator found (set SIRIREADY_SIM_ID)" >&2; exit 1; }

swift build -q
BIN="$(swift build --show-bin-path)/siriready"
"$BIN" plan --app "Fixtures/apps/$VARIANT" --cases "$CASES" --bundle-id "$BUNDLE" --out "$OUT/plan.json"

RUNPLAN="$OUT/plan.json"
if [[ -n "$ONLY" ]]; then
  RUNPLAN="$OUT/plan.run.json"
  python3 - "$OUT/plan.json" "$ONLY" "$RUNPLAN" <<'PY'
import json, sys
plan, only = json.load(open(sys.argv[1])), json.load(open(sys.argv[2]))
keep, probes = set(only["cases"]), set(only["probe_entities"])
plan["cases"] = [c for c in plan["cases"] if c["caseId"] in keep]
plan["indexProbes"] = [p for p in plan["indexProbes"] if p["entityId"] in probes]
json.dump(plan, open(sys.argv[3], "w"), ensure_ascii=False, indent=1)
print(f"subset plan: {len(plan['cases'])} cases, {len(plan['indexProbes'])} probes")
PY
fi

DERIVED="$ROOT/out/real/DerivedData"
xcodebuild -project "$DIR/$NAME.xcodeproj" -scheme "$NAME" -destination "id=$SIM" -derivedDataPath "$DERIVED" \
  build-for-testing -quiet
rm -f "$OUT/raw.json"
TEST_RUNNER_SIRIREADY_PLAN="$RUNPLAN" TEST_RUNNER_SIRIREADY_OUT="$OUT/raw.json" TEST_RUNNER_SIRIREADY_LIMIT="$LIMIT" \
  xcodebuild -project "$DIR/$NAME.xcodeproj" -scheme "$NAME" -destination "id=$SIM" -derivedDataPath "$DERIVED" \
  -only-testing:"${NAME}UITests/SiriReadyHarness/testRunPlan" test-without-building 2>&1 | tee "$OUT/xcodebuild.log" \
  | grep -E "SIRIREADY|Test Case .*(passed|failed)|error:" || true
[[ -s "$OUT/raw.json" ]] || { echo "harness produced no raw.json (see $OUT/xcodebuild.log)" >&2; exit 1; }

if [[ -n "$ONLY" ]]; then
  echo "subset run: raw observations in $OUT/raw.json (subset only; not ingested)"
  exit 0
fi
SPOT=()
[[ -n "${SIRIREADY_SPOTCHECK:-}" ]] && SPOT=(--spotcheck "$SIRIREADY_SPOTCHECK")
"$BIN" ingest --app "Fixtures/apps/$VARIANT" --cases "$CASES" --plan "$OUT/plan.json" --raw "$OUT/raw.json" --out "$OUT" ${SPOT[@]+"${SPOT[@]}"}
