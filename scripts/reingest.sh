#!/usr/bin/env bash
# Rebuild the MOCK+REAL reports in results/phase4/ from the committed plan.json + raw.json
# (no simulator needed). raw.json files are the observations of real AppIntentsTesting runs.
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -q
BIN="$(swift build --show-bin-path)/siriready"
for v in messages_ok messages_broken calendar_ok calendar_broken; do
  case "$v" in messages*) CASES=dataset/v1.2/cases_dev.jsonl ;; *) CASES=dataset/v1.2/cases_eval.jsonl ;; esac
  dir="results/phase4/$v"
  "$BIN" ingest --app "Fixtures/apps/$v" --cases "$CASES" --plan "$dir/plan.json" --raw "$dir/raw.json" --out "$dir" \
    ${SIRIREADY_SPOTCHECK:+--spotcheck "$SIRIREADY_SPOTCHECK"}
  rm -f "$dir/mixed.json"   # large and fully reproducible from plan + raw
done
