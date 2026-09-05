#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PORT="${PORT:-8080}"
BIN="$ROOT/.tools/bin/cloudflared"
if [[ ! -x "$BIN" ]]; then
  echo "Install cloudflared to $BIN first." >&2
  exit 1
fi
exec "$BIN" tunnel --url "http://127.0.0.1:${PORT}" --no-autoupdate
