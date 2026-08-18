#!/usr/bin/env bash
# Validate the relay compose file without a live VPS.
set -euo pipefail
RELAY_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$RELAY_ROOT"

echo "== render templates from .env.example =="
python3 "$RELAY_ROOT/scripts/render_config.py" --env "$RELAY_ROOT/.env.example" --out "$RELAY_ROOT/generated"

echo "== docker compose --env-file .env.example config =="
docker compose --env-file "$RELAY_ROOT/.env.example" config

echo "== unit checks =="
python3 "$RELAY_ROOT/tests/test_relay_config.py"
