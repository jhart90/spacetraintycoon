#!/usr/bin/env bash
# Phase 6 — export the Godot build (PLAN §4 Phase 6, "platform export").
# Requires the matching export templates (one-time, ~1 GB): in the Godot editor,
# Editor → Manage Export Templates → Download and Install (version 4.6.3.stable),
# OR `godot --headless --install-export-templates`. Without them you'll see
# "No export template found" — the preset itself is correct and ready.
#
# Usage: bash export.sh [windows|web]
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
GODOT="${GODOT:-/c/Users/jackh/Downloads/Godot463/Godot_v4.6.3-stable_win64_console.exe}"
PROJ="$HERE/../space-train-tycoon"
TARGET="${1:-windows}"

case "$TARGET" in
	windows)
		OUT="$HERE/../build/windows/SpaceTrainTycoon.exe"
		PRESET="Windows Desktop" ;;
	web)
		OUT="$HERE/../build/web/index.html"
		PRESET="Web" ;;
	*)
		echo "usage: export.sh [windows|web]"; exit 2 ;;
esac

mkdir -p "$(dirname "$OUT")"
echo "Exporting preset '$PRESET' → $OUT"
"$GODOT" --headless --path "$PROJ" --export-release "$PRESET" "$OUT"
echo "exit $?  (a 'No export template found' error means templates aren't installed yet — see header)"
