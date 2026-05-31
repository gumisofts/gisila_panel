#!/usr/bin/env bash
# Tear down a gisila-panel install. Apps remain running unless --apps is set.
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
  echo "Please run as root" >&2; exit 1
fi

systemctl stop gisila-panel.service gisila-worker.service gisila-ui.service 2>/dev/null || true
systemctl disable gisila-panel.service gisila-worker.service gisila-ui.service 2>/dev/null || true
rm -f /etc/systemd/system/gisila-panel.service \
      /etc/systemd/system/gisila-worker.service \
      /etc/systemd/system/gisila-ui.service \
      /etc/systemd/system/gisila-apps.target
systemctl daemon-reload

if [[ "${1:-}" == "--apps" ]]; then
  for unit in /etc/systemd/system/gisila-app_*.service; do
    [[ -e "$unit" ]] || continue
    name=$(basename "$unit" .service)
    systemctl stop "$name" || true
    systemctl disable "$name" || true
    rm -f "$unit"
  done
  rm -rf /srv/apps
  systemctl daemon-reload
fi

rm -f /etc/sudoers.d/gisila
rm -f /usr/local/bin/gisila-panel /usr/local/bin/gisila-worker /usr/local/bin/gisila-agent
rm -f /etc/nginx/sites-enabled/gisila-panel /etc/nginx/sites-available/gisila-panel
systemctl reload nginx 2>/dev/null || true

echo "✓ gisila-panel uninstalled. /etc/gisila and /srv/gisila kept for safety."
