# =============================================================================
# Shared install env helpers for infra/install.sh and infra/install-prebuilt.sh.
#
# Preferred knobs (URLs + domain):
#   DATABASE_URL   postgresql://user:pass@host:5432/dbname?sslmode=require
#   REDIS_URL      redis://:pass@host:6379/0   (password optional)
#   PANEL_DOMAIN   panel.example.com           (injected into nginx vhost)
#   ISSUE_TLS=1    run certbot for PANEL_DOMAIN after nginx is installed
#   SKIP_OS_CHECK=1  allow non-Ubuntu/Debian hosts (unsupported; for testing)
#
# Discrete DB_*/REDIS_* vars still work and override fields from a URL when set
# explicitly in the environment before the installer runs.
#
# Supported host OS: Ubuntu 22.04+ and Debian 12+ (amd64/arm64). Prebuilt
# release tarballs are glibc Linux binaries — CI builds them on Ubuntu runners,
# but they install and run on Debian the same way.
# =============================================================================

# Read a single KEY=value from /etc/os-release without polluting the caller's
# environment. (Sourcing that file exports VERSION=… which would clobber the
# installer's release VERSION knob — e.g. Debian's VERSION="13 (trixie)".)
gisila_os_release_get() {
  local key="$1"
  local value
  value="$(awk -F= -v k="$key" '
    $1 == k {
      v = substr($0, index($0, "=") + 1)
      if (v ~ /^".*"$/) v = substr(v, 2, length(v) - 2)
      else if (v ~ /^'\''.*'\''$/) v = substr(v, 2, length(v) - 2)
      print v
      exit
    }
  ' /etc/os-release)"
  printf '%s' "$value"
}

# Require Ubuntu 22.04+ or Debian 12+. Uses /etc/os-release only (no lsb_release).
gisila_require_supported_os() {
  if [[ "${SKIP_OS_CHECK:-0}" == "1" ]]; then
    echo "==> SKIP_OS_CHECK=1 — skipping Ubuntu/Debian version check"
    return 0
  fi

  if [[ ! -r /etc/os-release ]]; then
    echo "ERROR: cannot detect OS (/etc/os-release missing)." >&2
    echo "       Gisila Panel supports Ubuntu 22.04+ and Debian 12+." >&2
    exit 1
  fi

  local id version_id pretty major
  id="$(gisila_os_release_get ID)"
  version_id="$(gisila_os_release_get VERSION_ID)"
  pretty="$(gisila_os_release_get PRETTY_NAME)"
  pretty="${pretty:-$id $version_id}"
  major="${version_id%%.*}"
  major="${major:-0}"

  case "$id" in
    ubuntu)
      if [[ "$major" =~ ^[0-9]+$ && "$major" -ge 22 ]]; then
        echo "==> Detected $pretty (supported)"
        return 0
      fi
      ;;
    debian)
      if [[ "$major" =~ ^[0-9]+$ && "$major" -ge 12 ]]; then
        echo "==> Detected $pretty (supported)"
        return 0
      fi
      ;;
  esac

  echo "ERROR: unsupported OS: $pretty" >&2
  echo "       Gisila Panel supports Ubuntu 22.04+ and Debian 12+ (x64 and arm64)." >&2
  echo "       Set SKIP_OS_CHECK=1 to bypass this check (unsupported)." >&2
  exit 1
}

# Parse DATABASE_URL into DB_HOST/PORT/NAME/USER/PASSWORD/SSL (only fills unset).
gisila_parse_database_url() {
  local url="${1:-}"
  [[ -n "$url" ]] || return 0
  command -v python3 >/dev/null 2>&1 || {
    echo "ERROR: python3 is required to parse DATABASE_URL" >&2
    exit 1
  }
  eval "$(DB_URL="$url" python3 - <<'PY'
import os, shlex, sys
from urllib.parse import urlparse, unquote, parse_qs

url = os.environ["DB_URL"]
u = urlparse(url)
if u.scheme not in ("postgres", "postgresql"):
    print(
        f"echo \"ERROR: DATABASE_URL must start with postgresql:// (got {u.scheme!r})\" >&2; exit 1",
        file=sys.stdout,
    )
    raise SystemExit(0)

host = u.hostname or "localhost"
port = str(u.port or 5432)
# path is "/dbname"
name = unquote((u.path or "/gisila_panel").lstrip("/")) or "gisila_panel"
user = unquote(u.username) if u.username else "gisila"
password = unquote(u.password) if u.password is not None else ""
qs = parse_qs(u.query or "")
sslmode = (qs.get("sslmode") or qs.get("ssl") or [""])[0].lower()
ssl = "true" if sslmode in ("require", "verify-ca", "verify-full", "true", "1", "yes") else "false"

def assign(name, value):
    # Only set if the caller has not already exported the discrete var.
    print(f'if [ -z "${{{name}+x}}" ]; then {name}={shlex.quote(value)}; fi')

assign("DB_HOST", host)
assign("DB_PORT", port)
assign("DB_NAME", name)
assign("DB_USER", user)
assign("DB_PASSWORD", password)
assign("DB_SSL", ssl)
PY
)"
}

# Parse REDIS_URL into REDIS_HOST/PORT/PASSWORD (only fills unset).
gisila_parse_redis_url() {
  local url="${1:-}"
  [[ -n "$url" ]] || return 0
  command -v python3 >/dev/null 2>&1 || {
    echo "ERROR: python3 is required to parse REDIS_URL" >&2
    exit 1
  }
  eval "$(REDIS_URL_IN="$url" python3 - <<'PY'
import os, shlex, sys
from urllib.parse import urlparse, unquote

url = os.environ["REDIS_URL_IN"]
u = urlparse(url)
if u.scheme not in ("redis", "rediss"):
    print(
        f"echo \"ERROR: REDIS_URL must start with redis:// (got {u.scheme!r})\" >&2; exit 1",
        file=sys.stdout,
    )
    raise SystemExit(0)

host = u.hostname or "127.0.0.1"
port = str(u.port or 6379)
password = unquote(u.password) if u.password is not None else ""

def assign(name, value):
    print(f'if [ -z "${{{name}+x}}" ]; then {name}={shlex.quote(value)}; fi')

assign("REDIS_HOST", host)
assign("REDIS_PORT", port)
assign("REDIS_PASSWORD", password)
PY
)"
}

# Apply URL knobs, then fill any remaining defaults.
gisila_apply_install_env() {
  if [[ -n "${DATABASE_URL:-}" ]]; then
    echo "==> Using DATABASE_URL for PostgreSQL"
    gisila_parse_database_url "$DATABASE_URL"
  fi
  if [[ -n "${REDIS_URL:-}" ]]; then
    echo "==> Using REDIS_URL for Redis"
    gisila_parse_redis_url "$REDIS_URL"
  fi

  : "${DB_HOST:=localhost}"
  : "${DB_PORT:=5432}"
  : "${DB_NAME:=gisila_panel}"
  : "${DB_USER:=gisila}"
  : "${DB_PASSWORD:=gisila}"
  : "${DB_SSL:=false}"

  : "${REDIS_HOST:=127.0.0.1}"
  : "${REDIS_PORT:=6379}"
  : "${REDIS_PASSWORD:=}"

  : "${PANEL_DOMAIN:=}"
  : "${ISSUE_TLS:=0}"

  export DB_HOST DB_PORT DB_NAME DB_USER DB_PASSWORD DB_SSL
  export REDIS_HOST REDIS_PORT REDIS_PASSWORD
  export PANEL_DOMAIN ISSUE_TLS
}

# Write PANEL_DOMAIN into the panel nginx vhost (replaces panel.example.com).
gisila_apply_panel_domain() {
  local conf="${1:-/etc/nginx/sites-available/gisila-panel}"
  local domain="${PANEL_DOMAIN:-}"
  [[ -n "$domain" ]] || return 0
  [[ -f "$conf" ]] || return 0
  echo "==> Setting panel domain: $domain"
  PANEL_DOMAIN="$domain" NGINX_CONF="$conf" python3 - <<'PY'
import os
from pathlib import Path
conf = Path(os.environ["NGINX_CONF"])
domain = os.environ["PANEL_DOMAIN"]
text = conf.read_text()
conf.write_text(text.replace("panel.example.com", domain))
PY
}

# Optionally issue a Let's Encrypt cert for PANEL_DOMAIN.
gisila_maybe_issue_tls() {
  local domain="${PANEL_DOMAIN:-}"
  [[ -n "$domain" && "${ISSUE_TLS:-0}" == "1" ]] || return 0
  echo "==> Issuing TLS certificate for $domain (certbot)"
  mkdir -p /var/www/letsencrypt
  if certbot --nginx -d "$domain" --non-interactive --agree-tos \
      --register-unsafely-without-email --redirect; then
    echo "    TLS ready for https://$domain"
  else
    echo "WARNING: certbot failed — DNS may not point here yet." >&2
    echo "         Re-run later: certbot --nginx -d $domain" >&2
  fi
}
