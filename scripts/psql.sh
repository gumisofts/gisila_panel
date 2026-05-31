#!/usr/bin/env bash
# Open a psql session against the dev database without installing psql locally.
set -euo pipefail
cd "$(dirname "$0")/.."
exec docker compose exec -e PGPASSWORD=postgres pg \
  psql -U postgres -d gisila_panel "$@"
