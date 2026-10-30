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
username = unquote(u.username) if u.username else ""
tls = "true" if u.scheme == "rediss" else "false"

def assign(name, value):
    print(f'if [ -z "${{{name}+x}}" ]; then {name}={shlex.quote(value)}; fi')

assign("REDIS_HOST", host)
assign("REDIS_PORT", port)
assign("REDIS_PASSWORD", password)
assign("REDIS_USERNAME", username)
assign("REDIS_TLS", tls)
PY
)"
}

# Apply URL knobs, then fill any remaining defaults.
gisila_apply_install_env() {
  # Did the operator actually name a Redis on this run, or are we about to fall
  # back to the localhost default? Upgrades keep the existing /etc/gisila/.env,
  # so without this an operator moving to an external Redis would re-run the
  # installer and silently stay pointed at the old one. Must be read before the
  # URL parsers and defaults below fill these in.
  if [[ -n "${REDIS_URL:-}${REDIS_HOST:-}${REDIS_PORT:-}${REDIS_PASSWORD:-}${REDIS_USERNAME:-}${REDIS_TLS:-}" ]]; then
    GISILA_REDIS_EXPLICIT=1
  else
    GISILA_REDIS_EXPLICIT=0
  fi
  export GISILA_REDIS_EXPLICIT

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
  # No default password: a well-known one is refused by
  # gisila_check_connection_security, so the operator must supply their own.
  : "${DB_PASSWORD:=}"
  : "${DB_SSL:=false}"

  # Upgrades keep Redis settings in /etc/gisila/.env; check and connect with
  # those rather than the localhost defaults below.
  if [[ "$GISILA_REDIS_EXPLICIT" == "0" && -f /etc/gisila/.env ]]; then
    local key
    for key in REDIS_HOST REDIS_PORT REDIS_PASSWORD REDIS_USERNAME REDIS_TLS; do
      if grep -q "^${key}=" /etc/gisila/.env; then
        printf -v "$key" '%s' "$(grep -m1 "^${key}=" /etc/gisila/.env | cut -d= -f2-)"
      fi
    done
  fi

  : "${REDIS_HOST:=127.0.0.1}"
  : "${REDIS_PORT:=6379}"
  : "${REDIS_PASSWORD:=}"
  : "${REDIS_USERNAME:=}"
  : "${REDIS_TLS:=false}"

  : "${PANEL_DOMAIN:=}"
  : "${ISSUE_TLS:=0}"

  export DB_HOST DB_PORT DB_NAME DB_USER DB_PASSWORD DB_SSL
  export REDIS_HOST REDIS_PORT REDIS_PASSWORD REDIS_USERNAME REDIS_TLS
  export PANEL_DOMAIN ISSUE_TLS
}

# Set KEY=value in an env file, replacing any existing line for KEY. Rewrites
# through the original inode so the file keeps its owner and 0640 mode.
gisila_set_env_var() {
  local file="$1" key="$2" value="$3" tmp
  tmp="$(mktemp)"
  if [[ -f "$file" ]]; then
    # grep exits 1 when nothing survives the filter, which is a normal outcome
    # here and must not trip the installer's `set -e`.
    grep -v "^${key}=" "$file" > "$tmp" || true
  fi
  printf '%s=%s\n' "$key" "$value" >> "$tmp"
  cat "$tmp" > "$file"
  rm -f "$tmp"
}

# Refresh the REDIS_* keys of an existing env file when the operator passed
# Redis details explicitly (see GISILA_REDIS_EXPLICIT above). Called on the
# upgrade path, where the env file is otherwise left untouched.
gisila_sync_redis_env() {
  local file="${1:-/etc/gisila/.env}"
  [[ "${GISILA_REDIS_EXPLICIT:-0}" == "1" ]] || return 0
  gisila_set_env_var "$file" REDIS_HOST "$REDIS_HOST"
  gisila_set_env_var "$file" REDIS_PORT "$REDIS_PORT"
  gisila_set_env_var "$file" REDIS_PASSWORD "$REDIS_PASSWORD"
  gisila_set_env_var "$file" REDIS_USERNAME "$REDIS_USERNAME"
  gisila_set_env_var "$file" REDIS_TLS "$REDIS_TLS"
  echo "    updated REDIS_* → $REDIS_HOST:$REDIS_PORT (tls=$REDIS_TLS)"
}

# Classify where HOST lives: loopback | private | public. A name is private
# only when every address it resolves to is (RFC 1918, ULA, link-local, CGNAT).
gisila_host_scope() {
  HOST_IN="$1" python3 - <<'PY'
import ipaddress, os, socket
host = os.environ["HOST_IN"]
try:
    addrs = {ai[4][0] for ai in socket.getaddrinfo(host, None)}
except OSError:
    addrs = set()
ips = [ipaddress.ip_address(a.split("%")[0]) for a in addrs]
if ips and all(ip.is_loopback for ip in ips):
    print("loopback")
elif ips and all(ip.is_loopback or ip.is_private or ip.is_link_local
                 or ip in ipaddress.ip_network("100.64.0.0/10") for ip in ips):
    print("private")
else:
    print("public")
PY
}

# Whether something listens on PORT on a non-loopback address of this host.
gisila_port_listens_publicly() {
  command -v ss >/dev/null 2>&1 || return 1
  ss -ltnH "sport = :$1" 2>/dev/null | awk '{print $4}' \
    | grep -qvE '^(127\.[0-9.]+|\[::1\]|::1):'
}

# Refuse Postgres/Redis settings that would leave either open to the apps this
# host runs or to the network. Both may live anywhere (this host, the LAN, a
# managed provider); only the unsafe combinations are refused. Hosted apps
# share this machine's loopback, so 127.0.0.1 is not private from them.
# GISILA_ALLOW_INSECURE=1 downgrades refusals to warnings (test machines only).
gisila_check_connection_security() {
  local problems=() warnings=() scope weak
  weak=' gisila postgres password admin root changeme secret redis 123456 12345678 '

  # PostgreSQL
  if [[ -z "$DB_PASSWORD" ]]; then
    problems+=("PostgreSQL: no password set. Pass DATABASE_URL with the gisila role's password.")
  elif [[ "$weak" == *" ${DB_PASSWORD,,} "* || ${#DB_PASSWORD} -lt 12 ]]; then
    problems+=("PostgreSQL: the password for '$DB_USER' is a well-known value or shorter than 12 characters. Hosted apps share this machine and could log in with it. Set a strong one: ALTER ROLE $DB_USER PASSWORD '<new>';")
  fi
  scope="$(gisila_host_scope "$DB_HOST")"
  if [[ "$scope" != "loopback" && "$DB_SSL" != "true" ]]; then
    if [[ "$scope" == "public" ]]; then
      problems+=("PostgreSQL at $DB_HOST is reached over the internet without TLS. Add ?sslmode=require to DATABASE_URL.")
    else
      warnings+=("PostgreSQL at $DB_HOST (private network) is reached without TLS; credentials cross the LAN in plain text.")
    fi
  fi
  if [[ "$scope" == "loopback" ]] && gisila_port_listens_publicly "$DB_PORT"; then
    warnings+=("PostgreSQL on this host listens on a public interface (port $DB_PORT). Bind it to 127.0.0.1 or firewall the port.")
  fi

  # Redis
  if [[ -z "$REDIS_PASSWORD" ]]; then
    problems+=("Redis: no password set. Every app on this host can reach 127.0.0.1, so an open Redis lets any of them read and inject panel jobs. Set requirepass and pass REDIS_URL='redis://:<password>@$REDIS_HOST:$REDIS_PORT'.")
  elif [[ "$weak" == *" ${REDIS_PASSWORD,,} "* || ${#REDIS_PASSWORD} -lt 16 ]]; then
    problems+=("Redis: the password is a well-known value or shorter than 16 characters. Use a long random one (openssl rand -hex 24).")
  fi
  scope="$(gisila_host_scope "$REDIS_HOST")"
  if [[ "$scope" != "loopback" && "$REDIS_TLS" != "true" ]]; then
    if [[ "$scope" == "public" ]]; then
      problems+=("Redis at $REDIS_HOST is reached over the internet without TLS. Use a rediss:// URL.")
    else
      warnings+=("Redis at $REDIS_HOST (private network) is reached without TLS; the password crosses the LAN in plain text.")
    fi
  fi
  if [[ "$scope" == "loopback" ]] && gisila_port_listens_publicly "$REDIS_PORT"; then
    warnings+=("Redis on this host listens on a public interface (port $REDIS_PORT). Bind it to 127.0.0.1 or firewall the port.")
  fi

  local w p
  for w in "${warnings[@]}"; do echo "WARNING: $w" >&2; done
  ((${#problems[@]} == 0)) && return 0
  for p in "${problems[@]}"; do echo "ERROR: $p" >&2; done
  if [[ "${GISILA_ALLOW_INSECURE:-0}" == "1" ]]; then
    echo "WARNING: GISILA_ALLOW_INSECURE=1 — continuing anyway. Never use this on a host that runs other people's apps." >&2
    return 0
  fi
  echo "Refusing to install with an insecure database or Redis configuration (see above)." >&2
  exit 1
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

# Download (or copy RELEASE_FILE), verify and unpack a prebuilt release into
# the directory $1, and set SRC to the unpacked tree. Uses VERSION,
# GITHUB_REPO, ASSET, RELEASE_URL and RELEASE_FILE. Shared by
# install-prebuilt.sh and upgrade.sh.
gisila_fetch_release() {
  local STAGE="$1"

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

  # Check the download against the checksum published next to it. Releases
  # from before checksums were published have none: warn and go on.
  if [[ -z "${RELEASE_FILE:-}" ]]; then
    if curl -fsSL "$URL.sha256" -o "$STAGE/release.sha256" 2>/dev/null; then
      EXPECTED="$(awk '{print $1}' "$STAGE/release.sha256")"
      ACTUAL="$(sha256sum "$STAGE/release.tar.gz" | awk '{print $1}')"
      if [[ ! "$EXPECTED" =~ ^[0-9a-f]{64}$ || "$EXPECTED" != "$ACTUAL" ]]; then
        echo "ERROR: checksum mismatch for $URL" >&2
        echo "       expected $EXPECTED, got $ACTUAL. Not installing it." >&2
        exit 1
      fi
      echo "    checksum OK ($ACTUAL)"
    else
      echo "    WARNING: no $URL.sha256 published; installing without a checksum check" >&2
    fi
  fi

  tar -C "$STAGE" -xzf "$STAGE/release.tar.gz"
  SRC="$(find "$STAGE" -maxdepth 1 -type d -name 'gisila-release*' | head -1)"
  if [[ -z "$SRC" || ! -x "$SRC/bin/gisila-panel" ]]; then
    echo "ERROR: release archive is missing bin/gisila-panel — wrong/corrupt asset?" >&2
    exit 1
  fi
  echo "    release version: $(cat "$SRC/VERSION" 2>/dev/null || echo unknown)"
}
