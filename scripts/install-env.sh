#!/usr/bin/env bash
# =============================================================================
# Helpers for the Ubuntu install-host stack (docker-compose.install.yml).
#
#   ./scripts/install-env.sh up         build + start pg/redis + ubuntu host
#   ./scripts/install-env.sh shell      bash as non-root ubuntu (has sudo)
#   ./scripts/install-env.sh install    sudo infra/install.sh inside the host
#   ./scripts/install-env.sh check      probe host ports from outside the container
#   ./scripts/install-env.sh status     systemd + panel units
#   ./scripts/install-env.sh logs       follow host journal / compose logs
#   ./scripts/install-env.sh down       stop stack (volumes kept)
#   ./scripts/install-env.sh reset      stop + wipe volumes
#
# From the Docker host / Windows browser (after install):
#   Panel API:  http://localhost:8001
#   Nginx:      http://localhost:18080
#   SSH:        ssh -p 12222 ubuntu@localhost   (password: ubuntu)
# =============================================================================
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# Dedicated compose project so this stack never recreates the main
# docker-compose.yml pg/redis/api containers.
COMPOSE=(docker compose -p gisila-install -f "$ROOT/docker-compose.install.yml")
HOST_SERVICE=host

usage() {
  sed -n '2,18p' "$0" | sed 's/^# \?//'
  exit "${1:-0}"
}

cmd="${1:-}"
shift || true

case "$cmd" in
  up|start)
    "${COMPOSE[@]}" up -d --build "$@"
    echo
    echo "Host is up (Ubuntu + systemd + sudo). Next:"
    echo "  ./scripts/install-env.sh install   # required before the panel answers"
    echo "  ./scripts/install-env.sh check"
    echo "  ./scripts/install-env.sh shell"
    echo
    echo "From outside Docker (host / Windows):"
    echo "  Panel (after install):  http://localhost:8001"
    echo "  Nginx (after install):  http://localhost:18080"
    echo "  SSH:                    ssh -p 12222 ubuntu@localhost  (password: ubuntu)"
    echo "  Postgres:               localhost:5456"
    echo "  Redis:                  localhost:6381"
    ;;

  shell|sh)
    "${COMPOSE[@]}" exec -u ubuntu -w /workspace/gisila-panel "$HOST_SERVICE" \
      bash -l "$@"
    ;;

  root)
    "${COMPOSE[@]}" exec -u root -w /workspace/gisila-panel "$HOST_SERVICE" \
      bash -l "$@"
    ;;

  install)
    "${COMPOSE[@]}" exec -u ubuntu -w /workspace/gisila-panel "$HOST_SERVICE" \
      env \
        DATABASE_URL="${DATABASE_URL:-postgresql://postgres:postgres@pg:5432/gisila_panel}" \
        REDIS_URL="${REDIS_URL:-redis://redis:6379}" \
        PANEL_DOMAIN="${PANEL_DOMAIN:-localhost}" \
        BUILD_FRONTEND="${BUILD_FRONTEND:-0}" \
        bash -lc 'sudo --preserve-env=DATABASE_URL,REDIS_URL,PANEL_DOMAIN,BUILD_FRONTEND,ISSUE_TLS bash infra/install.sh'
    echo
    echo "Install finished. Probe from outside Docker:"
    echo "  ./scripts/install-env.sh check"
    echo "  open http://localhost:8001"
    ;;

  check)
    echo "==> Published ports (docker)"
    docker port gisila-install-host 2>/dev/null || true
    echo
    echo "==> Listening inside container"
    "${COMPOSE[@]}" exec -u ubuntu "$HOST_SERVICE" \
      bash -lc 'sudo ss -lntp | grep -E ":80 |:443 |:8000 |:22 " || true'
    echo
    echo "==> HTTP from Docker host (outside container)"
    for url in \
      http://127.0.0.1:8001/ \
      http://127.0.0.1:18080/ \
      ; do
      code=$(curl -s -o /dev/null -w '%{http_code}' --connect-timeout 2 "$url" || true)
      [[ -z "$code" || "$code" == "000" ]] && code="unreachable"
      printf '  %-32s %s\n' "$url" "$code"
    done
    echo
    echo "==> SSH"
    if (echo >/dev/tcp/127.0.0.1/12222) >/dev/null 2>&1; then
      echo "  127.0.0.1:12222 open — try: ssh -p 12222 ubuntu@localhost  (password: ubuntu)"
    else
      echo "  127.0.0.1:12222 closed"
    fi
    echo
    echo "If panel URLs are unreachable, run: ./scripts/install-env.sh install"
    ;;

  status)
    "${COMPOSE[@]}" exec -u ubuntu "$HOST_SERVICE" \
      bash -lc 'id; sudo -n true && echo "sudo: ok (passwordless)"; echo -n "PID1="; tr "\0" " " </proc/1/cmdline; echo; sudo systemctl is-system-running || true; sudo systemctl is-active ssh nginx gisila-panel gisila-worker 2>/dev/null || true; sudo systemctl status gisila-panel gisila-worker --no-pager || true'
    ;;

  logs)
    if [[ "${1:-}" == "journal" ]]; then
      shift || true
      "${COMPOSE[@]}" exec -u ubuntu "$HOST_SERVICE" \
        sudo journalctl -f "$@"
    else
      "${COMPOSE[@]}" logs -f "$@"
    fi
    ;;

  down|stop)
    "${COMPOSE[@]}" down "$@"
    ;;

  reset)
    "${COMPOSE[@]}" down -v "$@"
    ;;

  ""|-h|--help|help)
    usage 0
    ;;

  *)
    echo "Unknown command: $cmd" >&2
    usage 1
    ;;
esac
