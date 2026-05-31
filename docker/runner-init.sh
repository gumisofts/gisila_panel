#!/bin/bash
# =============================================================================
# Gisila runner container initialisation.
#
# This script runs inside the privileged `runner` container on every start.
# It installs required host tools (once), seeds supervisord, and then hands
# off to the Dart background worker.
# =============================================================================
set -euo pipefail

# ── 1. Install host tools (idempotent) ─────────────────────────────────────
if ! command -v git >/dev/null 2>&1 || ! command -v supervisord >/dev/null 2>&1; then
  echo "[runner] Installing system tools…"
  apt-get update -qq
  DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
    git \
    curl \
    ca-certificates \
    build-essential \
    unzip \
    supervisor \
    nginx \
    openssh-client \
    passwd \
    adduser \
    util-linux \
    procps \
    python3 \
    python3-venv \
    python3-pip
fi

# ── 2. Persist dart's PATH for all users (login shells via runuser) ──────────
# dart:stable sets PATH via Docker ENV, not /etc/environment, so login shells
# started with `runuser -u <user> -- bash -lc` would miss the dart binary.
DART_BIN_DIR=/usr/lib/dart/bin
if [ -d "$DART_BIN_DIR" ] && ! grep -q "$DART_BIN_DIR" /etc/environment 2>/dev/null; then
  echo "PATH=\"$DART_BIN_DIR:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin\"" > /etc/environment
fi

# ── 3. Set up directories ────────────────────────────────────────────────────
mkdir -p /srv/apps
mkdir -p /etc/supervisor/conf.d
mkdir -p /var/log/supervisor
mkdir -p /etc/nginx/conf.d
mkdir -p /run/nginx

# ── 4. Write supervisord base config (if not already present) ───────────────
if [ ! -f /etc/supervisor/supervisord.conf ]; then
cat > /etc/supervisor/supervisord.conf <<'SUPERVISORD'
[supervisord]
nodaemon=false
logfile=/var/log/supervisor/supervisord.log
logfile_maxbytes=10MB
logfile_backups=3
loglevel=info
pidfile=/var/run/supervisord.pid

[unix_http_server]
file=/var/run/supervisor.sock
chmod=0700

[rpcinterface:supervisor]
supervisor.rpcinterface_factory = supervisor.rpcinterface:make_main_rpcinterface

[supervisorctl]
serverurl=unix:///var/run/supervisor.sock

[include]
files=/etc/supervisor/conf.d/*.conf
SUPERVISORD
fi

# ── 5. Write nginx base config ───────────────────────────────────────────────
cat > /etc/nginx/nginx.conf <<'NGINX'
user www-data;
worker_processes auto;
pid /run/nginx.pid;
error_log /var/log/nginx/error.log;

events {
    worker_connections 1024;
}

http {
    include mime.types;
    default_type application/octet-stream;
    sendfile on;
    keepalive_timeout 65;
    access_log /var/log/nginx/access.log;

    # Include per-app vhosts written by gisila-agent.
    include /etc/nginx/conf.d/*.conf;
}
NGINX

mkdir -p /var/log/nginx /var/lib/nginx/body

# ── 6. Start nginx (background) ─────────────────────────────────────────────
if ! pgrep -x nginx >/dev/null 2>&1; then
  nginx -t && nginx
fi

# ── 7. Start supervisord (background) ───────────────────────────────────────
if ! pgrep -x supervisord >/dev/null 2>&1; then
  supervisord -c /etc/supervisor/supervisord.conf
fi

# ── 8. Run dart pub get for agent (so the worker can `dart run` it) ────────
echo "[runner] dart pub get for gisila-agent…"
cd /workspace/gisila-panel/agent
dart pub get

echo "[runner] dart pub get for backend…"
cd /workspace/gisila-panel/backend
dart pub get

echo "[runner] Ready. Starting Dart worker…"

# ── 9. Start the Dart background worker ─────────────────────────────────────
exec dart run bin/worker.dart
