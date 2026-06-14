#!/usr/bin/env bash
# =============================================================================
# Gisila Panel — single-node production installer.
#
# Tested on Ubuntu 22.04 / Debian 12. Run as root: sudo bash infra/install.sh
#
# What this does (idempotent — safe to re-run):
#   1. Installs system packages (postgres, redis, nginx, certbot, apparmor,
#      git, build-essential, unzip, the Dart SDK, Node.js 22 LTS, pnpm).
#   2. Creates the `gisila` system user and /srv/gisila/ layout.
#   3. Initialises the Postgres database and role.
#   4. Compiles the API, worker, and agent to native binaries and installs
#      them under /usr/local/bin/.
#   5. Builds the Vite frontend into backend/web/ (served by the Dart API).
#   6. Drops the strict sudoers rule so `gisila` can run `gisila-agent` as root.
#   7. Installs systemd units for the API and worker.
#   8. Writes config (/etc/gisila/.env, /etc/gisila/database.yaml).
#   9. Runs the schema migration.
#  10. Writes the panel's own Nginx vhost and starts everything.
# =============================================================================
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
  echo "Please run as root: sudo bash $0" >&2
  exit 1
fi

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
GISILA_USER="gisila"
GISILA_HOME="/srv/gisila"
APPS_ROOT="/srv/apps"

# ── 1. System packages ────────────────────────────────────────────────────────
echo "==> Installing system packages"
apt-get update -qq
DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
  postgresql redis-server nginx \
  certbot python3-certbot-nginx \
  apparmor apparmor-utils \
  git build-essential unzip \
  curl ca-certificates gnupg \
  libsqlite3-dev libssl-dev zlib1g-dev libbz2-dev \
  libreadline-dev libncursesw5-dev xz-utils \
  libxml2-dev libxmlsec1-dev libffi-dev liblzma-dev

if ! command -v dart >/dev/null 2>&1; then
  echo "==> Installing Dart SDK"
  curl -fsSL https://dl-ssl.google.com/linux/linux_signing_key.pub \
    | gpg --dearmor -o /usr/share/keyrings/dart.gpg
  echo 'deb [signed-by=/usr/share/keyrings/dart.gpg] https://storage.googleapis.com/download.dartlang.org/linux/debian stable main' \
    > /etc/apt/sources.list.d/dart_stable.list
  apt-get update -qq
  apt-get install -y -qq dart
fi

# Ensure dart is on PATH for this script.
export PATH="/usr/lib/dart/bin:$PATH"

if ! command -v node >/dev/null 2>&1; then
  echo "==> Installing Node.js 22 LTS"
  curl -fsSL https://deb.nodesource.com/setup_22.x | bash -
  apt-get install -y -qq nodejs
fi

if ! command -v pnpm >/dev/null 2>&1; then
  echo "==> Installing pnpm"
  corepack enable
  corepack prepare pnpm@latest --activate
fi

# ── 2. System user + directories ─────────────────────────────────────────────
echo "==> Creating gisila user and directories"
if ! id -u "$GISILA_USER" >/dev/null 2>&1; then
  useradd --system --create-home --home "$GISILA_HOME" \
    --shell /bin/bash "$GISILA_USER"
fi
install -d -o "$GISILA_USER" -g "$GISILA_USER" -m 0750 "$GISILA_HOME"
# APPS_ROOT is 0751 so each unprivileged app user can traverse into its own
# work dir (e.g. /srv/apps/app_xxx) via absolute paths — required by the build
# (python -m venv) and at runtime (systemd ExecStart). Per-app dirs stay 0750
# so app users cannot read or list each other's directories.
install -d -o "$GISILA_USER" -g "$GISILA_USER" -m 0751 "$APPS_ROOT"
install -d -o root -g root -m 0755 /var/log/gisila
# Database backup artifacts. Owned by gisila so the API can stream downloads and
# stage uploaded dumps for restore; the root agent writes the dumps here too.
install -d -o "$GISILA_USER" -g "$GISILA_USER" -m 0750 /var/lib/gisila/backups
install -d -o "$GISILA_USER" -g "$GISILA_USER" -m 0750 /var/lib/gisila/backups/uploads

# ── 3. PostgreSQL ─────────────────────────────────────────────────────────────
echo "==> Configuring PostgreSQL"
systemctl enable --now postgresql

# Wait until PostgreSQL is accepting connections (fresh install can take a moment).
echo "==> Waiting for PostgreSQL to be ready"
for i in $(seq 1 15); do
  sudo -u postgres pg_isready -q && break
  echo "    waiting... ($i/15)"
  sleep 2
done
sudo -u postgres pg_isready  # final check — exits non-zero if still not ready

# Create the role.  ON_ERROR_STOP=1 ensures psql failures propagate to set -e.
sudo -u postgres psql --set ON_ERROR_STOP=1 <<SQL
DO \$\$ BEGIN
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'gisila') THEN
    CREATE ROLE gisila LOGIN PASSWORD 'gisila';
  END IF;
END \$\$;
SQL

# CREATE DATABASE cannot run inside a PL/pgSQL DO block (transaction restriction).
# Use createdb which runs outside any transaction.
if ! sudo -u postgres psql --set ON_ERROR_STOP=1 \
    -tc "SELECT 1 FROM pg_database WHERE datname='gisila_panel'" | grep -q 1; then
  sudo -u postgres createdb --owner=gisila gisila_panel
  echo "    created database gisila_panel"
else
  echo "    database gisila_panel already exists, skipping"
fi

# ── 4. Build & install binaries (all as root) ─────────────────────────────────
echo "==> dart pub get — backend"
cd "$REPO_DIR/backend"
dart pub get

echo "==> code generation — backend"
dart run build_runner build --delete-conflicting-outputs

echo "==> compiling gisila-panel (API server)"
mkdir -p "$REPO_DIR/backend/build"
dart compile exe bin/server.dart -o "$REPO_DIR/backend/build/gisila-panel"
install -m 0755 "$REPO_DIR/backend/build/gisila-panel" /usr/local/bin/gisila-panel

echo "==> compiling gisila-worker"
dart compile exe bin/worker.dart -o "$REPO_DIR/backend/build/gisila-worker"
install -m 0755 "$REPO_DIR/backend/build/gisila-worker" /usr/local/bin/gisila-worker

echo "==> dart pub get — agent"
cd "$REPO_DIR/agent"
dart pub get

echo "==> compiling gisila-agent"
mkdir -p "$REPO_DIR/agent/build"
dart compile exe bin/gisila-agent.dart -o "$REPO_DIR/agent/build/gisila-agent"
install -m 0755 "$REPO_DIR/agent/build/gisila-agent" /usr/local/bin/gisila-agent

# ── 5. Frontend — build into backend/web/ ────────────────────────────────────
# The Dart API serves the panel UI directly from backend/web/.
# No separate Node.js server or systemd unit is needed.
echo "==> Building panel UI (Vite → backend/web/)"
# pnpm / corepack hardening for the UI build.
#
# Mirrors the per-app build env in agent/lib/runtime/builders.dart and the
# runtime env in the generated systemd units. On a fresh, TTY-less host this
# keeps the build deterministic and non-interactive — without it pnpm can abort
# the modules-dir purge prompt (ERR_PNPM_ABORTED_REMOVE_MODULES_DIR_NO_TTY) when
# its pre-script deps check decides to reinstall, or corepack can try to fetch a
# pinned pnpm into an unwritable cache. CI=true is pnpm's documented remedy; the
# verify-deps / confirm-purge keys are set under both the npm_config_ (pnpm
# 9/10) and pnpm_config_ (pnpm 11) prefixes so the fix is version-agnostic.
export CI=true
export COREPACK_ENABLE_STRICT=0
export COREPACK_ENABLE_AUTO_PIN=0
export npm_config_verify_deps_before_run=false
export pnpm_config_verify_deps_before_run=false
export npm_config_confirm_modules_purge=false
export pnpm_config_confirm_modules_purge=false
cd "$REPO_DIR/frontend"
pnpm install --prefer-frozen-lockfile
pnpm build

# Deploy the built assets to /srv/gisila/web/ where the API server can find
# them (WorkingDirectory=/srv/gisila in gisila-panel.service).
echo "==> Deploying panel UI assets to $GISILA_HOME/web"
install -d -o "$GISILA_USER" -g "$GISILA_USER" -m 0750 "$GISILA_HOME/web"
rsync -a --delete "$REPO_DIR/backend/web/" "$GISILA_HOME/web/"
chown -R "$GISILA_USER:$GISILA_USER" "$GISILA_HOME/web"

# ── 6. Journal access for the API user ───────────────────────────────────────
# The gisila-panel API streams app runtime logs via journalctl. Adding the
# gisila user to the systemd-journal group lets it read journals without root,
# which is required on VPS hosts that enforce no_new_privileges (blocking sudo).
echo "==> Adding gisila to systemd-journal group"
usermod -aG systemd-journal "$GISILA_USER"

# ── 7. systemd units ─────────────────────────────────────────────────────────
echo "==> Installing systemd units"
install -m 0644 "$REPO_DIR/infra/gisila-panel.service"  /etc/systemd/system/
install -m 0644 "$REPO_DIR/infra/gisila-worker.service" /etc/systemd/system/
install -m 0644 "$REPO_DIR/infra/gisila-apps.target"    /etc/systemd/system/
systemctl daemon-reload
systemctl enable gisila-apps.target
systemctl enable gisila-panel.service gisila-worker.service

# ── 8. /etc/gisila/.env ───────────────────────────────────────────────────────
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
REDIS_HOST=127.0.0.1
REDIS_PORT=6379
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
  # On upgrades the file already exists — ensure SUPERUSER vars are present.
  if ! grep -q 'SUPERUSER_EMAIL' /etc/gisila/.env; then
    echo "SUPERUSER_EMAIL=admin@$(hostname -d 2>/dev/null | grep -m1 . || echo example.com)" \
      >> /etc/gisila/.env
    echo "SUPERUSER_PASSWORD=$(head -c 16 /dev/urandom | base64 | tr -d '/+=')" \
      >> /etc/gisila/.env
    echo "    added SUPERUSER_EMAIL/SUPERUSER_PASSWORD to existing .env"
  fi
fi

# ── 9. /etc/gisila/database.yaml ──────────────────────────────────────────────
echo "==> Writing /etc/gisila/database.yaml"
# Detect the major version of the running system cluster so the panel can show
# its own backing database as a read-only "system" instance (server_version).
SYSTEM_PG_VERSION="$(sudo -u postgres psql -tAc 'SHOW server_version_num' 2>/dev/null \
  | awk '{ printf "%d", $1 / 10000 }')"
SYSTEM_PG_VERSION="${SYSTEM_PG_VERSION:-0}"
echo "    detected system PostgreSQL major version: $SYSTEM_PG_VERSION"
cat > /etc/gisila/database.yaml <<EOF
default: default
connections:
  default:
    type: postgresql
    host: localhost
    port: 5432
    database: gisila_panel
    username: gisila
    password: gisila
    ssl: false
    connection_timeout: 30
    query_timeout: 30
    max_connections: 20
    min_connections: 2
    # Major version of this cluster. Surfaced read-only as the "system" instance
    # in the Databases panel; its port and version are never editable there.
    additional_params:
      server_version: $SYSTEM_PG_VERSION
EOF
chown "$GISILA_USER:$GISILA_USER" /etc/gisila/database.yaml
chmod 0640 /etc/gisila/database.yaml

# ── 10. Database migration ────────────────────────────────────────────────────
echo "==> Running migrations"
cd "$REPO_DIR/backend"
GISILA_DATABASE_FILE=/etc/gisila/database.yaml \
  dart run gisila_orm:migrate up --dir lib/migrations --config /etc/gisila/database.yaml

# ── 10b. Seed initial superuser ───────────────────────────────────────────────
# Load the env file so SUPERUSER_EMAIL / SUPERUSER_PASSWORD are available, then
# run the server's seed-only mode.  This is idempotent: if a superuser already
# exists the seed is skipped automatically.
echo "==> Seeding initial superuser"
set -a; source /etc/gisila/.env; set +a
GISILA_DATABASE_FILE=/etc/gisila/database.yaml \
  gisila-panel --seed-superuser || true

# ── 11. Nginx vhost ───────────────────────────────────────────────────────────
echo "==> Installing nginx panel vhost"
install -m 0644 "$REPO_DIR/infra/nginx-panel.conf" \
  /etc/nginx/sites-available/gisila-panel
ln -sf /etc/nginx/sites-available/gisila-panel \
  /etc/nginx/sites-enabled/gisila-panel
nginx -t
systemctl enable --now nginx
systemctl reload nginx

# ── 12. Start panel services ──────────────────────────────────────────────────
echo "==> Starting gisila-panel and gisila-worker"
systemctl restart gisila-panel.service gisila-worker.service
sleep 3
systemctl status --no-pager \
  gisila-panel.service gisila-worker.service || true

echo
echo "✓ Gisila Panel installed successfully."
echo
IP=$(hostname -I | awk '{print $1}')
echo "  Panel:  http://$IP  (or your configured domain)"
echo "  Docs:   http://$IP/docs"
echo "  Admin:  http://$IP/admin"
echo
echo "  Panel superuser:  \$SUPERUSER_EMAIL (see /etc/gisila/.env)"
echo "  Studio/admin:    \$STUDIO_USERNAME (see /etc/gisila/.env)"
echo
echo "  To add a domain and get a TLS cert:"
echo "    Edit /etc/nginx/sites-available/gisila-panel → set server_name"
echo "    certbot --nginx -d panel.your-domain.tld"
echo
