#!/usr/bin/env bash
# Run gisila_orm migrations inside the dev container.
#
#   scripts/migrate.sh up      # apply pending
#   scripts/migrate.sh down    # rollback the last batch
#   scripts/migrate.sh status  # show migration table
set -euo pipefail
cd "$(dirname "$0")/.."

ACTION="${1:-status}"
shift || true

docker compose run --rm migrate \
  /bin/sh -c "
    set -e
    dart pub get
    dart run gisila_orm:migrate $ACTION \
      --dir /workspace/gisila-panel/backend/lib/migrations \
      --config /workspace/gisila-panel/backend/docker/database.yaml $*
  "
