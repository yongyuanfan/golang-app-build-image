#!/bin/sh
# Container entrypoint. Forwards signals (via exec) to the Go binary
# and transparently passes through all arguments.

set -eu

: "${APP_BIN:=/app/main}"

if [ ! -x "$APP_BIN" ]; then
    echo "entrypoint: APP_BIN '$APP_BIN' not found or not executable" >&2
    exit 127
fi

if [ ! -f ".env" ] && [ -f ".env.example" ]; then
    cp .env.example .env
fi

exec "$APP_BIN" "$@"