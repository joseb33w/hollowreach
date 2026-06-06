#!/usr/bin/env bash
# Hollowreach — export the playable web build into out/ (nothreads HTML5, WebGL2).
# Requires Godot 4.6.3 with the web (nothreads) export templates installed, plus the
# art fetched via ./fetch_assets.sh. Override the engine path with GODOT=/path/to/godot.
set -euo pipefail
cd "$(dirname "$0")"

GODOT="${GODOT:-godot}"

if [ ! -f models/kk_Knight.glb ]; then
  echo "Art missing — running ./fetch_assets.sh first..."
  ./fetch_assets.sh
fi

echo "Importing resources..."
"$GODOT" --headless --path . --import

echo "Exporting Web build..."
rm -rf out && mkdir -p out
"$GODOT" --headless --path . --export-release "Web" out/index.html

# The multiplayer bridge is loaded by the export shell via a relative <script src="bridge.js">.
cp web/bridge.js out/bridge.js

echo "Built out/ — serve it over HTTP (e.g. 'python3 -m http.server -d out 8080') and open in a browser."
