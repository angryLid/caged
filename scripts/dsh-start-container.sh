#!/usr/bin/env bash
# scripts/dsh-start-container.sh — run the DeepSeek Harness web UI with the
# native Apple `container` tool. The dsh counterpart of
# scripts/start-container.sh (pi), scoped to the dsh image and its web server
# mode.
#
# How the browser reaches the UI (the port part):
#   - dsh web binds 127.0.0.1 by default and its CLI *rejects* --host 0.0.0.0,
#     but the webserver config accepts '0.0.0.0' (only the flag parser rejects
#     it). seed/.dsh/cordis.patch.yml sets it to bind 0.0.0.0:3080 inside the
#     container.
#   - Apple `container run -p` forwards a HOST LOOPBACK port to the container
#     IP, so `-p 127.0.0.1:${DSH_HOST_PORT}:3080` reaches that listener. Binding
#     the host side to 127.0.0.1 (not 0.0.0.0) keeps the UI off the LAN.
#   - Open http://127.0.0.1:${DSH_HOST_PORT} in a browser on the host.

set -euo pipefail

# --- Path resolution ---
# CURRENT_PWD: the directory the user invoked the script from (mounted as
# /workspace — dsh's agents work on this code).
CURRENT_PWD="$PWD"

# SCRIPT_DIR: scripts/ (absolute). DSH_DIR: the repo root (anchors both
# images' scripts).
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DSH_DIR="$(dirname "$SCRIPT_DIR")"

IMAGE_TAG="${DSH_IMAGE:-dsh:latest}"
CONTAINER_NAME="${CONTAINER_NAME:-caged-dsh}"
# RAM for the container VM. Apple `container` defaults the guest to 1 GB,
# which OOMs a long-running Node web server + agent runtime on larger tasks;
# pin 4 GB, override with DSH_MEMORY (e.g. 8g).
DSH_MEMORY="${DSH_MEMORY:-4g}"
# DSH_HOST_PORT is the host-loopback port you open in the browser; the
# container-internal port is a stable 3080 (pinned by seed/.dsh/cordis.patch.yml
# and dsh's default). Override only DSH_HOST_PORT.
DSH_HOST_PORT="${DSH_HOST_PORT:-3080}"
# DSH_PERMISSION_MODE: caged's container itself is the sandbox, so we disable
# dsh's built-in sandbox + interactive approval prompts by default
# (danger-full-access = dsh's official "allow all" preset). Override to get
# dsh's own confinement back.
DSH_PERMISSION_MODE="${DSH_PERMISSION_MODE:-danger-full-access}"

# --- API key resolution ------------------------------------------------
# pi uses MY_DEEPSEEK_API_KEY; dsh expects DEEPSEEK_API_KEY. Accept either, then
# FAIL LOUD (don't pass a blank key) if neither is available — a blank env value
# makes dsh throw "the API key resolved from DEEPSEEK_API_KEY is blank".
DSH_DEEPSEEK_KEY="${DEEPSEEK_API_KEY:-${MY_DEEPSEEK_API_KEY:-}}"
if [ -z "$DSH_DEEPSEEK_KEY" ] && [ -z "${OPENAI_API_KEY:-}" ]; then
    echo "Error: no provider API key available." >&2
    echo "  Set one before starting, e.g.:" >&2
    echo "    export DEEPSEEK_API_KEY=sk-..." >&2
    echo "  or enter it once in the Web UI (Settings -> Models -> DeepSeek)." >&2
    exit 1
fi

# --- Host path mapping ---
# Workspace: prefer CAGED_WORKSPACE, fall back to the caller's current dir.
WORKSPACE_HOST="${CAGED_WORKSPACE:-$CURRENT_PWD}"
# Live $DSH_HOME: anchored at seed/.dsh under the repo root (DSH_HOME_HOST
# overrides). Must exist on the host to be a bind source.
DSH_HOME_HOST="${DSH_HOME_HOST:-$DSH_DIR/seed/.dsh}"

echo "==> Ensuring seed dir exists (live \$DSH_HOME): ${DSH_HOME_HOST}"
mkdir -p "${DSH_HOME_HOST}"

echo "==> Workspace host path: ${WORKSPACE_HOST}"
echo "==> Seed (\$DSH_HOME) host path: ${DSH_HOME_HOST}"
echo "==> Starting container '${CONTAINER_NAME}' (UI on http://127.0.0.1:${DSH_HOST_PORT})..."

# Stop AND remove any leftover container with the same name first.
# (stop alone leaves the container in existence, so --rm + the same --name
# then fails with "container with id caged-dsh already exists".)
container rm -f "${CONTAINER_NAME}" 2>/dev/null || true

# Run the container with -it, even though dsh is a web server, not a TUI.
# Without a TTY, Apple `container`'s foreground signal path is broken
# upstream: the CLI forwards terminal SIGINT to the guest via XPC, but the
# signal field is encoded as an Int64 while the API service decodes it as a
# String, so every delivery fails with 'missing signal in xpc message' and the
# signal never reaches the container — Ctrl+C only force-exits the CLI after
# three presses ('Received 3 SIGINT/SIGTERM's, forcefully exiting.'). With -it
# the host terminal is in raw mode and Ctrl+C travels as a byte through the
# pty into the guest's line discipline, the same working path caged-pi uses;
# the web container then stops cleanly on one press. (Same upstream bug,
# SIGWINCH variant: https://github.com/apple/container/issues/1747.) Hardening
# following the caged posture implementable by the tool: --read-only,
# --cap-drop ALL, --tmpfs /tmp, pinned memory. (No userns / no --security-opt
# on Apple's tool, same as caged.)
exec container run \
  --name "${CONTAINER_NAME}" \
  --rm \
  -it \
  --workdir /workspace \
  --read-only \
  --tmpfs /tmp \
  --memory "${DSH_MEMORY}" \
  --cap-drop ALL \
  -p "127.0.0.1:${DSH_HOST_PORT}:3080" \
  -v "${WORKSPACE_HOST}:/workspace:rw" \
  -v "${DSH_HOME_HOST}:/agent-home/.dsh:rw" \
  -e HOME="/agent-home" \
  -e DSH_HOME="/agent-home/.dsh" \
  -e LANG="C.UTF-8" \
  -e DEEPSEEK_API_KEY="${DSH_DEEPSEEK_KEY}" \
  -e OPENAI_API_KEY="${OPENAI_API_KEY:-}" \
  -e DSH_PERMISSION_MODE="${DSH_PERMISSION_MODE}" \
  -e XDG_CONFIG_HOME="/tmp/.config" \
  -e npm_config_cache="/tmp/.npm" \
  -e XDG_CACHE_HOME="/tmp/.cache" \
  "${IMAGE_TAG}" \
  dsh \
  web