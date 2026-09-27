#!/usr/bin/env sh
# Tests del motor nuevo (engine/). Uso: sh tests/engine/run.sh [test_nombre]
# Falla también si aparece "SCRIPT ERROR": Godot headless sale 0 aunque un
# test aborte a mitad por un error de ejecución.
set -u
GODOT="${GODOT:-godot}"
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
LOG="$(mktemp)"
if [ "$#" -gt 0 ]; then
  "$GODOT" --headless --path "$ROOT" -s "$ROOT/tests/engine/run_tests.gd" -- --only="$1" >"$LOG" 2>&1
else
  "$GODOT" --headless --path "$ROOT" -s "$ROOT/tests/engine/run_tests.gd" >"$LOG" 2>&1
fi
code=$?
cat "$LOG"
if grep -q "SCRIPT ERROR" "$LOG"; then
  echo "[tests/engine] FAIL: hubo SCRIPT ERROR (algún test abortó a mitad)" >&2
  code=1
fi
rm -f "$LOG"
exit $code
