#!/usr/bin/env bash
# One-command dev environment for gisila-panel.
#
# Brings up Postgres, Redis, the Dart API + worker, and the Vite frontend
# builder in containers — no Dart, Node, or pnpm needed on the host.
#
# The panel UI is built by the `frontend-build` service (Vite) into
# backend/web/ and served directly by the Dart API on http://localhost:8000.
#
# Usage:
#   scripts/dev.sh             # foreground (Ctrl-C to stop)
#   scripts/dev.sh up -d       # detach
#   scripts/dev.sh logs -f api # tail one service
#   scripts/dev.sh down        # stop, keep volumes
#   scripts/dev.sh reset       # stop + wipe ALL volumes (re-init Postgres)
set -euo pipefail

cd "$(dirname "$0")/.."

# Pre-create every directory the docker-compose file mounts a *named volume*
# into. If we don't, the docker daemon creates them on first `up` as root,
# inside the bind-mounted workspace — which then breaks any host-side
# `dart pub get` / `pnpm install` with EACCES on .dart_tool/node_modules.
ensure_mount_targets() {
  local dirs=(
    backend/.dart_tool
    agent/.dart_tool
    frontend/node_modules
    ../gisila/.dart_tool
    ../gisila_orm/.dart_tool
    ../gisila_doc/.dart_tool
    ../gisila_studio/.dart_tool
  )
  for d in "${dirs[@]}"; do
    mkdir -p "$d"
  done
}

# If any of those dirs ended up root-owned from a previous run, fix them
# without needing host `sudo` — a one-shot root container can chown them.
fix_root_owned_targets() {
  local host_uid host_gid
  host_uid=$(id -u)
  host_gid=$(id -g)
  local bad=()
  for d in backend/.dart_tool agent/.dart_tool frontend/node_modules \
           ../gisila/.dart_tool ../gisila_orm/.dart_tool \
           ../gisila_doc/.dart_tool ../gisila_studio/.dart_tool; do
    [ -e "$d" ] || continue
    if [ ! -O "$d" ]; then
      bad+=("$d")
    fi
  done
  if [ ${#bad[@]} -gt 0 ]; then
    echo "==> fixing ownership on ${#bad[@]} root-owned dir(s) via alpine"
    docker run --rm -v "$(cd .. && pwd):/work" alpine \
      sh -c "cd /work/gisila-panel && chown -R ${host_uid}:${host_gid} ${bad[*]}"
  fi
}

ensure_mount_targets
fix_root_owned_targets

case "${1:-}" in
  ""|up)
    shift || true
    exec docker compose up "$@"
    ;;
  reset)
    docker compose down -v
    exec docker compose up
    ;;
  *)
    exec docker compose "$@"
    ;;
esac
