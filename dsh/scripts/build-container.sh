#!/usr/bin/env bash
# dsh/scripts/build-container.sh — build the dsh image with the native Apple
# `container` tool. Mirrors scripts/build-container.sh at the repo root,
# scoped to the dsh image.

set -euo pipefail

# Resolve paths relative to this script: SCRIPT_DIR is dsh/scripts/,
# DSH_DIR the dsh/ directory (the build context).
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DSH_DIR="$(dirname "$SCRIPT_DIR")"

IMAGE_TAG="${DSH_IMAGE:-dsh:latest}"
DSH_VERSION="${DSH_VERSION:-0.1.0-rc.6}"

echo "==> Build context: ${DSH_DIR}"
echo "==> Building image: ${IMAGE_TAG} (DSH_VERSION=${DSH_VERSION})..."

# Use dsh/ as the build context and its Containerfile, so the script works
# regardless of the directory it is invoked from.
container build \
  --tag "${IMAGE_TAG}" \
  --file "${DSH_DIR}/Containerfile" \
  --build-arg DSH_VERSION="${DSH_VERSION}" \
  "${DSH_DIR}"

echo "==> Build complete: ${IMAGE_TAG}"
echo "==> Start it with: ${SCRIPT_DIR}/start-container.sh"