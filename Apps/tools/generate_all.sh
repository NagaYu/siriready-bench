#!/usr/bin/env bash
# Regenerate the reference apps' seed data and Xcode projects (deterministic, stdlib Python only).
set -euo pipefail
cd "$(dirname "$0")/.."
PY="$(command -v python3.12 || command -v python3)"
"$PY" tools/make_seed.py
for spec in "Messages OK MessagesOK dev.siriready.messages.ok" "Messages Broken MessagesBroken dev.siriready.messages.broken" \
            "Calendar OK CalendarOK dev.siriready.calendar.ok" "Calendar Broken CalendarBroken dev.siriready.calendar.broken"; do
  read -r domain variant name bundle <<<"$spec"
  "$PY" tools/make_xcodeproj.py --name "$name" --bundle-id "$bundle" --app-dir App --shared-dir ../Shared \
    --shared-dir ../../Common --test-dir ../../Harness --out "$domain/$variant"
done
