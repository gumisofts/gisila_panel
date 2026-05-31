#!/usr/bin/env bash
# Open redis-cli against the dev redis without installing it locally.
set -euo pipefail
cd "$(dirname "$0")/.."
exec docker compose exec redis redis-cli "$@"
