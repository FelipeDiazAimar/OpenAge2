#!/usr/bin/env sh
# Tests del motor nuevo (engine/). Uso: sh tests/engine/run.sh [test_nombre]
set -u
GODOT="${GODOT:-godot}"
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
if [ "$#" -gt 0 ]; then
  "$GODOT" --headless --path "$ROOT" -s "$ROOT/tests/engine/run_tests.gd" -- --only="$1"
else
  "$GODOT" --headless --path "$ROOT" -s "$ROOT/tests/engine/run_tests.gd"
fi
