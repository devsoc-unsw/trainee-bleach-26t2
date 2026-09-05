#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/client/build/index.html"
GODOT_LINUX="$ROOT/.tools/bin/godot"
GODOT_WIN="/mnt/c/Users/louis/Downloads/Godot_v4.7.1-stable_win64.exe/Godot_v4.7.1-stable_win64_console.exe"

mkdir -p "$ROOT/client/build"

if [[ -x "$GODOT_LINUX" ]]; then
  "$GODOT_LINUX" --headless --path "$ROOT/client" --export-release Web "$OUT"
elif [[ -f "$GODOT_WIN" ]]; then
  WIN_OUT="$(wslpath -w "$OUT")"
  WIN_PROJECT="$(wslpath -w "$ROOT/client")"
  "$GODOT_WIN" --headless --path "$WIN_PROJECT" --export-release Web "$WIN_OUT"
elif command -v godot >/dev/null 2>&1; then
  godot --headless --path "$ROOT/client" --export-release Web "$OUT"
else
  echo "Godot 4.7.1 not found. Export Web to client/build/index.html first." >&2
  exit 1
fi

test -f "$OUT"
# Reject the tiny placeholder page
if [[ $(wc -c < "$OUT") -lt 2000 ]]; then
  echo "Export looks like a placeholder ($OUT)." >&2
  exit 1
fi
echo "Web export ready: $OUT"
