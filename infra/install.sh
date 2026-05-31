#!/usr/bin/env bash
# =============================================================================
# Gisila Panel — single-node production installer.
#
# Tested on Ubuntu 22.04 / Debian 12. Run as root: sudo bash infra/install.sh
#
# What this does (idempotent — safe to re-run):
#   1. Installs system packages (postgres, redis, nginx, certbot, apparmor,
#      git, build-essential, unzip, the Dart SDK).
#   2. Creates the `gisila` system user and /srv/gisila/ layout.
#   3. Compiles the API, worker, and agent to native binaries and installs
#      them under /usr/local/bin/.
#   4. Drops the strict sudoers rule so `gisila` can run `gisila-agent` as root.
#   5. Installs systemd units for the API and worker.
#   6. Initialises the Postgres database and runs the schema migration.
#   7. Writes the panel's own Nginx vhost and starts everything.
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
  curl ca-certificates gnupg

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

# ── 2. System user + directories ─────────────────────────────────────────────
echo "==> Creating gisila user and directories"
if ! id -u "$GISILA_USER" >/dev/null 2>&1; then
  useradd --system --create-home --home "$GISILA_HOME" \
    --shell /bin/bash "$GISILA_USER"
fi
install -d -o "$GISILA_USER" -g "$GISILA_USER" -m 0750 "$GISILA_HOME" "$APPS_ROOT"
install -d -o root -g root -m 0755 /var/log/gisila

# ── 3. PostgreSQL ─────────────────────────────────────────────────────────────
echo "==> Configuring PostgreSQL"
systemctl enable --now postgresql
sudo -u postgres psql <<SQL
DO \$\$ BEGIN
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'gisila') THEN
    CREATE ROLE gisila LOGIN PASSWORD 'gisila';
  END IF;
END \$\$;
DO \$\$ BEGIN
  IF NOT EXISTS (SELECT FROM pg_database WHERE datname = 'gisila_panel') THEN
    CREATE DATABASE gisila_panel OWNER gisila;
  END IF;
END \$\$;
SQL

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

# ── 5. sudoers rule ───────────────────────────────────────────────────────────
echo "==> Installing sudoers rule"
install -m 0440 "$REPO_DIR/infra/sudoers.d_gisila" /etc/sudoers.d/gisila
visudo -cf /etc/sudoers.d/gisila

# ── 6. systemd units ─────────────────────────────────────────────────────────
echo "==> Installing systemd units"
install -m 0644 "$REPO_DIR/infra/gisila-panel.service"  /etc/systemd/system/
install -m 0644 "$REPO_DIR/infra/gisila-worker.service" /etc/systemd/system/
install -m 0644 "$REPO_DIR/infra/gisila-apps.target"    /etc/systemd/system/
systemctl daemon-reload
systemctl enable gisila-apps.target
systemctl enable gisila-panel.service gisila-worker.service

# ── 7. /etc/gisila/.env ───────────────────────────────────────────────────────
echo "==> Writing /etc/gisila/.env"
install -d -o "$GISILA_USER" -g "$GISILA_USER" -m 0750 /etc/gisila
if [[ ! -f /etc/gisila/.env ]]; then
  cat > /etc/gisila/.env <<EOF
PORT=8000
JWT_SECRET=$(head -c 32 /dev/urandom | base64)
JWT_EXPIRE_DAYS=14
STUDIO_USERNAME=admin
STUDIO_PASSWORD=$(head -c 12 /dev/urandom | base64 | tr -d '/+=')
REDIS_HOST=127.0.0.1
REDIS_PORT=6379
APPS_ROOT=$APPS_ROOT
NGINX_SITES_DIR=/etc/nginx/sites-enabled
SYSTEMD_UNITS_DIR=/etc/systemd/system
APPARMOR_PROFILES_DIR=/etc/apparmor.d
APP_PORT_RANGE_MIN=4000
APP_PORT_RANGE_MAX=4999
AGENT_MODE=sudo
AGENT_BIN=/usr/local/bin/gisila-agent
NODE_ID=$(hostname -s)
EOF
  chown "$GISILA_USER:$GISILA_USER" /etc/gisila/.env
  chmod 0640 /etc/gisila/.env
fi

# ── 8. /etc/gisila/database.yaml ──────────────────────────────────────────────
echo "==> Writing /etc/gisila/database.yaml"
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
EOF
chown "$GISILA_USER:$GISILA_USER" /etc/gisila/database.yaml
chmod 0640 /etc/gisila/database.yaml

# ── 9. Database migration ─────────────────────────────────────────────────────
echo "==> Running migrations"
cd "$REPO_DIR/backend"
GISILA_DATABASE_FILE=/etc/gisila/database.yaml \
  dart run gisila_orm:migrate up --config /etc/gisila/database.yaml

# ── 10. Nginx vhost ───────────────────────────────────────────────────────────
echo "==> Installing nginx panel vhost"
install -m 0644 "$REPO_DIR/infra/nginx-panel.conf" \
  /etc/nginx/sites-available/gisila-panel
ln -sf /etc/nginx/sites-available/gisila-panel \
  /etc/nginx/sites-enabled/gisila-panel
nginx -t
systemctl enable --now nginx
systemctl reload nginx

# ── 11. Start panel services ──────────────────────────────────────────────────
echo "==> Starting gisila-panel and gisila-worker"
systemctl restart gisila-panel.service gisila-worker.service
sleep 2
systemctl status --no-pager gisila-panel.service gisila-worker.service || true

echo
echo "✓ Gisila Panel installed successfully."
echo
echo "  API:    http://$(hostname -I | awk '{print $1}'):8000"
echo "  Docs:   http://$(hostname -I | awk '{print $1}'):8000/docs"
echo "  Admin:  http://$(hostname -I | awk '{print $1}'):8000/admin"
echo
echo "  Credentials are in /etc/gisila/.env (STUDIO_USERNAME / STUDIO_PASSWORD)."
echo
echo "  To add a domain and get a TLS cert:"
echo "    Edit /etc/nginx/sites-available/gisila-panel → set server_name"
echo "    certbot --nginx -d panel.your-domain.tld"
echo
