#!/usr/bin/env bash
# Phase-1 galaxy parity harness (PLAN §9): runs BOTH sides and prints verdicts.
#   - Godot side: generates via the ported Galaxy.gd and asserts generateGalaxy
#     invariants (Main.gd --check-galaxy).
#   - JS side: runs the REAL generateGalaxy() from index.html headlessly in Node
#     over N runs and asserts the same invariants.
# The JS RNG is unseeded, so this is INVARIANT/rule parity (not bit-exact coords):
# the Godot output must fall within the JS distribution and satisfy every rule.
#
# Usage: bash run_parity.sh [js_runs]
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
GODOT="${GODOT:-/c/Users/jackh/Downloads/Godot463/Godot_v4.6.3-stable_win64_console.exe}"
PROJ="$HERE/../../space-train-tycoon"
JS_RUNS="${1:-12}"

echo "========== GODOT SIDE (ported Galaxy.gd) =========="
"$GODOT" --headless --path "$PROJ" -- --check-galaxy 2>&1 \
  | grep -E "stars=|relics placed|residual|CHECK (PASS|FAIL)"
g=${PIPESTATUS[0]}

echo
echo "========== JS SIDE (real index.html generateGalaxy) =========="
node "$HERE/js_galaxy_dump.js" "$JS_RUNS"
j=$?

echo
if [ "$g" -eq 0 ] && [ "$j" -eq 0 ]; then
  echo "########## PARITY: PASS (both sides satisfy all invariants) ##########"
  exit 0
else
  echo "########## PARITY: FAIL (godot=$g js=$j) ##########"
  exit 1
fi
