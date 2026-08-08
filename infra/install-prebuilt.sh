#!/usr/bin/env bash
# =============================================================================
# Gisila Panel — prebuilt single-node installer (no build toolchain required).
#
# For new devs / operators on Debian 12+ or Ubuntu 22.04+ (x64 and arm64).
# Downloads a prebuilt release (compiled binaries + panel UI + migrations) from
# GitHub Releases and wires up the system. Unlike infra/install.sh it installs
# NO Dart SDK, Node.js or pnpm and compiles nothing — so it is far faster and
# never hits the pnpm build-approval failure.
#
# PostgreSQL and Redis are NOT installed or managed by this script — the panel
# is a client of both, not their operator. Point it at existing instances
# (same host or remote) with DATABASE_URL / REDIS_URL (preferred) or discrete
# DB_*/REDIS_* vars. Defaults assume a local Postgres/Redis you already stood up.
#
# Run as root. Examples:
#   sudo bash infra/install-prebuilt.sh
#   sudo VERSION=0.1.0 bash infra/install-prebuilt.sh
#   sudo RELEASE_FILE=/tmp/gisila-release-linux-arm64.tar.gz bash infra/install-prebuilt.sh
#   sudo DATABASE_URL='postgresql://gisila:secret@10.0.0.5:5432/gisila_panel' \
#        REDIS_URL='redis://:secret@10.0.0.5:6379' \
#        PANEL_DOMAIN=panel.example.com \
#        bash infra/install-prebuilt.sh
#
# One-liner (env vars must be on `env`/`bash`, not on `curl`):
#   curl -fsSL https://raw.githubusercontent.com/gumisofts/gisila_panel/main/infra/install-prebuilt.sh \
#     | sudo env DATABASE_URL='postgresql://gisila:gisila@localhost:5432/gisila_panel' \
#                PANEL_DOMAIN=panel.example.com bash
#
# Env knobs:
#   VERSION, GITHUB_REPO, RELEASE_URL, RELEASE_FILE
#   SKIP_OS_CHECK=1  bypass Ubuntu/Debian version check (unsupported)
#   DATABASE_URL   postgresql://user:pass@host:5432/db(?sslmode=require)
#   REDIS_URL      redis://[:pass@]host:6379
#   PANEL_DOMAIN   hostname written into the nginx vhost
#   ISSUE_TLS=1    run certbot for PANEL_DOMAIN after nginx is up
#   DB_HOST, DB_PORT, DB_NAME, DB_USER, DB_PASSWORD, DB_SSL   (override URL fields)
#   REDIS_HOST, REDIS_PORT, REDIS_PASSWORD                   (override URL fields)
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

# Load shared URL/domain helpers (cloned tree, or fetch when piped via curl).
_GISILA_ENV_HELPER="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd)/install-env.sh"
if [[ -f "${_GISILA_ENV_HELPER:-}" ]]; then
  # shellcheck source=install-env.sh
  source "$_GISILA_ENV_HELPER"
else
  # shellcheck disable=SC1090
  source <(curl -fsSL "https://raw.githubusercontent.com/${GITHUB_REPO}/main/infra/install-env.sh")
fi

gisila_require_supported_os

ARCH="$(uname -m)"
case "$ARCH" in
  x86_64 | amd64) ARCH=x64 ;;
  aarch64 | arm64) ARCH=arm64 ;;
esac
ASSET="gisila-release-linux-${ARCH}.tar.gz"

# CI publishes linux-x64 and linux-arm64. Fail early on anything else instead
# of a bare curl 404 — unless the caller is pointing at their own artifact/URL.
case "$ARCH" in
  x64 | arm64) ;;
  *)
    if [[ -z "${RELEASE_FILE:-}" && -z "${RELEASE_URL:-}" ]]; then
      echo "ERROR: no prebuilt release is published for linux-$ARCH" >&2
      echo "       (CI builds linux-x64 and linux-arm64 — see .github/workflows/release.yml)." >&2
      echo "       Build your own with 'bash infra/build-release.sh' on this host, then" >&2
      echo "       re-run with RELEASE_FILE=/path/to/gisila-release-linux-$ARCH.tar.gz," >&2
      echo "       or use infra/install.sh to build from source instead." >&2
      exit 1
    fi
    ;;
esac

# ── 1. System packages (runtime only — no build toolchain) ────────────────────
# Note: no `postgresql` or `redis-server` here — this installer is a client of
# both, not their operator (see header comment). `postgresql-client` only
# provides the `psql` CLI, used below to sanity-check connectivity.
echo "==> Installing system packages"
apt-get update -qq
DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
  postgresql-client nginx \
  certbot python3-certbot-nginx python3 \
  apparmor apparmor-utils \
  curl ca-certificates rsync tar

# Resolve DATABASE_URL / REDIS_URL / PANEL_DOMAIN after python3 is available.
gisila_apply_install_env

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
  echo "       Create the database/role yourself, then re-run with DATABASE_URL, e.g.:" >&2
  echo "         sudo env DATABASE_URL='postgresql://gisila:SECRET@localhost:5432/gisila_panel' bash \$0" >&2
  echo "       On the DB host:" >&2
  echo "         sudo -u postgres psql -c \"CREATE ROLE $DB_USER LOGIN PASSWORD '<pw>';\"" >&2
  echo "         sudo -u postgres createdb --owner=$DB_USER $DB_NAME" >&2
  exit 1
fi
echo "    connected."

echo "==> Checking Redis connectivity ($REDIS_HOST:$REDIS_PORT)"
if ! timeout 5 bash -c "exec 3<>/dev/tcp/$REDIS_HOST/$REDIS_PORT" 2>/dev/null; then
  echo "ERROR: could not open a TCP connection to Redis at $REDIS_HOST:$REDIS_PORT." >&2
  echo "       Install/start Redis yourself, then re-run with REDIS_URL, e.g.:" >&2
  echo "         sudo env REDIS_URL='redis://:SECRET@127.0.0.1:6379' bash \$0" >&2
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
SUPERUSER_EMAIL=admin@${PANEL_DOMAIN:-$(hostname -d 2>/dev/null | grep -m1 . || echo example.com)}
SUPERUSER_PASSWORD=$(head -c 16 /dev/urandom | base64 | tr -d '/+=')
REDIS_HOST=$REDIS_HOST
REDIS_PORT=$REDIS_PORT
REDIS_PASSWORD=$REDIS_PASSWORD
PANEL_DOMAIN=$PANEL_DOMAIN
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
gisila_apply_panel_domain /etc/nginx/sites-available/gisila-panel
nginx -t
systemctl enable --now nginx
systemctl reload nginx
gisila_maybe_issue_tls

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
if [[ -n "$PANEL_DOMAIN" ]]; then
  echo "  Panel:  http://$PANEL_DOMAIN  (https if ISSUE_TLS=1 succeeded)"
  echo "  Docs:   http://$PANEL_DOMAIN/docs"
  echo "  Admin:  http://$PANEL_DOMAIN/admin"
else
  echo "  Panel:  http://$IP"
  echo "  Docs:   http://$IP/docs"
  echo "  Admin:  http://$IP/admin"
fi
echo
echo "  PostgreSQL: $DB_USER@$DB_HOST:$DB_PORT/$DB_NAME (external, /etc/gisila/database.yaml)"
echo "  Redis:      $REDIS_HOST:$REDIS_PORT (external, /etc/gisila/.env)"
echo
echo "  Panel superuser:  see /etc/gisila/.env (SUPERUSER_EMAIL/PASSWORD)"
echo "  Studio/admin:     see /etc/gisila/.env (STUDIO_USERNAME/PASSWORD)"
echo
if [[ -z "$PANEL_DOMAIN" ]]; then
  echo "  To set a domain (or re-run with PANEL_DOMAIN=… ISSUE_TLS=1):"
  echo "    Edit /etc/nginx/sites-available/gisila-panel → set server_name"
  echo "    certbot --nginx -d panel.your-domain.tld"
  echo
fi
