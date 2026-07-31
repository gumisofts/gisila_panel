#!/usr/bin/env bash
# =============================================================================
# Gisila Panel — uninstaller.
#
# Removes everything `infra/install.sh` puts on a host. Because some of it is
# data you may not want to lose, the destructive parts are opt-in:
#
#   sudo bash infra/uninstall.sh                 control plane only (default)
#   sudo bash infra/uninstall.sh --apps          + tear down all deployed apps
#   sudo bash infra/uninstall.sh --purge         + delete panel data (DB, dirs, user)
#   sudo bash infra/uninstall.sh --all           everything (= --apps --purge)
#
# What each stage removes:
#   control plane : gisila-panel/worker/ui systemd units, gisila-apps.target,
#                   /usr/local/bin/gisila-{panel,worker,agent}, the sudoers rule,
#                   and the panel's own nginx vhost.
#   --apps        : every deployed app's systemd units (service + celery
#                   target/worker/beat/flower), AppArmor profiles, nginx vhosts,
#                   supervisor configs, Linux users, and /srv/apps.
#   --purge       : the gisila system user + /srv/gisila, /var/log/gisila,
#                   /var/lib/gisila (DB backups), /etc/gisila, and (best-effort,
#                   local Postgres/Redis only — see note below) the gisila_panel
#                   database + role and the panel's Redis keys.
#
# PostgreSQL and Redis are not installed/managed by infra/install.sh — they are
# external services the panel connects to (see /etc/gisila/database.yaml and
# /etc/gisila/.env). --purge's DB/Redis cleanup below is a same-host
# convenience for local dev/single-node setups (it only works when they are
# actually reachable via `sudo -u postgres`/local `redis-cli`); for a remote or
# externally-managed instance, drop the database/role and flush the `gisila:*`
# keys yourself.
#
# Every step is best-effort and idempotent — safe to re-run.
# =============================================================================
set -uo pipefail
shopt -s nullglob

REMOVE_APPS=false
PURGE=false
for arg in "$@"; do
  case "$arg" in
    --apps)  REMOVE_APPS=true ;;
    --purge) PURGE=true ;;
    --all)   REMOVE_APPS=true; PURGE=true ;;
    -h|--help)
      # Print the top comment block (skip the shebang, stop at first code line).
      awk 'NR==1{next} /^#/{sub(/^# ?/,""); print; next} {exit}' "$0"
      exit 0 ;;
    *) echo "Unknown option: $arg (try --help)" >&2; exit 1 ;;
  esac
done

if [[ $EUID -ne 0 ]]; then
  echo "Please run as root: sudo bash $0" >&2
  exit 1
fi

# ── 1. Control plane: panel services + binaries ───────────────────────────────
echo "==> Stopping and removing panel services"
systemctl stop  gisila-panel.service gisila-worker.service gisila-ui.service 2>/dev/null || true
systemctl disable gisila-panel.service gisila-worker.service gisila-ui.service 2>/dev/null || true
rm -f /etc/systemd/system/gisila-panel.service \
      /etc/systemd/system/gisila-worker.service \
      /etc/systemd/system/gisila-ui.service \
      /etc/systemd/system/gisila-apps.target
systemctl daemon-reload

echo "==> Removing panel binaries and sudoers rule"
rm -f /usr/local/bin/gisila-panel \
      /usr/local/bin/gisila-worker \
      /usr/local/bin/gisila-agent
rm -f /etc/sudoers.d/gisila

echo "==> Removing panel nginx vhost"
rm -f /etc/nginx/sites-enabled/gisila-panel \
      /etc/nginx/sites-available/gisila-panel

# ── 2. Deployed apps (opt-in) ─────────────────────────────────────────────────
if $REMOVE_APPS; then
  echo "==> Tearing down all deployed apps"

  # Per-app systemd units: the simple service plus every Celery unit
  # (gisila-app_<id>.target / -worker-N.service / -beat.service / -flower.service).
  for unit in /etc/systemd/system/gisila-app_*.service \
              /etc/systemd/system/gisila-app_*.target; do
    name=$(basename "$unit")
    systemctl stop    "$name" 2>/dev/null || true
    systemctl disable "$name" 2>/dev/null || true
    rm -f "$unit"
  done
  systemctl daemon-reload

  # AppArmor profiles — unload from the kernel, then delete.
  for prof in /etc/apparmor.d/gisila-app_*; do
    apparmor_parser -R "$prof" 2>/dev/null || true
    rm -f "$prof"
  done

  # Per-app nginx vhosts.
  rm -f /etc/nginx/sites-enabled/gisila-app-*.conf \
        /etc/nginx/sites-available/gisila-app-*.conf

  # Supervisor configs (only present on Docker-mode installs).
  rm -f /etc/supervisor/conf.d/gisila-app_*.conf 2>/dev/null || true
  command -v supervisorctl >/dev/null 2>&1 && supervisorctl update 2>/dev/null || true

  # Per-app Linux users (named app_<shortid>, one work dir each under /srv/apps).
  for d in /srv/apps/app_*; do
    [[ -d "$d" ]] || continue
    u=$(basename "$d")
    if id -u "$u" >/dev/null 2>&1; then
      userdel "$u" 2>/dev/null || true
    fi
  done
  rm -rf /srv/apps

  systemctl reload nginx 2>/dev/null || true
else
  echo "==> Keeping deployed apps (pass --apps to remove them)"
fi

# ── 3. Panel data (opt-in) ────────────────────────────────────────────────────
if $PURGE; then
  echo "==> Purging panel data"

  # PostgreSQL: drop the panel database, then its owning role. Best-effort —
  # only works for a local cluster reachable via the `postgres` OS user; a
  # remote/externally-managed instance must be cleaned up by its operator.
  if command -v psql >/dev/null 2>&1; then
    sudo -u postgres dropdb   --if-exists gisila_panel 2>/dev/null || true
    sudo -u postgres dropuser --if-exists gisila       2>/dev/null || true
  fi

  # Redis: delete only the panel's keys (queues, pub/sub, caches). Best-effort
  # — only reaches a Redis on localhost:6379 with no auth; for a remote or
  # password-protected instance, flush `gisila:*` keys yourself.
  if command -v redis-cli >/dev/null 2>&1; then
    keys=$(redis-cli --scan --pattern 'gisila:*' 2>/dev/null || true)
    if [[ -n "$keys" ]]; then
      echo "$keys" | xargs -r redis-cli del >/dev/null 2>&1 || true
    fi
  fi

  # Config, logs, backups.
  rm -rf /etc/gisila /var/log/gisila /var/lib/gisila

  # The gisila system user and its home (/srv/gisila, which holds the built UI).
  if id -u gisila >/dev/null 2>&1; then
    userdel -r gisila 2>/dev/null || true
  fi
  rm -rf /srv/gisila
else
  echo "==> Keeping panel data: /etc/gisila, /srv/gisila, /var/lib/gisila, the"
  echo "    gisila_panel database and gisila role (pass --purge to remove them)"
fi

systemctl daemon-reload

echo
echo "✓ gisila-panel uninstalled."
if ! $REMOVE_APPS || ! $PURGE; then
  echo "  Re-run with --all to remove deployed apps and panel data too."
fi
echo "  Note: PostgreSQL and Redis are external services the panel connects to"
echo "  (never installed by this project) — for a remote/managed instance,"
echo "  --purge's local-only cleanup won't reach it; drop the database/role and"
echo "  flush 'gisila:*' Redis keys yourself. Shared system packages (nginx,"
echo "  certbot, dart, node) and any Let's Encrypt certificates are also left"
echo "  untouched."
