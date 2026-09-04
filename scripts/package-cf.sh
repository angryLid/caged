#!/usr/bin/env bash
# scripts/package-cf.sh — package the `cf` Confluence reader into a tarball
# (packages/cf/dist/cf-<version>.tgz) ON THE HOST, outside any Dockerfile.
#
# The Containerfile then only has to COPY the tarball in and run
# `npm install -g` — no registry access at image build time: the three runtime
# deps (turndown, turndown-plugin-gfm, domino) are declared as
# bundledDependencies in packages/cf/package.json, so npm pack bakes their
# node_modules into the tarball and the global install resolves them offline.
#
# Packing on the host mirrors the skill-source clones in
# scripts/build-caged-base.sh: anything that touches a registry happens here,
# not in the image build.
#
# Skip with CAGED_SKIP_CF_PACKAGE=1 to reuse the existing tarball (offline
# rebuilds), mirroring CAGED_SKIP_SKILLS_SYNC.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

SRC="$ROOT_DIR/packages/cf"
DIST="$SRC/dist"

if [ "${CAGED_SKIP_CF_PACKAGE:-0}" = "1" ]; then
  if ls "$DIST"/*.tgz >/dev/null 2>&1; then
    echo "==> CAGED_SKIP_CF_PACKAGE=1 — reusing $(ls "$DIST"/*.tgz | head -n1)"
    exit 0
  fi
  echo "Error: CAGED_SKIP_CF_PACKAGE=1 but no tarball found in $DIST." >&2
  echo "Run 'scripts/package-cf.sh' once on the host to create it." >&2
  exit 1
fi

if ! command -v node >/dev/null 2>&1; then
  echo "Error: node not found on the host — needed to pack cf (npm ci + npm pack)." >&2
  echo "Install Node.js, or skip the step with CAGED_SKIP_CF_PACKAGE=1." >&2
  exit 1
fi

echo "==> Packaging cf into $DIST ..."
NPM_CACHE="$(mktemp -d)"
trap 'rm -rf "$NPM_CACHE"' EXIT

# 1. Locked deps in the source tree (bundledDependencies must be installed to
#    be packed). --omit=dev keeps the tarball to runtime deps only.
( cd "$SRC" && npm ci --omit=dev --no-audit --no-fund --cache "$NPM_CACHE" )

# 2. Pack: bakes node_modules for the bundled deps into cf-<version>.tgz.
rm -rf "$DIST"
mkdir -p "$DIST"
( cd "$SRC" && npm pack --pack-destination "$DIST" --silent )

# npm pack names a scoped package tarball after the un-scoped name
# (@caged/cf -> caged-cf-<version>.tgz); the dist dir holds exactly one.
TARBALL="$(ls "$DIST"/*.tgz | head -n1)"
echo "==> cf packaged: $TARBALL"
echo "    (bundled deps in tarball: $(tar -tzf "$TARBALL" | grep -c 'package/node_modules/') entries)"