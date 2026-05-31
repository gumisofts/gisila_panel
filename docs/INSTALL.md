# Production install

## Single-node, Ubuntu 22.04+

```bash
git clone https://github.com/your-org/gisila-panel.git
cd gisila-panel
sudo bash infra/install.sh
```

This installs all dependencies, compiles the panel + agent to native
binaries, creates the `gisila` system user, sets up systemd, writes the
sudoers rule, runs migrations, and configures Nginx.

When the script finishes:

```
✓ Gisila Panel installed.
  API:     http://127.0.0.1:8000/docs
  Admin:   http://127.0.0.1:8000/admin
```

## Wire your domain

1. Point a DNS A record at the box: `panel.your-domain.tld → <ip>`.
2. Edit the nginx vhost:
   ```bash
   sudo sed -i 's/panel\.example\.com/panel.your-domain.tld/' \
     /etc/nginx/sites-available/gisila-panel
   sudo nginx -t && sudo systemctl reload nginx
   ```
3. Issue a certificate:
   ```bash
   sudo certbot --nginx -d panel.your-domain.tld
   ```

## Configuration

`/etc/gisila/.env` controls runtime behaviour:

| Variable | Purpose |
|---|---|
| `PORT` | API HTTP port (default 8000). |
| `JWT_SECRET` | HMAC secret. Rotate by editing + `systemctl restart gisila-panel`. |
| `JWT_EXPIRE_DAYS` | JWT lifetime. |
| `STUDIO_USERNAME` / `STUDIO_PASSWORD` | Credentials for `/admin`. |
| `REDIS_HOST` / `REDIS_PORT` | Redis connection. |
| `APPS_ROOT` | Where per-app filesystems live (default `/srv/apps`). |
| `APP_PORT_RANGE_MIN/MAX` | Internal port pool for new apps. |
| `AGENT_BIN` | Path to the privileged agent binary. |
| `NODE_ID` | Used when you scale beyond a single host. |

`/etc/gisila/database.yaml` points at the Postgres instance. Both files
are owned `gisila:gisila`, mode `0640`.

## Logs

```bash
journalctl -fu gisila-panel
journalctl -fu gisila-worker
journalctl -fu gisila-app_xxx     # any user app
```

## Updating

```bash
cd /opt/gisila-panel    # wherever you cloned
git pull
sudo bash infra/install.sh   # re-running is safe; binaries are replaced atomically
```

## Uninstall

```bash
sudo bash infra/uninstall.sh         # leaves apps running
sudo bash infra/uninstall.sh --apps  # also removes every user app and /srv/apps
```
