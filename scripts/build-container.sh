#!/usr/bin/env bash
# scripts/build-container.sh — build a caged image with the native Apple
# `container` tool.
#
# Usage:
#   scripts/build-container.sh pi     # the pi agent image (./Containerfile)
#   scripts/build-container.sh dsh    # the DeepSeek Harness image (./Containerfile.dsh)
#   scripts/build-container.sh webui  # the pi-web-ui Web UI image (./Containerfile.webui)
#   scripts/build-container.sh cmdc # the Command Code image (./Containerfile.commandcode)
#
# The image is a REQUIRED argument — there is no default, a build without
# one (or with an unknown image) fails before doing anything.
#
# pi and dsh build FROM the shared base image (./Containerfile.base, built
# first via scripts/build-caged-base.sh; skip with CAGED_SKIP_BASE=1).
# webui builds FROM the pi image (./Containerfile.webui is an additive layer
# on caged:latest), so the script builds base -> pi -> webui in order
# (skip the pi step with CAGED_SKIP_PI=1 when it's already current).
#
# Per-image knobs (env vars, defaults listed):
#   pi:    CAGED_IMAGE (caged:latest),      PI_VERSION (0.84.2)
#   dsh:   DSH_IMAGE (dsh:latest),          DSH_VERSION (0.1.0-rc.6)
#   webui: CAGED_WEB_IMAGE (caged-webui:latest), PI_WEB_UI_VERSION (0.26.0)
#   cmdc: COMMANDCODE_IMAGE (commandcode:latest), COMMAND_CODE_VERSION (latest)
# Shared: CAGED_BASE_IMAGE (caged-base:latest), CAGED_SKIP_BASE (0)

set -euo pipefail

# Resolve paths relative to this script: SCRIPT_DIR is scripts/, ROOT_DIR the project root.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

# --- Image selection: required argument, no default ----------------------
if [ "$#" -ne 1 ]; then
    echo "Error: no image specified — pass 'pi', 'dsh', 'webui' or 'cmdc'." >&2
    echo "Usage: $0 pi|dsh|webui|cmdc" >&2
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
webui)
    CONTAINERFILE="Containerfile.webui"
    IMAGE_TAG="${CAGED_WEB_IMAGE:-caged-webui:latest}"
    VERSION_ARG="PI_WEB_UI_VERSION"
    VERSION_VALUE="${PI_WEB_UI_VERSION:-0.26.0}"
    ;;
cmdc)
    CONTAINERFILE="Containerfile.commandcode"
    IMAGE_TAG="${COMMANDCODE_IMAGE:-commandcode:latest}"
    VERSION_ARG="COMMAND_CODE_VERSION"
    VERSION_VALUE="${COMMAND_CODE_VERSION:-latest}"
    ;;
*)
    echo "Error: unknown image '${1}' — expected 'pi', 'dsh', 'webui' or 'cmdc'." >&2
    echo "Usage: $0 pi|dsh|webui|cmdc" >&2
    exit 2
    ;;
esac

# Shared base image (Containerfile.base): apt essentials including python3,
# glab, gh, acli, non-root user. Override the tag with CAGED_BASE_IMAGE (must exist or be built); skip
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

# The webui image is an additive layer on top of the pi image
# (Containerfile.webui is `FROM caged:latest`), so building it needs the pi
# image present — build it first. Cached layers make this cheap when nothing
# pi-specific changed; skip with CAGED_SKIP_PI=1 (e.g. the pi image is
# already current).
if [ "${1}" = "webui" ] && [ "${CAGED_SKIP_PI:-0}" != "1" ]; then
    echo "==> webui needs the pi image (Containerfile.webui is FROM caged:latest) — building it first..."
    CAGED_IMAGE="${CAGED_IMAGE:-caged:latest}" \
    PI_VERSION="${PI_VERSION:-0.84.2}" \
    CAGED_SKIP_BASE=1 \
    bash "${SCRIPT_DIR}/build-container.sh" pi
fi

# Use the project root as the build context and an absolute Containerfile path,
# so the script works regardless of the directory it is invoked from.
container build \
  --tag "${IMAGE_TAG}" \
  --file "${ROOT_DIR}/${CONTAINERFILE}" \
  --build-arg CAGED_BASE_IMAGE="${CAGED_BASE_IMAGE}" \
  --build-arg CAGED_IMAGE="${CAGED_IMAGE:-caged:latest}" \
  --build-arg "${VERSION_ARG}=${VERSION_VALUE}" \
  "${ROOT_DIR}"

echo "==> Build complete: ${IMAGE_TAG}"
case "${1}" in
cmdc)
    echo "==> Start it with: ${SCRIPT_DIR}/start-container.sh cmdc"
    ;;
dsh)
    echo "==> Start it with: ${SCRIPT_DIR}/start-container.sh dsh"
    ;;
webui)
    echo "==> Start it with: ${SCRIPT_DIR}/start-container.sh webui"
    ;;
esac
