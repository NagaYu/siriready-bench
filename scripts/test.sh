#!/usr/bin/env bash
# Run every offline test suite: XCTest (swift test) and pytest.
#
# Environment assumptions (see README "環境メモ"):
# - XCTest ships with Xcode, not with the Command Line Tools, so DEVELOPER_DIR points at Xcode.
# - dataset/generate.py and validate.py target Python 3.12; the tests call them through python3.12
#   when it exists. pytest itself runs on PYTEST_PYTHON (default python3; on the author's machine
#   pytest is only installed for Python 3.13, and nothing is pip-installed by these scripts).
# - The real simulator smoke test is opt-in: SIRIREADY_REAL=1 scripts/test.sh
set -euo pipefail
cd "$(dirname "$0")/.."

if [[ -z "${DEVELOPER_DIR:-}" && -d /Applications/Xcode.app/Contents/Developer ]]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi
swift test

# pytest files live in pytests/ (a name that cannot collide with SwiftPM's Tests/ on
# case-insensitive volumes). pytest is run from inside pytests/ because pytest 9 fails to collect
# when invoked from a parent directory whose name ends with a space (this checkout's does).
PYTEST_PYTHON="${PYTEST_PYTHON:-python3}"
(cd pytests && "$PYTEST_PYTHON" -m pytest -q -p no:cacheprovider)
