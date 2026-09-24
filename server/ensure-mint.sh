#!/bin/bash
# Start the conversation mint server when it is not already listening.
# Used by the Xcode run scheme and the login service. Exits immediately if port is taken.

set -u

ROOT="$(cd "$(dirname "$0")" && pwd)"
ENV_FILE="$ROOT/.env"
LOG="${HOME}/Library/Logs/speechapp-mint.log"
PORT=8787

mkdir -p "$(dirname "$LOG")"

if [[ -f "$ENV_FILE" ]]; then
  parsed="$(grep -E '^PORT=' "$ENV_FILE" | tail -1 | cut -d= -f2- | tr -d '"' | tr -d "'")"
  if [[ -n "${parsed:-}" ]]; then
    PORT="$parsed"
  fi
fi

if lsof -nP -iTCP:"$PORT" -sTCP:LISTEN >/dev/null 2>&1; then
  exit 0
fi

find_node() {
  local candidate nvm
  for candidate in /opt/homebrew/bin/node /usr/local/bin/node; do
    if [[ -x "$candidate" ]]; then
      echo "$candidate"
      return
    fi
  done
  nvm="$(ls -d "$HOME"/.nvm/versions/node/*/bin/node 2>/dev/null | tail -1 || true)"
  if [[ -n "$nvm" && -x "$nvm" ]]; then
    echo "$nvm"
  fi
}

NODE="$(find_node || true)"
if [[ -z "$NODE" ]]; then
  echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) node not found; conversation mint not started" >>"$LOG"
  exit 0
fi

if [[ ! -f "$ENV_FILE" ]]; then
  echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) missing server/.env" >>"$LOG"
  exit 0
fi

cd "$ROOT"
nohup "$NODE" --env-file="$ENV_FILE" "$ROOT/mint.mjs" >>"$LOG" 2>&1 &
echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) started mint pid $! on port $PORT" >>"$LOG"
exit 0
