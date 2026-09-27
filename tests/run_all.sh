#!/usr/bin/env sh
# tests/run_all.sh - Bateria headless OpenAge-LAN: Lan8Bots + BalanceTester.
#
# Uso:
#   sh tests/run_all.sh [ticks]      # ticks por defecto: 3600 (6 min a 10 Hz)
#   GODOT=/ruta/a/godot sh tests/run_all.sh 600
#
# Requiere el binario `godot` (4.4) en el PATH o en $GODOT. En Windows con
# Git Bash suele ser: GODOT="/c/Program Files/Godot/godot.exe".
# Salida: 0 si TODO pasa, 1 si algo falla, 2 si falta el entorno.
set -u

GODOT="${GODOT:-godot}"
TICKS="${1:-3600}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

if ! command -v "$GODOT" >/dev/null 2>&1; then
  echo "[run_all] ERROR: no se encuentra '$GODOT'. Instala Godot 4.4 o exporta GODOT=/ruta/a/godot(.exe)." >&2
  exit 2
fi

code_lan=0
code_bal=0

code_eng=0
echo "[run_all] 0/2 Motor nuevo (tests/engine)..."
"$GODOT" --headless --path "$ROOT" -s "$ROOT/tests/engine/run_tests.gd" || code_eng=$?

echo "[run_all] 1/2 Lan8Bots (ticks=$TICKS)..."
"$GODOT" --headless --path "$ROOT" -s "$ROOT/tests/Lan8Bots.gd" -- --ticks="$TICKS" || code_lan=$?

echo "[run_all] 2/2 BalanceTester..."
"$GODOT" --headless --path "$ROOT" -s "$ROOT/tests/BalanceTester.gd" || code_bal=$?

echo "----------------------------------------"
if [ "$code_eng" -eq 0 ]; then echo "[run_all] Motor nuevo:   PASS"; else echo "[run_all] Motor nuevo:   FAIL ($code_eng)"; fi
if [ "$code_lan" -eq 0 ]; then echo "[run_all] Lan8Bots:      PASS"; else echo "[run_all] Lan8Bots:      FAIL ($code_lan)"; fi
if [ "$code_bal" -eq 0 ]; then echo "[run_all] BalanceTester: PASS"; else echo "[run_all] BalanceTester: FAIL ($code_bal)"; fi

if [ "$code_eng" -ne 0 ] || [ "$code_lan" -ne 0 ] || [ "$code_bal" -ne 0 ]; then
  echo "[run_all] RESULTADO: FAIL"
  exit 1
fi
echo "[run_all] RESULTADO: PASS"
exit 0
