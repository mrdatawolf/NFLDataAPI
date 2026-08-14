#!/usr/bin/env bash
# Prelaunch check + launcher for NFLDataAPI (macOS/Linux).
# Verifies the machine can run the app, auto-fixes what it safely can,
# builds, starts it, and opens the browser once it's healthy.
set -uo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")"

MIN_NODE_MAJOR=18

fail() {
  echo "ERROR: $1" >&2
  exit 1
}

echo "== NFLDataAPI prelaunch check =="

if ! command -v node >/dev/null 2>&1; then
  fail "Node.js is not installed or not on PATH. Install Node.js ${MIN_NODE_MAJOR}+ from https://nodejs.org/ and re-run this script."
fi

NODE_MAJOR=$(node -p "process.versions.node.split('.')[0]")
if [ "$NODE_MAJOR" -lt "$MIN_NODE_MAJOR" ]; then
  fail "Node.js ${MIN_NODE_MAJOR}+ is required, found $(node -v). Install a newer Node.js from https://nodejs.org/ and re-run this script."
fi
echo "Node $(node -v) OK"

if ! command -v npm >/dev/null 2>&1; then
  fail "npm was not found even though Node.js is installed. Reinstall Node.js from https://nodejs.org/."
fi

if [ ! -f .env ]; then
  if [ -f .env.example ]; then
    echo "No .env found - creating one from .env.example"
    cp .env.example .env
  else
    echo "WARNING: no .env or .env.example found; the app will use its built-in defaults."
  fi
fi

NEED_INSTALL=0
if [ ! -d node_modules ]; then
  NEED_INSTALL=1
elif [ ! -f node_modules/.package-lock.json ]; then
  NEED_INSTALL=1
elif [ -f package-lock.json ] && [ package-lock.json -nt node_modules/.package-lock.json ]; then
  NEED_INSTALL=1
elif [ ! -x node_modules/.bin/tsc ] || [ ! -x node_modules/.bin/vite ]; then
  # node_modules exists but is missing binaries the build needs - e.g. copied
  # in from another machine/OS instead of being installed here.
  NEED_INSTALL=1
fi

if [ "$NEED_INSTALL" -eq 1 ]; then
  echo "Installing dependencies (npm install)..."
  npm install || fail "npm install failed. See the output above for details."
else
  echo "Dependencies already installed"
fi

echo "Building..."
npm run build || fail "Build failed. See the output above for details."

PORT_VALUE=3002
if [ -f .env ]; then
  ENV_PORT=$(grep -E '^APIPORT=' .env | tail -1 | cut -d= -f2- | tr -d '[:space:]')
  [ -n "$ENV_PORT" ] && PORT_VALUE="$ENV_PORT"
fi

if command -v lsof >/dev/null 2>&1 && lsof -ti:"$PORT_VALUE" -sTCP:LISTEN >/dev/null 2>&1; then
  echo "WARNING: port $PORT_VALUE already appears to be in use. The server may fail to start."
fi

echo "== Starting NFLDataAPI on port $PORT_VALUE =="

npm start &
SERVER_PID=$!

cleanup() {
  # npm doesn't forward signals to the process it spawns, so killing
  # $SERVER_PID alone leaves the real "node dist/index.js" orphaned and
  # still bound to the port - kill whatever's actually listening instead.
  if command -v lsof >/dev/null 2>&1; then
    lsof -ti:"$PORT_VALUE" -sTCP:LISTEN 2>/dev/null | xargs -r kill 2>/dev/null || true
  elif command -v fuser >/dev/null 2>&1; then
    fuser -k "${PORT_VALUE}/tcp" >/dev/null 2>&1 || true
  fi
  kill "$SERVER_PID" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

URL="http://localhost:$PORT_VALUE"
if command -v curl >/dev/null 2>&1; then
  HEALTHY=0
  for _ in $(seq 1 60); do
    if curl -sf "$URL/health" >/dev/null 2>&1; then
      HEALTHY=1
      echo "Server is up at $URL"
      if command -v open >/dev/null 2>&1; then
        open "$URL" >/dev/null 2>&1 || true
      elif command -v xdg-open >/dev/null 2>&1; then
        xdg-open "$URL" >/dev/null 2>&1 || true
      fi
      break
    fi
    sleep 1
  done
  if [ "$HEALTHY" -eq 0 ]; then
    echo "WARNING: server did not report healthy within 60s. Check above for errors."
  fi
fi

wait "$SERVER_PID"
