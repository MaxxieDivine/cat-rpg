#!/usr/bin/env bash
# Runs every test. Exits non-zero if any test fails OR any script error is
# printed: GDScript keeps going after a runtime error, so a crashed test
# would otherwise look like a pass.
# Usage: tools/run_tests.sh [godot-binary] [-- runner args, e.g. --shots=dir --only=name]
# Set DISPLAY (or use xvfb-run) to run with a renderer; otherwise headless.
set -uo pipefail

GODOT="godot"
if [[ $# -gt 0 && "$1" != "--" ]]; then GODOT="$1"; shift; fi
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOG="$(mktemp)"
trap 'rm -f "$LOG"' EXIT

HEADLESS=(--headless)
[[ -n "${DISPLAY:-}" ]] && HEADLESS=()

"$GODOT" "${HEADLESS[@]}" --path "$ROOT" --script res://tests/run_tests.gd "$@" 2>&1 | tee "$LOG"
status=${PIPESTATUS[0]}

if grep -qE "SCRIPT ERROR|Parse Error|Failed to load script" "$LOG"; then
	echo "run_tests: script errors above (a test crashed); failing." >&2
	exit 1
fi
exit "$status"
