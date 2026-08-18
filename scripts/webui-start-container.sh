#!/usr/bin/env bash
# scripts/webui-start-container.sh — run the pi-web-ui Web chat UI with the
# native Apple `container` tool. The web-mode counterpart of
# scripts/start-container.sh (pi TUI) and scripts/dsh-start-container.sh
# (dsh Web UI), using the caged-webui image (scripts/build-container.sh webui).
#
# The pi SDK runs in-process inside pi-web-ui, so this is the same caged pi
# container in every way that matters — same live seed mount
# (~/.pi == seed/.pi), same provider keys, same hardening. The differences:
#   - the command is `pi-web-ui` (a web server) instead of the pi TUI,
#   - pi-web-ui binds 127.0.0.1 by default; the server must bind 0.0.0.0
#     INSIDE the container (PI_WEB_HOST) for `container run -p` to reach it,
#     and the HOST side is published to loopback only (127.0.0.1), so the UI
#     is reachable at http://127.0.0.1:${PI_WEBUI_HOST_PORT} and stays off
#     the LAN,
#   - chat history lives in /workspace/.pi-web (= $CAGED_WORKSPACE/.pi-web on
#     the host, same per-project pattern as pi sessions); override with
#     PI_WEB_DATA_DIR,
#   - memory defaults to 4 GB: the web mode keeps agents running in-process
#     and conversations alive in the background (override PI_WEBUI_MEMORY).
#
# Convention: like the pi/dsh containers, only ONE caged container at a time
# should mount a given seed rw — don't run the TUI (caged-pi) and the Web UI
# (caged-pi-webui) simultaneously against the same seed/.pi.

set -euo pipefail

# --- Path resolution ---
# CURRENT_PWD: the directory the user invoked the script from (mounted as
# /workspace — the web UI's agents work on this code).
CURRENT_PWD="$PWD"

# SCRIPT_DIR: scripts/ (absolute). ROOT_DIR: the repo root (anchors seed/).
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

IMAGE_TAG="${CAGED_WEB_IMAGE:-caged-webui:latest}"
CONTAINER_NAME="${CONTAINER_NAME:-caged-pi-webui}"
# RAM for the container VM. Apple `container` defaults the guest to 1 GB,
# which is too tight for a web server + in-process agent runtimes + parallel
# conversations; pin 4 GB like the dsh web image, override with PI_WEBUI_MEMORY.
PI_WEBUI_MEMORY="${PI_WEBUI_MEMORY:-4g}"
# PI_WEBUI_HOST_PORT is the host-loopback port you open in the browser; the
# container-internal port is a stable 8787 (pi-web-ui's default, pinned via
# PORT). Override only PI_WEBUI_HOST_PORT.
PI_WEBUI_HOST_PORT="${PI_WEBUI_HOST_PORT:-8787}"

# --- Host path mapping ---
# Workspace: prefer CAGED_WORKSPACE, fall back to the caller's current dir.
WORKSPACE_HOST="${CAGED_WORKSPACE:-$CURRENT_PWD}"
# Seed config home: anchored at seed/.pi under the project root (CAGED_PI_HOME
# overrides) — the same live ~/.pi bind the TUI uses, so models.json, skills,
# settings and AGENTS.md apply to the web mode unchanged.
PI_HOME_HOST="${CAGED_PI_HOME:-$ROOT_DIR/seed/.pi}"

echo "==> Checking required files in seed directory..."
if [ ! -f "${PI_HOME_HOST}/agent/models.json" ]; then
    echo "Error: Required seed file '${PI_HOME_HOST}/agent/models.json' not found!" >&2
    echo "Checked path: ${PI_HOME_HOST}/agent/models.json" >&2
    echo "Please ensure ${PI_HOME_HOST}/agent contains models.json, settings.json, and AGENTS.md" >&2
    exit 1
fi

# --- local-llm reachability hint (Apple path only) ---
# Same probe as scripts/start-container.sh: models.json's local-llm provider
# is the web UI's default, so warn (don't fail) if the host-side gateway at
# the vmnet address looks unreachable.
if [ -n "${LOCAL_API_KEY:-}" ] && ! curl -sS --noproxy '*' -m 1 -o /dev/null "http://192.168.64.1:8765/v1/models" 2>/dev/null; then
    echo "Warning: the local-llm provider doesn't look reachable at 192.168.64.1:8765." >&2
    echo "  The local-llm provider (baseUrl in seed/.pi/agent/models.json) reaches the host" >&2
    echo "  through the vmnet gateway. Make sure the host caddy-dev-server proxy listens" >&2
    echo "  on 192.168.64.1:8765 (not just 127.0.0.1), and macOS allows incoming" >&2
    echo "  connections. See docs/APPLE-CONTAINER.md -> 'Reaching host services'." >&2
fi

echo "==> Workspace host path: ${WORKSPACE_HOST}"
echo "==> Seed host path:      ${PI_HOME_HOST}"
echo "==> Starting container '${CONTAINER_NAME}' (Web UI on http://127.0.0.1:${PI_WEBUI_HOST_PORT})..."

# Stop AND remove any leftover container with the same name first.
# (stop alone leaves the container in existence, so --rm + the same --name
# then fails with "container with id caged-pi-webui already exists".)
container rm -f "${CONTAINER_NAME}" 2>/dev/null || true

# Run the container with -it, even though this is a web server, not a TUI.
# Without a TTY, Apple `container`'s foreground signal path is broken
# upstream: the CLI forwards terminal SIGINT to the guest via XPC, but the
# signal field is encoded as an Int64 while the API service decodes it as a
# String, so every delivery fails with 'missing signal in xpc message' and the
# signal never reaches the container — Ctrl+C only force-exits the CLI after
# three presses. With -it the host terminal is in raw mode and Ctrl+C travels
# as a byte through the pty into the guest's line discipline, the same
# working path the TUI uses; the web container then stops cleanly on one
# press. (Same upstream bug, SIGWINCH variant:
# https://github.com/apple/container/issues/1747.) Hardening following the
# caged posture implementable by the tool: --read-only, --cap-drop ALL,
# --tmpfs /tmp, pinned memory.
#
# The entrypoint (caged-entrypoint, inherited from the pi image) validates
# the live seed bind and installs skills, then execs tini -> pi-web-ui.
# --no-browser: there is no browser/xdg-open inside the container; without it
# the server would poll and warn before settling.
exec container run \
  --name "${CONTAINER_NAME}" \
  --rm \
  -it \
  --workdir /workspace \
  --read-only \
  --tmpfs /tmp \
  --memory "${PI_WEBUI_MEMORY}" \
  --cap-drop ALL \
  -p "127.0.0.1:${PI_WEBUI_HOST_PORT}:8787" \
  -v "${WORKSPACE_HOST}:/workspace:rw" \
  -v "${PI_HOME_HOST}:/agent-home/.pi:rw" \
  -e HOME="/agent-home" \
  -e TERM="${TERM:-xterm-256color}" \
  -e LANG="C.UTF-8" \
  -e PI_CODING_AGENT_DIR="/agent-home/.pi/agent" \
  -e PORT="8787" \
  -e PI_WEB_HOST="0.0.0.0" \
  -e PI_WEB_CWD="/workspace" \
  -e PI_WEB_DATA_DIR="/workspace/.pi-web" \
  -e MY_DEEPSEEK_API_KEY="${MY_DEEPSEEK_API_KEY:-}" \
  -e VOLCENGINE_API_KEY="${VOLCENGINE_API_KEY:-}" \
  -e MY_OPENROUTER_API_KEY="${MY_OPENROUTER_API_KEY:-}" \
  -e LOCAL_API_KEY="${LOCAL_API_KEY:-}" \
  -e CDP_HOST="192.168.64.1" \
  -e GITLAB_TOKEN="${GITLAB_TOKEN:-}" \
  -e GITLAB_HOST="${GITLAB_HOST:-}" \
  -e GLAB_SEND_TELEMETRY="false" \
  -e GLAB_CONFIG_DIR="/agent-home/.pi/agent/glab-cli" \
  -e JIRA_API_TOKEN="${JIRA_API_TOKEN:-}" \
  -e ACLI_CONFIG_DIR="/agent-home/.pi/agent/acli" \
  -e XDG_CONFIG_HOME="/tmp/.config" \
  -e npm_config_cache="/tmp/.npm" \
  -e XDG_CACHE_HOME="/tmp/.cache" \
  "${IMAGE_TAG}" \
  pi-web-ui --no-browser
