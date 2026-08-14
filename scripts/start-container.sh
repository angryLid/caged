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

# --- host.docker.internal reachability hint (Apple path only) ---
# models.json's local-llm provider and the chrome-devtools forwarder default to
# host.docker.internal. apple/container can't resolve that name natively — the
# fix is a host-side DNS redirect (see docs/APPLE-CONTAINER.md, "Reaching host
# services"). Only relevant when the local provider is configured; warn, don't
# fail — pi runs fine without it if the local provider is unused.
if [ -n "${LOCAL_API_KEY:-}" ]; then
    HOST_DNS="$(dscacheutil -q host -a name host.docker.internal 2>/dev/null || true)"
    if ! printf '%s' "$HOST_DNS" | grep -q 'ip_address'; then
        echo "Warning: 'host.docker.internal' does not resolve on this Mac." >&2
        echo "  The local-llm provider (baseUrl in seed/.pi/agent/models.json) and Chrome" >&2
        echo "  CDP forwarding reach the host through it; without a DNS redirect they fail" >&2
        echo "  inside the container. One-time fix (re-run after every reboot):" >&2
        echo "    sudo container system dns create host.docker.internal --localhost 203.0.113.113" >&2
        echo "  See docs/APPLE-CONTAINER.md -> 'Reaching host services'." >&2
    fi
fi

# Pre-create the host sessions directory (under the workspace directory).
mkdir -p "${WORKSPACE_HOST}/sessions"

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
  -v "${WORKSPACE_HOST}/sessions:/agent-home/.pi/agent/sessions:rw" \
  -e HOME="/agent-home" \
  -e TERM="${TERM:-xterm-256color}" \
  -e COLORTERM="truecolor" \
  -e LANG="C.UTF-8" \
  -e PI_CODING_AGENT_DIR="/agent-home/.pi/agent" \
  -e MY_DEEPSEEK_API_KEY="${MY_DEEPSEEK_API_KEY:-}" \
  -e VOLCENGINE_API_KEY="${VOLCENGINE_API_KEY:-}" \
  -e MY_OPENROUTER_API_KEY="${MY_OPENROUTER_API_KEY:-}" \
  -e LOCAL_API_KEY="${LOCAL_API_KEY:-}" \
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