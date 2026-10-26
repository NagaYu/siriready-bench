#!/usr/bin/env bash
# Local equivalent of the offline CI job (.github/workflows/ci.yml).
#   build → swift test → pytest → dataset validate (v1.2)
#   → BENCHMARKS.md / divergence appendix / HF package are reproducible from committed inputs
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ -z "${DEVELOPER_DIR:-}" && -d /Applications/Xcode.app/Contents/Developer ]]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi
PY="$(command -v python3.12 || command -v python3)"

step() { printf '\n== %s\n' "$*"; }

step "swift build + swift test"
swift build -q
swift test 2>&1 | grep -E "Executed [0-9]+ tests" | tail -1

step "pytest"
PYTEST_PYTHON="${PYTEST_PYTHON:-python3}"
(cd pytests && "$PYTEST_PYTHON" -m pytest -q -p no:cacheprovider)

step "dataset validate"
"$PY" dataset/validate.py --dataset v1.2

step "generated files are up to date"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
"$PY" dataset/generate.py --out "$TMP/dataset" >/dev/null
for f in v1.2/cases_dev.jsonl v1.2/cases_eval.jsonl v1.2/entities/messages.json v1.2/entities/calendar.json; do
  cmp -s "$TMP/dataset/$f" "dataset/$f" || { echo "stale: dataset/$f"; exit 1; }
done
cp BENCHMARKS.md docs/mock-divergence-cases.md "$TMP/"
scripts/make_benchmarks.sh >/dev/null
cmp -s BENCHMARKS.md "$TMP/BENCHMARKS.md" && cmp -s docs/mock-divergence-cases.md "$TMP/mock-divergence-cases.md" \
  || { echo "BENCHMARKS.md or docs/mock-divergence-cases.md is stale; run scripts/make_benchmarks.sh"; exit 1; }
if [[ -f hf/build_hf.py ]]; then
  "${PYTEST_PYTHON}" hf/build_hf.py --check
fi

step "pre-publication scan"
"$PY" scripts/prepublish_scan.py

echo
echo "ci_local: all offline checks passed"
