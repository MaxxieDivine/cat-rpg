#!/usr/bin/env bash
# Installs the Godot version pinned in .github/workflows/ci.yml into ~/.local/bin.
# Usage: tools/setup_godot.sh [--web]   (--web also installs the no-threads web templates)
# Safe to run every time: does nothing when already installed.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VER="$(grep -E '^\s*GODOT_VERSION:' "$ROOT/.github/workflows/ci.yml" | head -1 | sed -E 's/.*"([^"]+)".*/\1/')"
if [[ -z "$VER" ]]; then echo "GODOT_VERSION not found in ci.yml" >&2; exit 1; fi

BIN_DIR="$HOME/.local/bin"
TPL_DIR="$HOME/.local/share/godot/export_templates/${VER}.stable"
URL_BASE="https://github.com/godotengine/godot/releases/download/${VER}-stable"
mkdir -p "$BIN_DIR"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

if [[ -x "$BIN_DIR/godot" ]] && "$BIN_DIR/godot" --version 2>/dev/null | grep -q "^${VER}\.stable"; then
	echo "Godot ${VER} already installed."
else
	echo "Installing Godot ${VER}..."
	curl -fsSL -o "$TMP/godot.zip" "${URL_BASE}/Godot_v${VER}-stable_linux.x86_64.zip"
	unzip -q "$TMP/godot.zip" -d "$TMP/godot"
	install -m 755 "$TMP/godot/Godot_v${VER}-stable_linux.x86_64" "$BIN_DIR/godot"
	echo "Installed $("$BIN_DIR/godot" --version)"
fi

if [[ "${1:-}" == "--web" ]]; then
	if [[ -f "$TPL_DIR/web_nothreads_release.zip" && -f "$TPL_DIR/web_nothreads_debug.zip" ]]; then
		echo "Web templates already installed."
	else
		echo "Installing web export templates (no-threads only)..."
		curl -fsSL -o "$TMP/tpl.tpz" "${URL_BASE}/Godot_v${VER}-stable_export_templates.tpz"
		mkdir -p "$TPL_DIR"
		unzip -q -j "$TMP/tpl.tpz" \
			templates/web_nothreads_release.zip templates/web_nothreads_debug.zip templates/version.txt \
			-d "$TPL_DIR"
		echo "Templates in $TPL_DIR"
	fi
fi

case ":$PATH:" in *":$BIN_DIR:"*) ;; *) echo "Note: add $BIN_DIR to PATH";; esac
