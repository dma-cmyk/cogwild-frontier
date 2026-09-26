#!/usr/bin/env bash
# Launch Cogwild Frontier (imports assets on the first run).
set -euo pipefail
cd "$(dirname "$0")/game"
if [ ! -d .godot ]; then
	godot --headless --path . --import >/dev/null 2>&1 || true
fi
exec godot --path . "$@"
