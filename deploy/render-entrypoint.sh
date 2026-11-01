#!/usr/bin/env bash
set -euo pipefail

PUBLIC_PORT="${PORT:-10000}"
GAME_PORT="7000"

test -f /app/build/web/index.html || { echo "ERROR: build/web/index.html missing"; exit 1; }

if [ -f /app/web/network-config.js ]; then
  cp /app/web/network-config.js /app/build/web/network-config.js
fi

sed "s/__PORT__/${PUBLIC_PORT}/g" /app/deploy/nginx.conf.template > /tmp/nginx.conf

echo "Starting Godot server on 0.0.0.0:${GAME_PORT}"
godot --headless --path /app server/DedicatedServer.tscn -- --port="${GAME_PORT}" &
GODOT_PID=$!

cleanup() { kill "${GODOT_PID}" 2>/dev/null || true; }
trap cleanup EXIT INT TERM

sleep 1
kill -0 "${GODOT_PID}" 2>/dev/null || { echo "ERROR: Godot server exited"; wait "${GODOT_PID}"; exit 1; }

echo "Starting public web server on 0.0.0.0:${PUBLIC_PORT}"
exec nginx -c /tmp/nginx.conf -g "daemon off;"
