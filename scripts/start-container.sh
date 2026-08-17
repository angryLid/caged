#!/usr/bin/env bash
# scripts/start-container.sh — run the caged container with the native Apple container tool

set -euo pipefail

# --- Path resolution ---
# CURRENT_PWD: the directory the user invoked the script from (mounted as /workspace).
CURRENT_PWD="$PWD"

# SCRIPT_DIR: absolute path of this script's directory (.../caged/scripts)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# ROOT_DIR: the project root (.../caged)
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

IMAGE_TAG="${CAGED_IMAGE:-caged:latest}"
CONTAINER_NAME="${CONTAINER_NAME:-caged-pi}"

# --- Host path mapping ---
# Workspace: prefer CAGED_WORKSPACE, fall back to the caller's current directory.
WORKSPACE_HOST="${CAGED_WORKSPACE:-$CURRENT_PWD}"
# Seed config home: anchored at seed/.pi under the project root (CAGED_PI_HOME overrides).
PI_HOME_HOST="${CAGED_PI_HOME:-$ROOT_DIR/seed/.pi}"

echo "==> Checking required files in seed directory..."
if [ ! -f "${PI_HOME_HOST}/agent/models.json" ]; then
    echo "Error: Required seed file '${PI_HOME_HOST}/agent/models.json' not found!" >&2
    echo "Checked path: ${PI_HOME_HOST}/agent/models.json" >&2
    echo "Please ensure ${PI_HOME_HOST}/agent contains models.json, settings.json, and AGENTS.md" >&2
    exit 1
fi

# --- local-llm reachability hint (Apple path only) ---
# models.json's local-llm provider and the chrome-devtools forwarder reach the
# host at 192.168.64.1 — the vmnet gateway of `container`'s default network,
# i.e. the Mac's bridge interface as seen from inside every container (no DNS,
# pf, or sudo setup needed). The host services just have to listen on that
# address, not only loopback: the caddy-dev-server proxy on 192.168.64.1:8765,
# and Chrome CDP reachable on 192.168.64.1:9222 (socat bridge if Chrome binds
# loopback only). Warn, don't fail — pi runs fine without it if the local
# provider is unused. See docs/APPLE-CONTAINER.md, "Reaching host services".
if [ -n "${LOCAL_API_KEY:-}" ] && ! curl -sS --noproxy '*' -m 1 -o /dev/null "http://192.168.64.1:8765/v1/models" 2>/dev/null; then
    echo "Warning: the local-llm provider doesn't look reachable at 192.168.64.1:8765." >&2
    echo "  The local-llm provider (baseUrl in seed/.pi/agent/models.json) reaches the host" >&2
    echo "  through the vmnet gateway. Make sure the host caddy-dev-server proxy listens" >&2
    echo "  on 192.168.64.1:8765 (not just 127.0.0.1), and macOS allows incoming" >&2
    echo "  connections. See docs/APPLE-CONTAINER.md -> 'Reaching host services'." >&2
fi

# Pre-create the host sessions directory (under the workspace directory).
mkdir -p "${WORKSPACE_HOST}/.pi/sessions"

echo "==> Workspace host path: ${WORKSPACE_HOST}"
echo "==> Seed host path:      ${PI_HOME_HOST}"
echo "==> Starting container '${CONTAINER_NAME}'..."

# Stop any leftover container with the same name first.
container stop "${CONTAINER_NAME}" 2>/dev/null || true

# Run the container.
exec container run \
  --name "${CONTAINER_NAME}" \
  --rm \
  -it \
  --workdir /workspace \
  --read-only \
  --tmpfs /tmp \
  --cap-drop ALL \
  -v "${WORKSPACE_HOST}:/workspace:rw" \
  -v "${PI_HOME_HOST}:/agent-home/.pi:rw" \
  -v "${WORKSPACE_HOST}/.pi/sessions:/agent-home/.pi/agent/sessions:rw" \
  -e HOME="/agent-home" \
  -e TERM="${TERM:-xterm-256color}" \
  -e COLORTERM="truecolor" \
  -e LANG="C.UTF-8" \
  -e PI_CODING_AGENT_DIR="/agent-home/.pi/agent" \
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
  pi