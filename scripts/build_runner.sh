#!/usr/bin/env bash
# Re-run code generation (build_runner) inside the dev container after editing
# `schema.gisila.yaml`, a controller, or any other annotated source.
set -euo pipefail
cd "$(dirname "$0")/.."

docker compose run --rm migrate \
  /bin/sh -c '
    set -e
    dart pub get
    dart run build_runner build --delete-conflicting-outputs
  '
