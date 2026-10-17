#!/usr/bin/env bash
# Print the `dart compile exe` flags that stamp a build with its version, so
# the panel can show what is running (System → About, /system/info).
#
#   dart compile exe $(bash infra/build-defines.sh) bin/server.dart -o …
#
# VERSION / COMMIT override what git reports — build-release.sh passes the
# release version; a tarball with no .git falls back to "unknown".
set -euo pipefail
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# safe.directory: install.sh runs this as root on a checkout another user owns.
git_() { git -c safe.directory="$REPO_DIR" -C "$REPO_DIR" "$@" 2>/dev/null; }

version="${VERSION:-$(git_ describe --tags --always --dirty || echo unknown)}"
commit="${COMMIT:-$(git_ rev-parse --short=12 HEAD || echo unknown)}"
built_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

echo "--define=GISILA_VERSION=$version --define=GISILA_COMMIT=$commit --define=GISILA_BUILT_AT=$built_at"
