#!/usr/bin/env bash
#
# Regenerate go.mod.yml + modules.txt for the Flatpak manifest.
#
# Unlike the previous version (which vendored from a local ~/test/go2tv checkout
# that could drift from the pinned revision), this inspects the manifest, reads
# the exact git commit the Flatpak build uses, fetches *that* revision from the
# remote, and generates the vendored dependency files from it. This guarantees
# the local deps match the ones the remote build will actually compile.
#
# Usage:
#   ./update_modules.sh            # use url+commit from the manifest
#   ./update_modules.sh <ref>      # override commit/tag/branch (e.g. when bumping)
#
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
manifest="$script_dir/app.go2tv.go2tv.yml"

[ -f "$manifest" ] || { echo "manifest not found: $manifest" >&2; exit 1; }

# Extract url + commit from the `go2tv` module's git source.
# (No yq dependency; awk scopes the source block to the named module.)
url="$(awk '
  /^  - name:/ {app=($3 == "go2tv"); g=0}
  app && /type:[[:space:]]*git/ {g=1}
  g && /^[[:space:]]*url:/ {sub(/^[[:space:]]*url:[[:space:]]*/,""); gsub(/"/,""); print; exit}
' "$manifest")"

commit="${1:-$(awk '
  /^  - name:/ {app=($3 == "go2tv"); g=0}
  app && /type:[[:space:]]*git/ {g=1}
  g && /^[[:space:]]*commit:/ {sub(/^[[:space:]]*commit:[[:space:]]*/,""); gsub(/"/,""); print; exit}
' "$manifest")}"

[ -n "$url" ]    || { echo "could not parse git url from manifest" >&2; exit 1; }
[ -n "$commit" ] || { echo "could not parse commit from manifest" >&2; exit 1; }

echo "Manifest source : $url"
echo "Revision        : $commit"

# Temp checkout MUST be on the same filesystem as $script_dir: flatpak-go-mod
# does os.Rename(<src>/vendor/modules.txt, <out>/modules.txt), which fails
# across filesystems (EXDEV). Creating it under $script_dir keeps them together.
src="$(mktemp -d "$script_dir/.go2tv-src.XXXXXX")"
trap 'rm -rf "$src"' EXIT

echo "Fetching revision into $src ..."
git init -q "$src"
git -C "$src" remote add origin "$url"
# GitHub allows fetching a reachable commit by SHA directly (shallow).
git -C "$src" fetch -q --depth 1 origin "$commit"
git -C "$src" checkout -q FETCH_HEAD

[ -f "$src/go.mod" ] || { echo "selected source has no go.mod: $url at $commit" >&2; exit 1; }

echo "Generating go.mod.yml + modules.txt ..."
# GOWORK=off: this repo lives under ~/test which has a parent go.work.
# Without this, Go enters workspace mode and flatpak-go-mod's internal
# `go mod vendor` fails with "cannot be run in workspace mode".
GOWORK=off go run github.com/dennwc/flatpak-go-mod@latest -out "$script_dir" "$src"

echo "Done. Regenerated:"
echo "  $script_dir/go.mod.yml"
echo "  $script_dir/modules.txt"
