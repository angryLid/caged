#!/usr/bin/env bash
# Run one of caged's agent images with the native Apple container tool.
# Invoked by the unified launcher: `cg <agent> start`.
# Usage: cg pi|webui|dsh|cmdc start [command arguments...]

set -euo pipefail

MODE="${1:-pi}"
if [ "$#" -gt 0 ]; then shift; fi
case "$MODE" in
  pi|webui|dsh|cmdc) ;;
  --help|-h)
    cat >&2 <<'EOF'
Usage: cg pi|webui|dsh|cmdc start [command arguments...]

Agents:
  pi         Interactive pi TUI (default)
  webui      pi-web-ui on http://127.0.0.1:${PI_WEBUI_HOST_PORT:-8787}
  dsh        DeepSeek Harness on http://127.0.0.1:${DSH_HOST_PORT:-3080}
  cmdc       Interactive Command Code CLI

The remaining arguments replace the image's default command. Examples:
  cg pi start
  cg webui start
  cg dsh start
  cg cmdc start
  cg pi start --continue
EOF
    exit 0
    ;;
  *) echo "Error: unknown mode '$MODE' (expected pi, webui, dsh, or cmdc)." >&2; exit 2 ;;
esac

CURRENT_PWD="$PWD"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
WORKSPACE_HOST="${CAGED_WORKSPACE:-$CURRENT_PWD}"

# Select image, shared agent home, resources, and the command for this mode.
# The complete seed is mounted at /agent-home for every mode so pi, pi-webui,
# and dsh share CLI authentication and other agent state.
AGENT_HOME_HOST="${CAGED_AGENT_HOME:-$ROOT_DIR/seed}"

case "$MODE" in
  pi)
    IMAGE_TAG="${CAGED_IMAGE:-caged:latest}"
    CONTAINER_NAME="${CONTAINER_NAME:-caged-pi}"
    MEMORY="${CAGED_MEMORY:-2g}"
    PORT=""
    ;;
  webui)
    IMAGE_TAG="${CAGED_WEB_IMAGE:-caged-webui:latest}"
    CONTAINER_NAME="${CONTAINER_NAME:-caged-pi-webui}"
    MEMORY="${PI_WEBUI_MEMORY:-4g}"
    PORT="${PI_WEBUI_HOST_PORT:-8787}"
    ;;
  dsh)
    IMAGE_TAG="${DSH_IMAGE:-dsh:latest}"
    CONTAINER_NAME="${CONTAINER_NAME:-caged-dsh}"
    MEMORY="${DSH_MEMORY:-4g}"
    DSH_HOME_HOST="$AGENT_HOME_HOST/.dsh"
    PORT="${DSH_HOST_PORT:-3080}"
    DSH_PERMISSION_MODE="${DSH_PERMISSION_MODE:-danger-full-access}"
    DSH_DEEPSEEK_KEY="${DEEPSEEK_API_KEY:-${MY_DEEPSEEK_API_KEY:-}}"
    if [ -z "$DSH_DEEPSEEK_KEY" ] && [ -z "${OPENAI_API_KEY:-}" ] \
       && [ -z "${VOLCENGINE_API_KEY:-}" ] && [ -z "${MY_OPENROUTER_API_KEY:-}" ] \
       && [ -z "${LOCAL_API_KEY:-}" ] && [ -z "${NUBE_KEY:-}" ]; then
      echo "Error: no provider API key available for dsh." >&2
      echo "Set DEEPSEEK_API_KEY, OPENAI_API_KEY, VOLCENGINE_API_KEY," >&2
      echo "MY_OPENROUTER_API_KEY, LOCAL_API_KEY, or NUBE_KEY before starting." >&2
      exit 1
    fi
    mkdir -p "$DSH_HOME_HOST"
    ;;
  cmdc)
    IMAGE_TAG="${COMMANDCODE_IMAGE:-commandcode:latest}"
    CONTAINER_NAME="${CONTAINER_NAME:-caged-commandcode}"
    MEMORY="${COMMANDCODE_MEMORY:-4g}"
    PORT=""
    COMMANDCODE_HOME_HOST="$AGENT_HOME_HOST/.commandcode"
    mkdir -p "$COMMANDCODE_HOME_HOST"
    ;;
esac

if [ ! -d "$AGENT_HOME_HOST" ]; then
  echo "Error: shared agent home '$AGENT_HOME_HOST' does not exist." >&2
  echo "Ensure it points to <caged>/seed (override with CAGED_AGENT_HOME)." >&2
  exit 1
fi

# pi and pi-web-ui both use the live pi seed and require its model config.
if [ "$MODE" = pi ] || [ "$MODE" = webui ]; then
  if [ ! -f "$AGENT_HOME_HOST/.pi/agent/models.json" ]; then
    echo "Error: required seed file '$AGENT_HOME_HOST/.pi/agent/models.json' not found." >&2
    echo "Ensure CAGED_AGENT_HOME points to <caged>/seed." >&2
    exit 1
  fi
  if [ -n "${LOCAL_API_KEY:-}" ] && ! curl -sS --noproxy '*' -m 1 -o /dev/null \
      "http://192.168.64.1:8765/v1/models" 2>/dev/null; then
    echo "Warning: local-llm provider is not reachable at 192.168.64.1:8765." >&2
  fi
fi

if [ "$MODE" = dsh ]; then
  echo "==> Workspace: $WORKSPACE_HOST"
  echo "==> Agent home: $AGENT_HOME_HOST"
  echo "==> DSH home:   $DSH_HOME_HOST"
  echo "==> Starting dsh at http://127.0.0.1:$PORT"
else
  echo "==> Workspace: $WORKSPACE_HOST"
  echo "==> Agent home: $AGENT_HOME_HOST"
  if [ "$MODE" = cmdc ]; then
    echo "==> Command Code state: $AGENT_HOME_HOST/.commandcode"
  else
    echo "==> Pi config:  $AGENT_HOME_HOST/.pi"
  fi
  if [ "$MODE" = webui ]; then
    echo "==> Starting pi-web-ui at http://127.0.0.1:$PORT"
  elif [ "$MODE" = cmdc ]; then
    echo "==> Starting Command Code CLI"
  else
    echo "==> Starting pi TUI"
  fi
fi

# --rm normally handles cleanup; rm also covers a previous interrupted run.
container rm -f "$CONTAINER_NAME" 2>/dev/null || true

RUN_ARGS=(
  --name "$CONTAINER_NAME" --rm -it --workdir /workspace --read-only
  --tmpfs /tmp --memory "$MEMORY" --cap-drop ALL
  -v "$WORKSPACE_HOST:/workspace:rw"
  -v "$AGENT_HOME_HOST:/agent-home:rw"
  -e HOME=/agent-home -e LANG=C.UTF-8
  # Keep pi and pi-web-ui on the same per-workspace pi session directory.
  # The explicit override also wins over SDK defaults used by webui.
  -e PI_CODING_AGENT_SESSION_DIR="${PI_CODING_AGENT_SESSION_DIR:-/workspace/.pi/sessions}"
  -e GLAB_SEND_TELEMETRY=false
  -e GLAB_CONFIG_DIR=/agent-home/cli-auth/glab
  -e ACLI_CONFIG_DIR=/agent-home/cli-auth
  -e GH_CONFIG_DIR=/agent-home/cli-auth/gh
  -e GITLAB_TOKEN="${GITLAB_TOKEN:-}" -e GITLAB_HOST="${GITLAB_HOST:-}"
  -e GH_TOKEN="${GH_TOKEN:-}"
  -e JIRA_API_TOKEN="${JIRA_API_TOKEN:-}"
  -e XDG_CONFIG_HOME=/tmp/.config -e npm_config_cache=/tmp/.npm
  -e XDG_CACHE_HOME=/tmp/.cache
)

if [ "$MODE" = dsh ]; then
  RUN_ARGS+=(
    -p "127.0.0.1:$PORT:3080"
    -e DSH_HOME=/agent-home/.dsh
    -e DEEPSEEK_API_KEY="$DSH_DEEPSEEK_KEY"
    -e MY_DEEPSEEK_API_KEY="${MY_DEEPSEEK_API_KEY:-}"
    -e VOLCENGINE_API_KEY="${VOLCENGINE_API_KEY:-}"
    -e MY_OPENROUTER_API_KEY="${MY_OPENROUTER_API_KEY:-}"
    -e LOCAL_API_KEY="${LOCAL_API_KEY:-}" -e OPENAI_API_KEY="${OPENAI_API_KEY:-}"
    -e NUBE_KEY="${NUBE_KEY:-}"
    -e DSH_PERMISSION_MODE="$DSH_PERMISSION_MODE"
  )
  DEFAULT_CMD=(dsh web)
elif [ "$MODE" = webui ]; then
  RUN_ARGS+=(
    -p "127.0.0.1:$PORT:8787"
    -e TERM="${TERM:-xterm-256color}" -e PI_CODING_AGENT_DIR=/agent-home/.pi/agent
    -e PORT=8787 -e PI_WEB_HOST=0.0.0.0 -e PI_WEB_CWD=/workspace
    -e PI_WEB_DATA_DIR=/workspace/.pi-web
  )
  DEFAULT_CMD=(pi-web-ui --no-browser)
elif [ "$MODE" = cmdc ]; then
  RUN_ARGS+=(
    -e TERM="${TERM:-xterm-256color}"
  )
  DEFAULT_CMD=(cmd --yolo)
else
  RUN_ARGS+=(
    -e TERM="${TERM:-xterm-256color}" -e PI_CODING_AGENT_DIR=/agent-home/.pi/agent
  )
  DEFAULT_CMD=(pi)
fi

# Provider credentials are shared by all modes; harmlessly empty values
# preserve the old scripts' environment contract. CLI auth is deliberately
# shared under /agent-home/cli-auth because the complete seed is mounted at
# /agent-home for every container.
RUN_ARGS+=(
  -e MY_DEEPSEEK_API_KEY="${MY_DEEPSEEK_API_KEY:-}" -e VOLCENGINE_API_KEY="${VOLCENGINE_API_KEY:-}"
  -e MY_OPENROUTER_API_KEY="${MY_OPENROUTER_API_KEY:-}" -e LOCAL_API_KEY="${LOCAL_API_KEY:-}"
  -e NUBE_KEY="${NUBE_KEY:-}" -e JUSTWOKER_API_KEY="${JUSTWOKER_API_KEY:-}"
  -e CDP_HOST=192.168.64.1
)

if [ "$MODE" = pi ] || [ "$MODE" = webui ]; then
  RUN_ARGS+=(
    -e TERM="${TERM:-xterm-256color}"
  )
fi

if [ "$#" -gt 0 ] && [ "$1" = -- ]; then shift; fi
CMD=("${@:-${DEFAULT_CMD[*]}}")
# The expansion above is intentionally replaced below for correct array
# semantics when no command arguments were supplied.
if [ "$#" -eq 0 ]; then CMD=("${DEFAULT_CMD[@]}"); fi
exec container run "${RUN_ARGS[@]}" "$IMAGE_TAG" "${CMD[@]}"
