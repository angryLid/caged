#!/usr/bin/env bash
# scripts/build-container.sh — build a caged image with the native Apple
# `container` tool. Invoked by the unified launcher: `cg <agent> build`.
#
# Usage:
#   cg pi build            # the pi agent image (./Containerfile), then the
#                          # browser layer on top (./Containerfile.browser)
#   cg browser build       # only the browser layer (./Containerfile.browser)
#   cg dsh build           # the DeepSeek Harness image (./Containerfile.dsh)
#   cg webui build         # the pi-web-ui Web UI image (./Containerfile.webui)
#   cg cmdc build          # the Command Code image (./Containerfile.commandcode)
#   scripts/build-container.sh pi  # equivalent direct call
#
# The image is a REQUIRED argument — there is no default, a build without
# one (or with an unknown image) fails before doing anything.
#
# pi and dsh build FROM the shared base image (./Containerfile.base, built
# first via scripts/build-caged-base.sh; skip with CAGED_SKIP_BASE=1).
# The browser layer (./Containerfile.browser) builds FROM the pi image, and
# webui builds FROM the browser layer, so the script builds
# base -> pi -> browser -> webui in order (skip the pi step with
# CAGED_SKIP_PI=1, the browser step with CAGED_SKIP_BROWSER=1, when they're
# already current).
#
# Per-image knobs (env vars, defaults listed):
#   pi:      CAGED_IMAGE (caged:latest),           PI_VERSION (latest)
#   browser: CAGED_BROWSER_IMAGE (caged-browser:latest), PLAYWRIGHT_VERSION (latest)
#   dsh:     DSH_IMAGE (dsh:latest),               DSH_VERSION (latest)
#   webui:   CAGED_WEB_IMAGE (caged-webui:latest), PI_WEB_UI_VERSION (latest)
#   cmdc:    COMMANDCODE_IMAGE (commandcode:latest), COMMAND_CODE_VERSION (latest)
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
    VERSION_VALUE="${PI_VERSION:-latest}"
    PKG_NAME="@earendil-works/pi-coding-agent"
    ;;
browser)
    CONTAINERFILE="Containerfile.browser"
    IMAGE_TAG="${CAGED_BROWSER_IMAGE:-caged-browser:latest}"
    VERSION_ARG="PLAYWRIGHT_VERSION"
    VERSION_VALUE="${PLAYWRIGHT_VERSION:-latest}"
    PKG_NAME="playwright"
    ;;
dsh)
    CONTAINERFILE="Containerfile.dsh"
    IMAGE_TAG="${DSH_IMAGE:-dsh:latest}"
    VERSION_ARG="DSH_VERSION"
    VERSION_VALUE="${DSH_VERSION:-latest}"
    PKG_NAME="@deepseek-ai/dsh"
    ;;
webui)
    CONTAINERFILE="Containerfile.webui"
    IMAGE_TAG="${CAGED_WEB_IMAGE:-caged-webui:latest}"
    VERSION_ARG="PI_WEB_UI_VERSION"
    VERSION_VALUE="${PI_WEB_UI_VERSION:-latest}"
    PKG_NAME="pi-web-ui"
    ;;
cmdc)
    CONTAINERFILE="Containerfile.commandcode"
    IMAGE_TAG="${COMMANDCODE_IMAGE:-commandcode:latest}"
    VERSION_ARG="COMMAND_CODE_VERSION"
    VERSION_VALUE="${COMMAND_CODE_VERSION:-latest}"
    PKG_NAME="command-code"
    ;;
*)
    echo "Error: unknown image '${1}' — expected 'pi', 'browser', 'dsh', 'webui' or 'cmdc'." >&2
    echo "Usage: $0 pi|browser|dsh|webui|cmdc" >&2
    exit 2
    ;;
esac

# Cache-busting via version resolution: the layer cache key includes the ARG
# value, so a literal "latest" would keep the install layer cached forever and
# never pick up new agent releases. Resolve "latest" to the concrete npm
# dist-tag version here instead — the ARG value (and thus the cache key)
# changes only when a new release actually lands, keeping the cache useful
# between releases. Explicit versions pass through untouched. Falls back to
# the literal "latest" when the registry is unreachable (build still works,
# it just reuses the cached layer).
if [ "${VERSION_VALUE}" = "latest" ]; then
    RESOLVED_VERSION="$(npm view "${PKG_NAME}" version 2>/dev/null || true)"
    if [ -n "${RESOLVED_VERSION}" ]; then
        echo "==> ${VERSION_ARG}: latest = ${RESOLVED_VERSION} (npm dist-tag)"
        VERSION_VALUE="${RESOLVED_VERSION}"
    else
        echo "==> Warning: could not resolve latest ${PKG_NAME} from npm; building with literal '${VERSION_VALUE}' (layer cache may serve a stale version)." >&2
    fi
fi

# Shared base image (Containerfile.base): apt essentials including python3/pip,
# uv, pnpm, yarn, glab, gh, jira-cli, non-root user. Override the tag with CAGED_BASE_IMAGE (must exist or be built); skip
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

# The webui image is an additive layer on top of the browser layer
# (Containerfile.webui is `FROM caged-browser:latest`), so building it needs
# the pi image present — build it first; that build now also chains the
# browser layer. Cached layers make this cheap when nothing below changed;
# skip with CAGED_SKIP_PI=1 (e.g. everything below webui is already current).
if [ "${1}" = "webui" ] && [ "${CAGED_SKIP_PI:-0}" != "1" ]; then
    echo "==> webui needs the browser layer (Containerfile.webui is FROM caged-browser:latest) — building it first..."
    CAGED_IMAGE="${CAGED_IMAGE:-caged:latest}" \
    PI_VERSION="${PI_VERSION:-latest}" \
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
  --build-arg CAGED_BROWSER_IMAGE="${CAGED_BROWSER_IMAGE:-caged-browser:latest}" \
  --build-arg "${VERSION_ARG}=${VERSION_VALUE}" \
  "${ROOT_DIR}"

# The pi image alone is not runnable-as-pi: the browser layer on top of it is
# what pi actually runs on (both the TUI and webui; see docs/BROWSER.md).
# Chain it unless explicitly skipped.
if [ "${1}" = "pi" ] && [ "${CAGED_SKIP_BROWSER:-0}" != "1" ]; then
    echo "==> pi runs on the browser layer — building ${CAGED_BROWSER_IMAGE:-caged-browser:latest}..."
    CAGED_SKIP_BASE=1 \
    CAGED_IMAGE="${CAGED_IMAGE:-caged:latest}" \
    PLAYWRIGHT_VERSION="${PLAYWRIGHT_VERSION:-latest}" \
    bash "${SCRIPT_DIR}/build-container.sh" browser
fi

echo "==> Build complete: ${IMAGE_TAG}"
case "${1}" in
pi)
    echo "==> Start it with: cg pi start"
    ;;
cmdc)
    echo "==> Start it with: cg cmdc start"
    ;;
dsh)
    echo "==> Start it with: cg dsh start"
    ;;
webui)
    echo "==> Start it with: cg webui start"
    ;;
esac
