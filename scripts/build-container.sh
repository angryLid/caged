#!/usr/bin/env bash
# scripts/build-container.sh — build a caged image with the native Apple
# `container` tool.
#
# Usage:
#   scripts/build-container.sh pi    # the pi agent image (./Containerfile)
#   scripts/build-container.sh dsh   # the DeepSeek Harness image (./Containerfile.dsh)
#
# The image is a REQUIRED argument — there is no default, a build without
# one (or with an unknown image) fails before doing anything.
#
# Both images build FROM the shared base image (./Containerfile.base, built
# first via scripts/build-caged-base.sh; skip with CAGED_SKIP_BASE=1).
#
# Per-image knobs (env vars, defaults listed):
#   pi:  CAGED_IMAGE (caged:latest), PI_VERSION (0.84.2)
#   dsh: DSH_IMAGE (dsh:latest),     DSH_VERSION (0.1.0-rc.6)
# Shared: CAGED_BASE_IMAGE (caged-base:latest), CAGED_SKIP_BASE (0)

set -euo pipefail

# Resolve paths relative to this script: SCRIPT_DIR is scripts/, ROOT_DIR the project root.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

# --- Image selection: required argument, no default ----------------------
if [ "$#" -ne 1 ]; then
    echo "Error: no image specified — pass 'pi' or 'dsh'." >&2
    echo "Usage: $0 pi|dsh" >&2
    exit 2
fi

case "${1}" in
pi)
    CONTAINERFILE="Containerfile"
    IMAGE_TAG="${CAGED_IMAGE:-caged:latest}"
    VERSION_ARG="PI_VERSION"
    VERSION_VALUE="${PI_VERSION:-0.84.2}"
    ;;
dsh)
    CONTAINERFILE="Containerfile.dsh"
    IMAGE_TAG="${DSH_IMAGE:-dsh:latest}"
    VERSION_ARG="DSH_VERSION"
    VERSION_VALUE="${DSH_VERSION:-0.1.0-rc.6}"
    ;;
*)
    echo "Error: unknown image '${1}' — expected 'pi' or 'dsh'." >&2
    echo "Usage: $0 pi|dsh" >&2
    exit 2
    ;;
esac

# Shared base image (Containerfile.base): apt essentials, glab, acli, non-root
# user. Override the tag with CAGED_BASE_IMAGE (must exist or be built); skip
# the automatic base rebuild with CAGED_SKIP_BASE=1 (e.g. when using a
# prebuilt/pre-pushed base).
CAGED_BASE_IMAGE="${CAGED_BASE_IMAGE:-caged-base:latest}"
CAGED_SKIP_BASE="${CAGED_SKIP_BASE:-0}"

echo "==> Project Root: ${ROOT_DIR}"
echo "==> Building image: ${IMAGE_TAG} (${VERSION_ARG}=${VERSION_VALUE}, base: ${CAGED_BASE_IMAGE})..."

# Build the shared base image first (cached layers make this cheap on
# rebuilds; skip with CAGED_SKIP_BASE=1 if you manage the base yourself).
if [ "${CAGED_SKIP_BASE}" != "1" ]; then
  CAGED_BASE_IMAGE="${CAGED_BASE_IMAGE}" bash "${SCRIPT_DIR}/build-caged-base.sh"
fi

# Use the project root as the build context and an absolute Containerfile path,
# so the script works regardless of the directory it is invoked from.
container build \
  --tag "${IMAGE_TAG}" \
  --file "${ROOT_DIR}/${CONTAINERFILE}" \
  --build-arg CAGED_BASE_IMAGE="${CAGED_BASE_IMAGE}" \
  --build-arg "${VERSION_ARG}=${VERSION_VALUE}" \
  "${ROOT_DIR}"

echo "==> Build complete: ${IMAGE_TAG}"
if [ "${1}" = "dsh" ]; then
    echo "==> Start it with: ${SCRIPT_DIR}/dsh-start-container.sh"
fi
