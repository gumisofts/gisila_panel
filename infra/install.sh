#!/usr/bin/env bash
# =============================================================================
# Gisila Panel — single-node production installer.
#
# Tested on Ubuntu 22.04+ / Debian 12+ (x64 and arm64).
# Run as root: sudo bash infra/install.sh
#
# PostgreSQL and Redis are NOT installed or managed by this script — the panel
# is a client of both, not their operator. Point it at existing instances with
# DATABASE_URL / REDIS_URL (preferred) or discrete DB_*/REDIS_* vars.
#
#   sudo DATABASE_URL='postgresql://gisila:secret@10.0.0.5:5432/gisila_panel' \
#        REDIS_URL='redis://:secret@10.0.0.5:6379' \
#        PANEL_DOMAIN=panel.example.com \
#        bash infra/install.sh
#
# Env knobs:
#   DATABASE_URL   postgresql://user:pass@host:5432/db(?sslmode=require)
#   REDIS_URL      redis://[:pass@]host:6379
#   PANEL_DOMAIN   hostname written into the nginx vhost
#   ISSUE_TLS=1    run certbot for PANEL_DOMAIN after nginx is up
#   DB_HOST, DB_PORT, DB_NAME, DB_USER, DB_PASSWORD, DB_SSL   (override URL)
#   REDIS_HOST, REDIS_PORT, REDIS_PASSWORD                   (override URL)
#   BUILD_FRONTEND=1   rebuild the UI from source instead of using the
#                      prebuilt backend/web/ assets (requires Node.js + pnpm)
#
# What this does (idempotent — safe to re-run):
#   1. Installs system packages (nginx, certbot, apparmor, git,
#      build-essential, unzip, the Dart SDK, the `psql` client). Node.js 22
#      LTS + pnpm are installed only when rebuilding the UI from source
#      (BUILD_FRONTEND=1).
#   2. Creates the `gisila` system user and /srv/gisila/ layout.
#   3. Compiles the API, worker, and agent to native binaries and installs
#      them under /usr/local/bin/.
#   4. Deploys the prebuilt Vite frontend from backend/web/ (served by the Dart
#      API). Pass BUILD_FRONTEND=1 to rebuild it from source instead.
#   5. Drops the strict sudoers rule so `gisila` can run `gisila-agent` as root.
#   6. Installs systemd units for the API and worker.
#   7. Writes config (/etc/gisila/.env, /etc/gisila/database.yaml) pointing at
#      the PostgreSQL/Redis instances described by the env vars above.
#   8. Runs the schema migration against that PostgreSQL instance.
#   9. Writes the panel's own Nginx vhost and starts everything.
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

# The panel UI ships prebuilt in backend/web/ (committed to the repo), so a
# normal install neither installs Node/pnpm nor runs a Vite build — that step
# was both the slowest part of the install and the one that broke whenever pnpm
# wanted its build scripts approved. Developers who changed the UI can rebuild
# from source with BUILD_FRONTEND=1.
BUILD_FRONTEND="${BUILD_FRONTEND:-0}"

# shellcheck source=install-env.sh
source "$REPO_DIR/infra/install-env.sh"

gisila_require_supported_os

# ── 1. System packages ────────────────────────────────────────────────────────
# Note: no `postgresql` or `redis-server` here — this installer is a client of
# both, not their operator (see header comment). `postgresql-client` only
# provides the `psql` CLI, used below to sanity-check connectivity.
echo "==> Installing system packages"
apt-get update -qq
DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
  postgresql-client nginx \
  certbot python3-certbot-nginx python3 \
  apparmor apparmor-utils \
  git build-essential unzip \
  curl ca-certificates gnupg \
  libsqlite3-dev libssl-dev zlib1g-dev libbz2-dev \
  libreadline-dev libncursesw5-dev xz-utils \
  libxml2-dev libxmlsec1-dev libffi-dev liblzma-dev

gisila_apply_install_env

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

# Node.js + pnpm are only needed to build the panel UI from source. The default
# install deploys the prebuilt backend/web/ assets, so we skip them unless the
# operator explicitly asked for a source rebuild (BUILD_FRONTEND=1). User apps
# get their own Node toolchain via fnm at deploy time — they do not depend on a
# system-wide Node installed here.
if [[ "$BUILD_FRONTEND" == "1" ]]; then
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

# ── 3. Check external PostgreSQL connectivity ────────────────────────────────
# PostgreSQL itself is not provisioned by this script (see header comment) —
# the database, role, and password must already exist on $DB_HOST. We only
# verify we can reach it so a misconfigured DB_* var fails fast, here, instead
# of deep inside the migration step below.
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

# ── 3b. Check external Redis connectivity ────────────────────────────────────
# Same idea, no extra package needed — /dev/tcp is a bash builtin.
echo "==> Checking Redis connectivity ($REDIS_HOST:$REDIS_PORT)"
if ! timeout 5 bash -c "exec 3<>/dev/tcp/$REDIS_HOST/$REDIS_PORT" 2>/dev/null; then
  echo "ERROR: could not open a TCP connection to Redis at $REDIS_HOST:$REDIS_PORT." >&2
  echo "       Install/start Redis yourself, then re-run with REDIS_URL, e.g.:" >&2
  echo "         sudo env REDIS_URL='redis://:SECRET@127.0.0.1:6379' bash \$0" >&2
  exit 1
fi
echo "    connected."

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

# ── 5. Frontend — deploy prebuilt assets (optionally rebuild) ────────────────
# The Dart API serves the panel UI directly from backend/web/. Those assets are
# committed to the repo, so by default we deploy them as-is — no Node/pnpm, no
# Vite build. To rebuild from source after changing the UI, run with
# BUILD_FRONTEND=1.  No separate Node.js server or systemd unit is needed.
if [[ "$BUILD_FRONTEND" == "1" ]]; then
  echo "==> Building panel UI from source (Vite → backend/web/)"
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
else
  echo "==> Using prebuilt panel UI in backend/web/ (set BUILD_FRONTEND=1 to rebuild)"
  if [[ ! -f "$REPO_DIR/backend/web/index.html" ]]; then
    echo "ERROR: no prebuilt UI found at $REPO_DIR/backend/web/index.html." >&2
    echo "       Commit the built assets, or re-run with BUILD_FRONTEND=1 to build" >&2
    echo "       from source (requires Node.js + pnpm)." >&2
    exit 1
  fi
fi

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
  # On upgrades the file already exists — ensure newer vars are present without
  # clobbering anything the operator has since customized.
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
  # Redis is the one connection that lives in .env rather than database.yaml
  # (which is rewritten on every run), so it is the one that would otherwise go
  # stale when an operator re-runs the installer to move to a different Redis.
  gisila_sync_redis_env /etc/gisila/.env
fi

# ── 9. /etc/gisila/database.yaml ──────────────────────────────────────────────
echo "==> Writing /etc/gisila/database.yaml"
# Detect the major version of the configured cluster (works for remote hosts
# too, unlike `sudo -u postgres`) so the panel can show its own backing
# database as a read-only "system" instance (server_version).
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
gisila_apply_panel_domain /etc/nginx/sites-available/gisila-panel
nginx -t
systemctl enable --now nginx
systemctl reload nginx
gisila_maybe_issue_tls

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
echo "  Panel superuser:  \$SUPERUSER_EMAIL (see /etc/gisila/.env)"
echo "  Studio/admin:    \$STUDIO_USERNAME (see /etc/gisila/.env)"
echo
if [[ -z "$PANEL_DOMAIN" ]]; then
  echo "  To set a domain (or re-run with PANEL_DOMAIN=… ISSUE_TLS=1):"
  echo "    Edit /etc/nginx/sites-available/gisila-panel → set server_name"
  echo "    certbot --nginx -d panel.your-domain.tld"
  echo
fi
