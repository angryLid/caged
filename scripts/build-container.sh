#!/usr/bin/env bash
# scripts/build-container.sh — build the caged image with the native Apple container tool

set -euo pipefail

# Resolve paths relative to this script: SCRIPT_DIR is scripts/, ROOT_DIR the project root.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

IMAGE_TAG="${CAGED_IMAGE:-caged:latest}"
PI_VERSION="${PI_VERSION:-0.84.2}"

echo "==> Project Root: ${ROOT_DIR}"
echo "==> Building image: ${IMAGE_TAG} (PI_VERSION=${PI_VERSION})..."

# Use the project root as the build context and an absolute Containerfile path,
# so the script works regardless of the directory it is invoked from.
container build \
  --tag "${IMAGE_TAG}" \
  --file "${ROOT_DIR}/Containerfile" \
  --build-arg PI_VERSION="${PI_VERSION}" \
  "${ROOT_DIR}"

echo "==> Build complete: ${IMAGE_TAG}"