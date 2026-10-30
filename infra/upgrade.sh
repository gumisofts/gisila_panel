#!/usr/bin/env bash
# =============================================================================
# Gisila Panel — upgrade an existing install to a prebuilt release.
#
# Touches as little as possible. It replaces only the panel's own files:
#   /usr/local/bin/gisila-{panel,worker,migrate,agent}, the panel UI in
#   /srv/gisila/web, the migrations in /usr/local/share/gisila/migrations,
#   and the gisila-* systemd units when the release changed them,
# then runs the new migrations and restarts gisila-panel and gisila-worker.
# Hosted apps keep running throughout (they are their own systemd units).
#
# It does NOT touch: apt packages, nginx or TLS certificates, /etc/gisila/.env,
# /etc/gisila/database.yaml, /etc/gisila/secret.key, users, Postgres or Redis
# settings, or the firewall.
#
# Before changing anything it backs up those files and the database to
# /var/backups/gisila/<time>-<old version>/. If the migrations fail or the new
# version doesn't come up, it puts the old files back and restarts them.
#
# Run as root:
#   curl -fsSL https://raw.githubusercontent.com/gumisofts/gisila_panel/main/infra/upgrade.sh | sudo bash
#   curl -fsSL …/infra/upgrade.sh | sudo env VERSION=0.1.0 bash
#   sudo bash infra/upgrade.sh                       # from a clone
#
# Env knobs:
#   VERSION=x.y.z      release to install (default: latest)
#   RELEASE_FILE=…     install a local release tarball instead of downloading
#   FORCE=1            reinstall even when already on that version
#   SKIP_DB_BACKUP=1   skip the pg_dump (when you have your own backup, or the
#                      local pg_dump is older than the server)
#   ROLLBACK=1         put back the files from the latest backup (or BACKUP=…)
#                      and restart. The database is not restored, see below.
#   GITHUB_REPO, RELEASE_URL
# =============================================================================
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
  echo "Please run as root: sudo bash $0" >&2
  exit 1
fi

GISILA_USER="gisila"
GISILA_HOME="/srv/gisila"
MIGRATIONS_DIR="/usr/local/share/gisila/migrations"
BACKUP_ROOT="/var/backups/gisila"
GITHUB_REPO="${GITHUB_REPO:-gumisofts/gisila_panel}"
VERSION="${VERSION:-latest}"
BINARIES=(gisila-panel gisila-worker gisila-migrate gisila-agent)
UNITS=(gisila-panel.service gisila-worker.service gisila-apps.target)
SERVICES=(gisila-panel.service gisila-worker.service)

for f in /etc/gisila/.env /etc/gisila/database.yaml /usr/local/bin/gisila-panel; do
  if [[ ! -e "$f" ]]; then
    echo "ERROR: $f is missing: this host has no Gisila Panel install to upgrade." >&2
    echo "       Install it with infra/install-prebuilt.sh instead." >&2
    exit 1
  fi
done

# ── Backups ───────────────────────────────────────────────────────────────────

# Copy the panel's current files into backup dir $1.
save_files() {
  local dir="$1"
  install -d -m 0700 "$dir/bin" "$dir/units" "$dir/etc"
  for b in "${BINARIES[@]}"; do
    [[ -e "/usr/local/bin/$b" ]] && cp -p "/usr/local/bin/$b" "$dir/bin/"
  done
  for u in "${UNITS[@]}"; do
    [[ -e "/etc/systemd/system/$u" ]] && cp -p "/etc/systemd/system/$u" "$dir/units/"
  done
  [[ -d "$GISILA_HOME/web" ]] && rsync -a "$GISILA_HOME/web/" "$dir/web/"
  [[ -d "$MIGRATIONS_DIR" ]] && rsync -a "$MIGRATIONS_DIR/" "$dir/migrations/"
  for f in .env database.yaml secret.key; do
    [[ -e "/etc/gisila/$f" ]] && cp -p "/etc/gisila/$f" "$dir/etc/"
  done
  return 0
}

# Put the files from backup dir $1 back. Config in /etc/gisila is never
# changed by an upgrade, so it is not restored.
restore_files() {
  local dir="$1"
  for b in "${BINARIES[@]}"; do
    [[ -e "$dir/bin/$b" ]] && install -m 0755 "$dir/bin/$b" "/usr/local/bin/$b"
  done
  for u in "${UNITS[@]}"; do
    [[ -e "$dir/units/$u" ]] && install -m 0644 "$dir/units/$u" "/etc/systemd/system/$u"
  done
  systemctl daemon-reload
  if [[ -d "$dir/web" ]]; then
    rsync -a --delete "$dir/web/" "$GISILA_HOME/web/"
    chown -R "$GISILA_USER:$GISILA_USER" "$GISILA_HOME/web"
  fi
  [[ -d "$dir/migrations" ]] && rsync -a --delete "$dir/migrations/" "$MIGRATIONS_DIR/"
  return 0
}

# A value from /etc/gisila/database.yaml (the file the installer writes).
db_setting() {
  sed -nE "s/^[[:space:]]+$1:[[:space:]]*(.*)$/\1/p" /etc/gisila/database.yaml | head -1
}

backup_database() {
  local out="$1/database.dump"
  local host port name user password ssl
  host="$(db_setting host)"; port="$(db_setting port)"; name="$(db_setting database)"
  user="$(db_setting username)"; password="$(db_setting password)"; ssl="$(db_setting ssl)"
  echo "==> Backing up database $name on $host:$port"
  if ! PGPASSWORD="$password" PGSSLMODE="$([[ "$ssl" == "true" ]] && echo require || echo prefer)" \
      pg_dump -Fc -h "$host" -p "$port" -U "$user" -d "$name" -f "$out" 2>"$1/pg_dump.log"; then
    echo "ERROR: pg_dump failed, nothing was changed:" >&2
    sed 's/^/       /' "$1/pg_dump.log" >&2
    echo "       Back up the database yourself, then re-run with SKIP_DB_BACKUP=1." >&2
    exit 1
  fi
  chmod 0600 "$out"
  echo "    saved $out ($(du -h "$out" | cut -f1))"
}

# Both services active and the API answering (401 from /auth/me is fine).
healthy() {
  local port code
  port="$(sed -nE 's/^PORT=([0-9]+).*/\1/p' /etc/gisila/.env | head -1)"
  for _ in $(seq 1 30); do
    if systemctl is-active --quiet gisila-panel.service &&
       systemctl is-active --quiet gisila-worker.service; then
      code="$(curl -s -o /dev/null -w '%{http_code}' "http://127.0.0.1:${port:-8000}/auth/me" || true)"
      if [[ "$code" =~ ^[234][0-9][0-9]$ ]]; then return 0; fi
    fi
    sleep 1
  done
  return 1
}

installed_version() {
  /usr/local/bin/gisila-agent version 2>/dev/null |
    sed -nE 's/.*"version":"([^"]*)".*/\1/p' | head -1
}

# ── Rollback mode ─────────────────────────────────────────────────────────────

if [[ "${ROLLBACK:-0}" == "1" ]]; then
  BACKUP="${BACKUP:-$(ls -1d "$BACKUP_ROOT"/*/ 2>/dev/null | sort | tail -1)}"
  BACKUP="${BACKUP%/}"
  [[ -n "$BACKUP" && -d "$BACKUP/bin" ]] || { echo "ERROR: no backup found in $BACKUP_ROOT" >&2; exit 1; }
  echo "==> Rolling back to the files in $BACKUP"
  systemctl stop "${SERVICES[@]}"
  restore_files "$BACKUP"
  systemctl start "${SERVICES[@]}"
  if healthy; then echo "✓ Rolled back to $(installed_version)."; else
    echo "WARNING: the panel is not answering. See: journalctl -u gisila-panel -u gisila-worker -n 100" >&2
  fi
  echo
  echo "  The database was not restored: the old version runs on the newer schema,"
  echo "  which works because migrations only add. To restore it as well:"
  echo "    pg_restore --clean --if-exists -d <database> $BACKUP/database.dump"
  exit 0
fi

# ── Fetch the release ─────────────────────────────────────────────────────────

_GISILA_ENV_HELPER="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd)/install-env.sh"
if [[ -f "${_GISILA_ENV_HELPER:-}" ]]; then
  # shellcheck source=install-env.sh
  source "$_GISILA_ENV_HELPER"
else
  # shellcheck disable=SC1090
  source <(curl -fsSL "https://raw.githubusercontent.com/${GITHUB_REPO}/main/infra/install-env.sh")
fi

ARCH="$(uname -m)"
case "$ARCH" in
  x86_64 | amd64) ARCH=x64 ;;
  aarch64 | arm64) ARCH=arm64 ;;
esac
ASSET="gisila-release-linux-${ARCH}.tar.gz"

OLD_VERSION="$(installed_version)"
OLD_VERSION="${OLD_VERSION:-unknown}"
echo "==> Installed version: $OLD_VERSION"

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
gisila_fetch_release "$STAGE"
NEW_VERSION="$(cat "$SRC/VERSION" 2>/dev/null || echo unknown)"

if [[ "$NEW_VERSION" == "$OLD_VERSION" && "${FORCE:-0}" != "1" ]]; then
  echo "✓ Already on $OLD_VERSION. Nothing to do (FORCE=1 reinstalls it)."
  exit 0
fi

# ── Back up, then swap the files ──────────────────────────────────────────────

BACKUP="$BACKUP_ROOT/$(date -u +%Y%m%dT%H%M%SZ)-$OLD_VERSION"
echo "==> Backing up the current install to $BACKUP"
install -d -m 0700 "$BACKUP_ROOT" "$BACKUP"
save_files "$BACKUP"
if [[ "${SKIP_DB_BACKUP:-0}" != "1" ]]; then
  backup_database "$BACKUP"
else
  echo "    skipping the database backup (SKIP_DB_BACKUP=1)"
fi
# Keep the three newest backups.
ls -1d "$BACKUP_ROOT"/*/ 2>/dev/null | sort | head -n -3 | xargs -r rm -rf

fail() {
  echo >&2
  echo "ERROR: $1" >&2
  echo "==> Putting $OLD_VERSION back" >&2
  systemctl stop "${SERVICES[@]}" || true
  restore_files "$BACKUP"
  systemctl start "${SERVICES[@]}" || true
  if healthy; then
    echo "    $OLD_VERSION is running again." >&2
  else
    echo "WARNING: $OLD_VERSION is not answering either." >&2
  fi
  echo "    Logs: journalctl -u gisila-panel -u gisila-worker -n 100" >&2
  echo "    Database backup: $BACKUP/database.dump" >&2
  exit 1
}

echo "==> Stopping gisila-panel and gisila-worker (hosted apps keep running)"
systemctl stop "${SERVICES[@]}"

echo "==> Installing $NEW_VERSION"
for b in "${BINARIES[@]}"; do
  install -m 0755 "$SRC/bin/$b" "/usr/local/bin/$b"
done
rsync -a --delete "$SRC/web/" "$GISILA_HOME/web/"
chown -R "$GISILA_USER:$GISILA_USER" "$GISILA_HOME/web"
rsync -a --delete "$SRC/migrations/" "$MIGRATIONS_DIR/"

# Directories newer versions use, created only when missing.
for d in /var/lib/gisila/backups /var/lib/gisila/backups/uploads /var/lib/gisila/artifacts; do
  [[ -d "$d" ]] || install -d -o "$GISILA_USER" -g "$GISILA_USER" -m 0750 "$d"
done

UNITS_CHANGED=0
for u in "${UNITS[@]}"; do
  if [[ -f "$SRC/infra/$u" ]] && ! cmp -s "$SRC/infra/$u" "/etc/systemd/system/$u"; then
    install -m 0644 "$SRC/infra/$u" "/etc/systemd/system/$u"
    echo "    updated /etc/systemd/system/$u"
    UNITS_CHANGED=1
  fi
done
[[ "$UNITS_CHANGED" == "1" ]] && systemctl daemon-reload

echo "==> Running migrations"
GISILA_DATABASE_FILE=/etc/gisila/database.yaml \
  gisila-migrate up --dir "$MIGRATIONS_DIR" --config /etc/gisila/database.yaml ||
  fail "the migrations failed."

echo "==> Starting gisila-panel and gisila-worker"
systemctl start "${SERVICES[@]}"
healthy || fail "$NEW_VERSION did not come up within 30 seconds."

echo
echo "✓ Upgraded Gisila Panel: $OLD_VERSION → $NEW_VERSION"
echo
echo "  Backup:   $BACKUP"
echo "  Undo:     curl -fsSL https://raw.githubusercontent.com/$GITHUB_REPO/main/infra/upgrade.sh | sudo env ROLLBACK=1 bash"
echo "  Untouched: nginx, TLS, /etc/gisila config, packages, Postgres, Redis"
