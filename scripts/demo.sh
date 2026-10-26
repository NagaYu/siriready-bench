#!/usr/bin/env bash
# SiriReady Bench Phase 1 demo: audit → bench → report for ok vs broken fixtures.
# Fully offline. All scores are MOCK (rule-based resolver), not Siri measurements.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
OUT="${1:-out/demo}"
PY="$(command -v python3.12 || command -v python3)"

echo "== build"
swift build -q
BIN="$(swift build --show-bin-path)/siriready"

echo "== dataset"
"$PY" dataset/validate.py --dataset v1.2

run_pair() {
  local domain="$1" cases="$2"
  echo
  echo "################ ${domain}: ok vs broken ################"
  for variant in ok broken; do
    local app="Fixtures/apps/${domain}_${variant}"
    echo
    echo "== audit ${domain}_${variant}"
    "$BIN" audit --app "$app" --out "$OUT/${domain}_${variant}/audit.md"
    grep -E '^[0-9]+\. \*\*\[' "$OUT/${domain}_${variant}/audit.md" | sed -E 's/\*\*//g' || echo "No findings."
    echo "== bench ${domain}_${variant}"
    "$BIN" bench --app "$app" --cases "$cases" --out "$OUT/${domain}_${variant}"
  done
  echo
  echo "== report: comparison (${domain})"
  "$BIN" report --compare "$OUT/${domain}_ok" "$OUT/${domain}_broken" --out "$OUT/${domain}_compare.md"
  sed -n '/^| |/,/^$/p' "$OUT/${domain}_compare.md"
}

run_pair messages dataset/v1.2/cases_dev.jsonl
run_pair calendar dataset/v1.2/cases_eval.jsonl

# report re-renders Markdown from the JSON result (round trip).
"$BIN" report --in "$OUT/messages_broken" >/dev/null

echo
echo "Reports: $OUT/<fixture>/report.md, report.json; comparisons: $OUT/*_compare.md"
echo "Reminder: MOCK scores show the effect of static gaps under SiriReady's own rules."
echo "They are not Siri / Spotlight measurements and not OS-independent absolute values (Phase 2 measures the real system)."
