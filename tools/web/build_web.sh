#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
GODOT_BIN="${GODOT:-godot}"
python3 "$ROOT/tools/web/fetch_templates.py"
python3 "$ROOT/tools/web/apply_import_presets.py"
mkdir -p "$ROOT/build/web"
flock /tmp/cogwild-godot.lock timeout 900 "$GODOT_BIN" --headless --path "$ROOT/game" --import
EXPORT_LOG="$ROOT/build/web/export.log"
if ! flock /tmp/cogwild-godot.lock timeout 900 "$GODOT_BIN" --headless --path "$ROOT/game" --export-release Web "$ROOT/build/web/index.html" >"$EXPORT_LOG" 2>&1; then
	cat "$EXPORT_LOG"
	echo "Web export failed; complete log: $EXPORT_LOG" >&2
	exit 1
fi
rm "$EXPORT_LOG"
echo "Web build ready: $ROOT/build/web/index.html"
echo "Serve with: python3 -m http.server -d build/web 8060 --bind 127.0.0.1"
