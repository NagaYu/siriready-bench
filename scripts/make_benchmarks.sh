#!/usr/bin/env bash
# Regenerate BENCHMARKS.md and docs/mock-divergence-cases.md from the committed results (dataset v1.2).
# Deterministic: the measurement conditions come from benchmarks/phase4-conditions.json.
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -q
BIN="$(swift build --show-bin-path)/siriready"
"$BIN" benchmarks --conditions benchmarks/phase4-conditions.json --out BENCHMARKS.md --divergence-out docs/mock-divergence-cases.md
