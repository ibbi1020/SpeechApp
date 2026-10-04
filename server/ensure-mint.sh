#!/bin/bash
# Start the conversation mint server for this project.
# Stops any existing mint.mjs for THIS repo only (path match), then listens again.
# Never kills other processes — even if they hold PORT.

set -u

ROOT="$(cd "$(dirname "$0")" && pwd)"
MINT="$ROOT/mint.mjs"
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

# Kill only node processes running this project's mint.mjs:
# - absolute path to $MINT, or
# - any mint.mjs whose cwd is this server directory.
# Never kills other projects or unrelated listeners on PORT.
stop_project_mint() {
  local pid cmd cwd
  while read -r pid cmd; do
    [[ -z "${pid:-}" ]] && continue
    case "$cmd" in
      *"$MINT"*)
        kill "$pid" 2>/dev/null || true
        continue
        ;;
      *mint.mjs*)
        cwd="$(lsof -a -p "$pid" -d cwd -Fn 2>/dev/null | sed -n 's/^n//p' | head -1)"
        if [[ "$cwd" == "$ROOT" ]]; then
          kill "$pid" 2>/dev/null || true
        fi
        ;;
    esac
  done < <(ps -ax -o pid=,command=)
}

stop_project_mint

project_mint_running() {
  local pid cmd cwd
  while read -r pid cmd; do
    case "$cmd" in
      *"$MINT"*) return 0 ;;
      *mint.mjs*)
        cwd="$(lsof -a -p "$pid" -d cwd -Fn 2>/dev/null | sed -n 's/^n//p' | head -1)"
        if [[ "$cwd" == "$ROOT" ]]; then
          return 0
        fi
        ;;
    esac
  done < <(ps -ax -o pid=,command=)
  return 1
}

# Wait for our processes to exit (and release PORT when we owned it).
for _ in $(seq 1 20); do
  project_mint_running || break
  sleep 0.1
done

# If something else still owns the port, leave it alone.
if lsof -nP -iTCP:"$PORT" -sTCP:LISTEN >/dev/null 2>&1; then
  echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) port $PORT still in use after stopping project mint; not starting" >>"$LOG"
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

# Format 2 testing talks to xAI directly; keep the key off git.
/bin/bash "$ROOT/sync-xai-secret.sh" || true

cd "$ROOT"
nohup "$NODE" --env-file="$ENV_FILE" "$MINT" >>"$LOG" 2>&1 &
echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) started mint pid $! on port $PORT" >>"$LOG"
exit 0
