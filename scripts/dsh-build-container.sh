#!/usr/bin/env bash
# scripts/dsh-build-container.sh — build the dsh image with the native Apple
# `container` tool. The dsh counterpart of scripts/build-container.sh (pi):
# same pattern and hardening posture, scoped to the dsh image.

set -euo pipefail

# Resolve paths relative to this script: SCRIPT_DIR is scripts/, DSH_DIR the
# repo root (the build context, shared with the pi image).
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DSH_DIR="$(dirname "$SCRIPT_DIR")"

IMAGE_TAG="${DSH_IMAGE:-dsh:latest}"
DSH_VERSION="${DSH_VERSION:-0.1.0-rc.6}"

echo "==> Build context: ${DSH_DIR}"
echo "==> Building image: ${IMAGE_TAG} (DSH_VERSION=${DSH_VERSION})..."

# Use the repo root as the build context and Containerfile.dsh, so the
# script works regardless of the directory it is invoked from.
container build \
  --tag "${IMAGE_TAG}" \
  --file "${DSH_DIR}/Containerfile.dsh" \
  --build-arg DSH_VERSION="${DSH_VERSION}" \
  "${DSH_DIR}"

echo "==> Build complete: ${IMAGE_TAG}"
echo "==> Start it with: ${SCRIPT_DIR}/dsh-start-container.sh"