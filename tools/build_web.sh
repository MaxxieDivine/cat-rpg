#!/usr/bin/env bash
# Builds the web export into build/web, cache-busted by commit SHA.
# Usage: tools/build_web.sh [godot-binary]     (also used by CI)
set -euo pipefail

GODOT="${1:-godot}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="$ROOT/build/web"
BUILD_JSON="$ROOT/data/build.json"
cd "$ROOT"

SHA="$(git rev-parse --short HEAD 2>/dev/null || echo dev)"
if [[ -n "$(git status --porcelain 2>/dev/null)" ]]; then SHA="${SHA}+"; fi
SHA="${BUILD_SHA:-$SHA}"  # override for local tests of the update path
DATE="$(date -u +%Y-%m-%d)"

rm -rf "$OUT"
mkdir -p "$OUT"
trap 'rm -f "$BUILD_JSON"' EXIT
printf '{\n\t"sha": "%s",\n\t"date": "%s"\n}\n' "$SHA" "$DATE" > "$BUILD_JSON"

"$GODOT" --headless --path . --import || true
"$GODOT" --headless --path . --export-release "Web" "$OUT/index.html"

[[ -f "$OUT/index.wasm" ]] || { echo "build_web: index.wasm missing, export failed" >&2; exit 1; }
[[ -f "$OUT/index.pck" ]] || { echo "build_web: index.pck missing, export failed" >&2; exit 1; }

HTML="$OUT/index.html"
V="${SHA//+/-dirty}"

# Each rewrite is checked so a Godot template change fails the build loudly.
expect() { grep -q -- "$1" "$HTML" || { echo "build_web: expected '$1' in index.html ($2)" >&2; exit 1; }; }

expect 'const GODOT_CONFIG = {' "engine config"
sed -i "s|const GODOT_CONFIG = {|const GODOT_CONFIG = {\"mainPack\":\"index.pck?v=${V}\",|" "$HTML"
expect "\"mainPack\":\"index.pck?v=${V}\"" "mainPack cache-bust"

expect '<script src="index.js">' "engine script tag"
sed -i "s|<script src=\"index.js\">|<script src=\"index.js?v=${V}\">|" "$HTML"
expect "index.js?v=${V}" "index.js cache-bust"

expect '<meta name="viewport" content="' "viewport meta"
sed -i 's|<meta name="viewport" content="\([^"]*\)"|<meta name="viewport" content="\1, viewport-fit=cover"|' "$HTML"
expect 'viewport-fit=cover' "viewport-fit"

expect 'name="robots" content="noindex, nofollow"' "robots meta from export preset"
expect 'name="apple-mobile-web-app-capable" content="yes"' "home-screen meta from export preset"
expect '<link rel="manifest" href="index.manifest.json">' "PWA manifest link"
expect '"serviceWorker":"index.service.worker.js"' "service worker in engine config"

# PWA: check the manifest, then swap Godot's cache-first service worker for
# ours (network-first, see tools/web/service_worker.js).
MANIFEST="$OUT/index.manifest.json"
[[ -f "$MANIFEST" ]] || { echo "build_web: index.manifest.json missing (PWA export off?)" >&2; exit 1; }
grep -q '"display":"fullscreen"' "$MANIFEST" || { echo "build_web: manifest display is not fullscreen" >&2; exit 1; }
grep -q '"orientation":"landscape"' "$MANIFEST" || { echo "build_web: manifest orientation is not landscape" >&2; exit 1; }
[[ -f "$OUT/index.service.worker.js" ]] || { echo "build_web: index.service.worker.js missing" >&2; exit 1; }
grep -q 'CACHED_FILES' "$OUT/index.service.worker.js" || { echo "build_web: Godot service worker changed shape; review tools/web/service_worker.js" >&2; exit 1; }
cp "$ROOT/tools/web/service_worker.js" "$OUT/index.service.worker.js"

printf 'User-agent: *\nDisallow: /\n' > "$OUT/robots.txt"
touch "$OUT/.nojekyll"

echo "build_web: built $OUT (build $SHA $DATE)"
