#!/usr/bin/env bash
# =============================================================================
# Gisila Panel — release builder.
#
# Produces a self-contained prebuilt release tarball:
#
#   dist/gisila-release-linux-<arch>.tar.gz
#
# containing the compiled binaries, the built panel UI, the SQL migrations and
# the infra assets. New devs / operators never run this — they run
# infra/install-prebuilt.sh, which downloads the tarball from GitHub Releases.
#
# Run this on a BUILD host that has the full toolchain (Dart SDK, Node.js,
# pnpm) — a maintainer machine or CI. Example end-to-end publish:
#
#   bash infra/build-release.sh
#   gh release create v"$(cat dist/VERSION)" \
#     dist/gisila-release-linux-*.tar.gz \
#     --repo gumisofts/gisila_panel
#
# Env knobs:
#   VERSION=...            override the version stamp (default: backend pubspec)
#   SKIP_FRONTEND_BUILD=1  reuse the committed backend/web/ instead of rebuilding
# =============================================================================
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="${VERSION:-$(grep -m1 '^version:' "$REPO_DIR/backend/pubspec.yaml" | awk '{print $2}')}"

ARCH="$(uname -m)"
case "$ARCH" in
  x86_64 | amd64) ARCH=x64 ;;
  aarch64 | arm64) ARCH=arm64 ;;
  *) echo "WARN: unrecognised arch '$ARCH' — tarball will be tagged as-is" >&2 ;;
esac

PKG="gisila-release"                       # top-level dir inside the tarball
OUT_DIR="$REPO_DIR/dist"
TARBALL="$OUT_DIR/${PKG}-linux-${ARCH}.tar.gz"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

# Required build tooling.
for tool in dart node pnpm; do
  command -v "$tool" >/dev/null 2>&1 \
    || { echo "ERROR: '$tool' not found on PATH (this is the build host)" >&2; exit 1; }
done

echo "==> Building Gisila Panel release $VERSION (linux-$ARCH)"

# ── Backend binaries ──────────────────────────────────────────────────────────
echo "==> Compiling backend binaries (server, worker, migrate)"
cd "$REPO_DIR/backend"
dart pub get
dart run build_runner build --delete-conflicting-outputs
mkdir -p "$REPO_DIR/backend/build"
dart compile exe bin/server.dart  -o "$REPO_DIR/backend/build/gisila-panel"
dart compile exe bin/worker.dart  -o "$REPO_DIR/backend/build/gisila-worker"
dart compile exe bin/migrate.dart -o "$REPO_DIR/backend/build/gisila-migrate"

# ── Agent binary ────────────────────────────────────────────────────────────
echo "==> Compiling gisila-agent"
cd "$REPO_DIR/agent"
dart pub get
mkdir -p "$REPO_DIR/agent/build"
dart compile exe bin/gisila-agent.dart -o "$REPO_DIR/agent/build/gisila-agent"

# ── Frontend ──────────────────────────────────────────────────────────────────
if [[ "${SKIP_FRONTEND_BUILD:-0}" == "1" ]]; then
  echo "==> Reusing committed panel UI in backend/web/ (SKIP_FRONTEND_BUILD=1)"
else
  echo "==> Building panel UI (Vite → backend/web/)"
  # pnpm / corepack hardening — see infra/install.sh for the rationale.
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
fi
[[ -f "$REPO_DIR/backend/web/index.html" ]] \
  || { echo "ERROR: no panel UI at backend/web/index.html" >&2; exit 1; }

# ── Stage the tarball tree ────────────────────────────────────────────────────
echo "==> Staging $PKG"
mkdir -p "$STAGE/$PKG/bin" "$STAGE/$PKG/web" "$STAGE/$PKG/migrations" "$STAGE/$PKG/infra"

install -m 0755 "$REPO_DIR/backend/build/gisila-panel"   "$STAGE/$PKG/bin/"
install -m 0755 "$REPO_DIR/backend/build/gisila-worker"  "$STAGE/$PKG/bin/"
install -m 0755 "$REPO_DIR/backend/build/gisila-migrate" "$STAGE/$PKG/bin/"
install -m 0755 "$REPO_DIR/agent/build/gisila-agent"     "$STAGE/$PKG/bin/"

cp -a "$REPO_DIR/backend/web/."            "$STAGE/$PKG/web/"
cp -a "$REPO_DIR/backend/lib/migrations/." "$STAGE/$PKG/migrations/"

install -m 0644 "$REPO_DIR/infra/gisila-panel.service"  "$STAGE/$PKG/infra/"
install -m 0644 "$REPO_DIR/infra/gisila-worker.service" "$STAGE/$PKG/infra/"
install -m 0644 "$REPO_DIR/infra/gisila-apps.target"    "$STAGE/$PKG/infra/"
install -m 0644 "$REPO_DIR/infra/nginx-panel.conf"      "$STAGE/$PKG/infra/"

echo "$VERSION" > "$STAGE/$PKG/VERSION"

# ── Pack ──────────────────────────────────────────────────────────────────────
mkdir -p "$OUT_DIR"
tar -C "$STAGE" -czf "$TARBALL" "$PKG"
echo "$VERSION" > "$OUT_DIR/VERSION"

echo
echo "✓ Built $TARBALL ($(du -h "$TARBALL" | awk '{print $1}'))"
echo
echo "  Publish it to a GitHub Release so install-prebuilt.sh can fetch it:"
echo "    gh release create v$VERSION \"$TARBALL\" --repo gumisofts/gisila_panel"
echo
echo "  (Re-uploading the same asset name to the 'latest' release keeps the"
echo "   'VERSION=latest' install path working.)"
echo
