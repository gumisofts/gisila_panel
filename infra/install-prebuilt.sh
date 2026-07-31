#!/usr/bin/env bash
# =============================================================================
# Gisila Panel — prebuilt single-node installer (no build toolchain required).
#
# For new devs / operators on Debian 12 or Ubuntu 22.04+. Downloads a prebuilt
# release (compiled binaries + panel UI + migrations) from GitHub Releases and
# wires up the system. Unlike infra/install.sh it installs NO Dart SDK, Node.js
# or pnpm and compiles nothing — so it is far faster and never hits the pnpm
# build-approval failure.
#
# PostgreSQL and Redis are NOT installed or managed by this script — the panel
# is a client of both, not their operator. Point it at existing instances
# (same host or remote) with the DB_*/REDIS_* env vars below; defaults assume
# a Postgres/Redis you've already stood up locally with those exact settings.
#
# Run as root. Examples:
#   sudo bash infra/install-prebuilt.sh                       # newest release
#   sudo VERSION=0.1.0 bash infra/install-prebuilt.sh         # pinned version
#   sudo RELEASE_FILE=/tmp/gisila-release-linux-x64.tar.gz \
#        bash infra/install-prebuilt.sh                       # local artifact
#   sudo DB_HOST=10.0.0.5 DB_PASSWORD=secret \
#        REDIS_HOST=10.0.0.5 REDIS_PASSWORD=secret \
#        bash infra/install-prebuilt.sh                       # external DB/Redis
#
# One-liner (no clone needed):
#   curl -fsSL https://raw.githubusercontent.com/gumisofts/gisila_panel/main/infra/install-prebuilt.sh | sudo bash
#
# Env knobs:
#   VERSION       release to install: "latest" (default) or e.g. "0.1.0"
#   GITHUB_REPO   owner/repo to fetch from (default: gumisofts/gisila_panel)
#   RELEASE_URL   exact tarball URL (overrides VERSION/GITHUB_REPO)
#   RELEASE_FILE  path to a local tarball (skips the download entirely)
#   DB_HOST, DB_PORT, DB_NAME, DB_USER, DB_PASSWORD, DB_SSL   PostgreSQL
#   REDIS_HOST, REDIS_PORT, REDIS_PASSWORD                   Redis
# =============================================================================
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
  echo "Please run as root: sudo bash $0" >&2
  exit 1
fi

GISILA_USER="gisila"
GISILA_HOME="/srv/gisila"
APPS_ROOT="/srv/apps"
MIGRATIONS_DIR="/usr/local/share/gisila/migrations"
GITHUB_REPO="${GITHUB_REPO:-gumisofts/gisila_panel}"
VERSION="${VERSION:-latest}"

# External PostgreSQL connection this install will point the panel at. Not
# installed here — see the header comment above.
DB_HOST="${DB_HOST:-localhost}"
DB_PORT="${DB_PORT:-5432}"
DB_NAME="${DB_NAME:-gisila_panel}"
DB_USER="${DB_USER:-gisila}"
DB_PASSWORD="${DB_PASSWORD:-gisila}"
DB_SSL="${DB_SSL:-false}"

# External Redis connection this install will point the panel at. Not
# installed here — see the header comment above.
REDIS_HOST="${REDIS_HOST:-127.0.0.1}"
REDIS_PORT="${REDIS_PORT:-6379}"
REDIS_PASSWORD="${REDIS_PASSWORD:-}"

ARCH="$(uname -m)"
case "$ARCH" in
  x86_64 | amd64) ARCH=x64 ;;
  aarch64 | arm64) ARCH=arm64 ;;
esac
ASSET="gisila-release-linux-${ARCH}.tar.gz"

# CI (.github/workflows/release.yml) currently only builds/publishes linux-x64.
# Fail early with a clear message on other architectures instead of a bare
# curl 404 — unless the caller is pointing at their own artifact/URL.
if [[ "$ARCH" != "x64" && -z "${RELEASE_FILE:-}" && -z "${RELEASE_URL:-}" ]]; then
  echo "ERROR: no prebuilt release is published for linux-$ARCH yet" >&2
  echo "       (CI only builds linux-x64 — see .github/workflows/release.yml)." >&2
  echo "       Build your own with 'bash infra/build-release.sh' on this host, then" >&2
  echo "       re-run with RELEASE_FILE=/path/to/gisila-release-linux-$ARCH.tar.gz," >&2
  echo "       or use infra/install.sh to build from source instead." >&2
  exit 1
fi

# ── 1. System packages (runtime only — no build toolchain) ────────────────────
# Note: no `postgresql` or `redis-server` here — this installer is a client of
# both, not their operator (see header comment). `postgresql-client` only
# provides the `psql` CLI, used below to sanity-check connectivity.
echo "==> Installing system packages"
apt-get update -qq
DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
  postgresql-client nginx \
  certbot python3-certbot-nginx \
  apparmor apparmor-utils \
  curl ca-certificates rsync tar

# ── 2. Fetch & unpack the prebuilt release ────────────────────────────────────
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

if [[ -n "${RELEASE_FILE:-}" ]]; then
  echo "==> Using local release artifact: $RELEASE_FILE"
  [[ -f "$RELEASE_FILE" ]] || { echo "ERROR: $RELEASE_FILE not found" >&2; exit 1; }
  cp "$RELEASE_FILE" "$STAGE/release.tar.gz"
else
  if [[ -n "${RELEASE_URL:-}" ]]; then
    URL="$RELEASE_URL"
  elif [[ "$VERSION" == "latest" ]]; then
    URL="https://github.com/$GITHUB_REPO/releases/latest/download/$ASSET"
  else
    URL="https://github.com/$GITHUB_REPO/releases/download/v${VERSION#v}/$ASSET"
  fi
  echo "==> Downloading $URL"
  DOWNLOAD_OK=false
  if curl -fSL "$URL" -o "$STAGE/release.tar.gz"; then
    DOWNLOAD_OK=true
  elif [[ "$VERSION" == "latest" && -z "${RELEASE_URL:-}" ]]; then
    # GitHub's "latest release" endpoint/URL (used above) silently skips
    # draft *and prerelease* releases — so it 404s whenever the newest
    # published release was tagged as a prerelease (common for early v0.x
    # tags). Fall back to the releases API, which lists every release
    # newest-first regardless of that flag, and retry against its tag
    # directly instead of making the operator pass an explicit VERSION.
    echo "    /releases/latest has no asset (likely a prerelease) — checking the releases API"
    FALLBACK_TAG="$(curl -fsSL "https://api.github.com/repos/$GITHUB_REPO/releases" 2>/dev/null \
      | grep -m1 '"tag_name"' | sed -E 's/.*"tag_name": *"([^"]+)".*/\1/' || true)"
    if [[ -n "$FALLBACK_TAG" ]]; then
      URL="https://github.com/$GITHUB_REPO/releases/download/$FALLBACK_TAG/$ASSET"
      echo "==> Retrying with newest published release: $FALLBACK_TAG"
      curl -fSL "$URL" -o "$STAGE/release.tar.gz" && DOWNLOAD_OK=true
    fi
  fi

  if ! $DOWNLOAD_OK; then
    echo >&2
    echo "ERROR: failed to download the release asset from:" >&2
    echo "         $URL" >&2
    echo "       Most likely no GitHub Release has been published for" >&2
    echo "       $GITHUB_REPO yet, or '$VERSION' doesn't match a published tag." >&2
    echo "       Publish one with 'bash infra/build-release.sh' + 'gh release create'," >&2
    echo "       or install from a local artifact with RELEASE_FILE=/path/to/*.tar.gz." >&2
    exit 1
  fi
fi

tar -C "$STAGE" -xzf "$STAGE/release.tar.gz"
SRC="$(find "$STAGE" -maxdepth 1 -type d -name 'gisila-release*' | head -1)"
if [[ -z "$SRC" || ! -x "$SRC/bin/gisila-panel" ]]; then
  echo "ERROR: release archive is missing bin/gisila-panel — wrong/corrupt asset?" >&2
  exit 1
fi
echo "    release version: $(cat "$SRC/VERSION" 2>/dev/null || echo unknown)"

# ── 3. System user + directories ──────────────────────────────────────────────
echo "==> Creating gisila user and directories"
if ! id -u "$GISILA_USER" >/dev/null 2>&1; then
  useradd --system --create-home --home "$GISILA_HOME" \
    --shell /bin/bash "$GISILA_USER"
fi
install -d -o "$GISILA_USER" -g "$GISILA_USER" -m 0750 "$GISILA_HOME"
install -d -o "$GISILA_USER" -g "$GISILA_USER" -m 0751 "$APPS_ROOT"
install -d -o root -g root -m 0755 /var/log/gisila
install -d -o "$GISILA_USER" -g "$GISILA_USER" -m 0750 /var/lib/gisila/backups
install -d -o "$GISILA_USER" -g "$GISILA_USER" -m 0750 /var/lib/gisila/backups/uploads

# ── 4. Check external PostgreSQL & Redis connectivity ────────────────────────
# Neither is provisioned by this script (see header comment) — the database,
# role, and password must already exist on $DB_HOST. We only verify we can
# reach both so a misconfigured DB_*/REDIS_* var fails fast, here, instead of
# deep inside the migration step below.
echo "==> Checking PostgreSQL connectivity ($DB_USER@$DB_HOST:$DB_PORT/$DB_NAME)"
if ! PGPASSWORD="$DB_PASSWORD" psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" \
    -d "$DB_NAME" --set ON_ERROR_STOP=1 -tc 'SELECT 1' >/dev/null 2>&1; then
  echo "ERROR: could not connect to PostgreSQL as $DB_USER@$DB_HOST:$DB_PORT/$DB_NAME." >&2
  echo "       This script no longer installs/configures PostgreSQL — create the" >&2
  echo "       database and role yourself, then re-run with matching DB_HOST/DB_PORT/" >&2
  echo "       DB_NAME/DB_USER/DB_PASSWORD env vars. Example, on the DB host:" >&2
  echo "         sudo -u postgres psql -c \"CREATE ROLE $DB_USER LOGIN PASSWORD '<pw>';\"" >&2
  echo "         sudo -u postgres createdb --owner=$DB_USER $DB_NAME" >&2
  exit 1
fi
echo "    connected."

echo "==> Checking Redis connectivity ($REDIS_HOST:$REDIS_PORT)"
if ! timeout 5 bash -c "exec 3<>/dev/tcp/$REDIS_HOST/$REDIS_PORT" 2>/dev/null; then
  echo "ERROR: could not open a TCP connection to Redis at $REDIS_HOST:$REDIS_PORT." >&2
  echo "       This script no longer installs/configures Redis — stand it up yourself," >&2
  echo "       then re-run with matching REDIS_HOST/REDIS_PORT/REDIS_PASSWORD env vars." >&2
  exit 1
fi
echo "    connected."

# ── 5. Install prebuilt binaries ──────────────────────────────────────────────
echo "==> Installing binaries to /usr/local/bin"
install -m 0755 "$SRC/bin/gisila-panel"   /usr/local/bin/gisila-panel
install -m 0755 "$SRC/bin/gisila-worker"  /usr/local/bin/gisila-worker
install -m 0755 "$SRC/bin/gisila-migrate" /usr/local/bin/gisila-migrate
install -m 0755 "$SRC/bin/gisila-agent"   /usr/local/bin/gisila-agent

# ── 6. Deploy panel UI + migrations ───────────────────────────────────────────
echo "==> Deploying panel UI assets to $GISILA_HOME/web"
install -d -o "$GISILA_USER" -g "$GISILA_USER" -m 0750 "$GISILA_HOME/web"
rsync -a --delete "$SRC/web/" "$GISILA_HOME/web/"
chown -R "$GISILA_USER:$GISILA_USER" "$GISILA_HOME/web"

echo "==> Installing migrations to $MIGRATIONS_DIR"
install -d -o root -g root -m 0755 "$MIGRATIONS_DIR"
rsync -a --delete "$SRC/migrations/" "$MIGRATIONS_DIR/"

# ── 7. Journal access for the API user ────────────────────────────────────────
echo "==> Adding gisila to systemd-journal group"
usermod -aG systemd-journal "$GISILA_USER"

# ── 8. systemd units ──────────────────────────────────────────────────────────
echo "==> Installing systemd units"
install -m 0644 "$SRC/infra/gisila-panel.service"  /etc/systemd/system/
install -m 0644 "$SRC/infra/gisila-worker.service" /etc/systemd/system/
install -m 0644 "$SRC/infra/gisila-apps.target"    /etc/systemd/system/
systemctl daemon-reload
systemctl enable gisila-apps.target
systemctl enable gisila-panel.service gisila-worker.service

# ── 9. /etc/gisila/.env ───────────────────────────────────────────────────────
echo "==> Writing /etc/gisila/.env"
install -d -o "$GISILA_USER" -g "$GISILA_USER" -m 0750 /etc/gisila
if [[ ! -f /etc/gisila/.env ]]; then
  cat > /etc/gisila/.env <<EOF
PORT=8000
JWT_SECRET=$(head -c 32 /dev/urandom | base64)
JWT_EXPIRE_DAYS=14
STUDIO_USERNAME=admin
STUDIO_PASSWORD=$(head -c 12 /dev/urandom | base64 | tr -d '/+=')
SUPERUSER_EMAIL=admin@$(hostname -d 2>/dev/null | grep -m1 . || echo example.com)
SUPERUSER_PASSWORD=$(head -c 16 /dev/urandom | base64 | tr -d '/+=')
REDIS_HOST=$REDIS_HOST
REDIS_PORT=$REDIS_PORT
REDIS_PASSWORD=$REDIS_PASSWORD
APPS_ROOT=$APPS_ROOT
NGINX_SITES_DIR=/etc/nginx/sites-enabled
SYSTEMD_UNITS_DIR=/etc/systemd/system
APPARMOR_PROFILES_DIR=/etc/apparmor.d
APP_PORT_RANGE_MIN=4000
APP_PORT_RANGE_MAX=4999
AGENT_MODE=direct
AGENT_BIN=/usr/local/bin/gisila-agent
NODE_ID=$(hostname -s)
EOF
  chown "$GISILA_USER:$GISILA_USER" /etc/gisila/.env
  chmod 0640 /etc/gisila/.env
else
  if ! grep -q 'SUPERUSER_EMAIL' /etc/gisila/.env; then
    echo "SUPERUSER_EMAIL=admin@$(hostname -d 2>/dev/null | grep -m1 . || echo example.com)" \
      >> /etc/gisila/.env
    echo "SUPERUSER_PASSWORD=$(head -c 16 /dev/urandom | base64 | tr -d '/+=')" \
      >> /etc/gisila/.env
    echo "    added SUPERUSER_EMAIL/SUPERUSER_PASSWORD to existing .env"
  fi
  if ! grep -q 'REDIS_PASSWORD' /etc/gisila/.env; then
    echo "REDIS_PASSWORD=$REDIS_PASSWORD" >> /etc/gisila/.env
    echo "    added REDIS_PASSWORD to existing .env"
  fi
fi

# ── 10. /etc/gisila/database.yaml ─────────────────────────────────────────────
echo "==> Writing /etc/gisila/database.yaml"
# Detect the major version of the configured cluster (works for remote hosts
# too, unlike `sudo -u postgres`).
SYSTEM_PG_VERSION="$(PGPASSWORD="$DB_PASSWORD" psql -h "$DB_HOST" -p "$DB_PORT" \
  -U "$DB_USER" -d "$DB_NAME" -tAc 'SHOW server_version_num' 2>/dev/null \
  | awk '{ printf "%d", $1 / 10000 }')"
SYSTEM_PG_VERSION="${SYSTEM_PG_VERSION:-0}"
echo "    detected PostgreSQL major version: $SYSTEM_PG_VERSION"
cat > /etc/gisila/database.yaml <<EOF
default: default
connections:
  default:
    type: postgresql
    host: $DB_HOST
    port: $DB_PORT
    database: $DB_NAME
    username: $DB_USER
    password: $DB_PASSWORD
    ssl: $DB_SSL
    connection_timeout: 30
    query_timeout: 30
    max_connections: 20
    min_connections: 2
    additional_params:
      server_version: $SYSTEM_PG_VERSION
EOF
chown "$GISILA_USER:$GISILA_USER" /etc/gisila/database.yaml
chmod 0640 /etc/gisila/database.yaml

# ── 11. Database migration ────────────────────────────────────────────────────
echo "==> Running migrations"
GISILA_DATABASE_FILE=/etc/gisila/database.yaml \
  gisila-migrate up --dir "$MIGRATIONS_DIR" --config /etc/gisila/database.yaml

# ── 11b. Seed initial superuser ───────────────────────────────────────────────
echo "==> Seeding initial superuser"
set -a; source /etc/gisila/.env; set +a
GISILA_DATABASE_FILE=/etc/gisila/database.yaml \
  gisila-panel --seed-superuser || true

# ── 12. Nginx vhost ───────────────────────────────────────────────────────────
echo "==> Installing nginx panel vhost"
install -m 0644 "$SRC/infra/nginx-panel.conf" \
  /etc/nginx/sites-available/gisila-panel
ln -sf /etc/nginx/sites-available/gisila-panel \
  /etc/nginx/sites-enabled/gisila-panel
nginx -t
systemctl enable --now nginx
systemctl reload nginx

# ── 13. Start panel services ──────────────────────────────────────────────────
echo "==> Starting gisila-panel and gisila-worker"
systemctl restart gisila-panel.service gisila-worker.service
sleep 3
systemctl status --no-pager \
  gisila-panel.service gisila-worker.service || true

echo
echo "✓ Gisila Panel installed (prebuilt — no toolchain)."
echo
IP=$(hostname -I | awk '{print $1}')
echo "  Panel:  http://$IP  (or your configured domain)"
echo "  Docs:   http://$IP/docs"
echo "  Admin:  http://$IP/admin"
echo
echo "  PostgreSQL: $DB_USER@$DB_HOST:$DB_PORT/$DB_NAME (external, /etc/gisila/database.yaml)"
echo "  Redis:      $REDIS_HOST:$REDIS_PORT (external, /etc/gisila/.env)"
echo
echo "  Panel superuser:  see /etc/gisila/.env (SUPERUSER_EMAIL/PASSWORD)"
echo "  Studio/admin:     see /etc/gisila/.env (STUDIO_USERNAME/PASSWORD)"
echo
echo "  To add a domain and get a TLS cert:"
echo "    Edit /etc/nginx/sites-available/gisila-panel → set server_name"
echo "    certbot --nginx -d panel.your-domain.tld"
echo
