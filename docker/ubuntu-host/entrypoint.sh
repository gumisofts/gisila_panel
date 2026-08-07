#!/usr/bin/env bash
# Boot helper for the Ubuntu install-host container.
#
# Must exec systemd as PID 1 immediately — do not block on workspace chown.
set -euo pipefail

log() { echo "[gisila-host] $*"; }

# Make sudo usable in non-interactive agent/worker invocations.
if [[ ! -f /etc/sudoers.d/ubuntu ]]; then
  echo 'ubuntu ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/ubuntu
  chmod 0440 /etc/sudoers.d/ubuntu
fi

# Background housekeeping + optional AUTO_INSTALL (never block PID 1).
(
  # Light ownership fix for the panel tree only (not the whole monorepo).
  if [[ -d /workspace/gisila-panel ]]; then
    chown -R ubuntu:ubuntu /workspace/gisila-panel 2>/dev/null || true
  fi

  for _ in $(seq 1 90); do
    if systemctl is-system-running 2>/dev/null | grep -Eq 'running|degraded'; then
      break
    fi
    sleep 1
  done

  # Ensure sshd is up for outside-Docker access.
  systemctl enable --now ssh 2>/dev/null || systemctl enable --now sshd 2>/dev/null || true

  if [[ "${AUTO_INSTALL:-0}" == "1" ]]; then
    log "AUTO_INSTALL=1 — running infra/install.sh via sudo as ubuntu"
    export DATABASE_URL="${DATABASE_URL:-postgresql://postgres:postgres@pg:5432/gisila_panel}"
    export REDIS_URL="${REDIS_URL:-redis://redis:6379}"
    export PANEL_DOMAIN="${PANEL_DOMAIN:-localhost}"
    unset DOCKER_DEPLOY || true
    cd /workspace/gisila-panel
    sudo --preserve-env=DATABASE_URL,REDIS_URL,PANEL_DOMAIN,BUILD_FRONTEND,ISSUE_TLS \
      -u root bash infra/install.sh \
      || log "install.sh failed — shell into the container and re-run manually"
  else
    log "Ready. From the Docker host:"
    log "  ./scripts/install-env.sh install"
    log "  ssh -p 12222 ubuntu@localhost   # password: ubuntu"
    log "  http://localhost:8001           # after install"
  fi
) &

exec "$@"
