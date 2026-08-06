#!/bin/sh
# caged entrypoint.
#
# Runs as the non-root user `pi` (USER pi in the image). Responsibilities:
#   1. Fail-fast validation BEFORE launching pi. There is deliberately no
#      config baked into the image: $HOME (=/pi-agent) must be the live bind
#      mount of the host `seed/` directory (compose.yaml does this), making
#      ~/.pi == seed/.pi. If the seed is missing, incomplete, or internally
#      inconsistent, we exit non-zero with a clear message — never let pi
#      start half-configured.
#   2. Best-effort ownership bootstrap (matters for fresh named volumes).
#   3. Launch the requested command under tini so spawned bash subprocesses
#      (pi's bash tool) get reaped properly.

set -e

PI_HOME="${HOME:-/pi-agent}/.pi"
AGENT_DIR="$PI_HOME/agent"

fail() {
    echo "caged: error: $*" >&2
    exit 1
}

# --- 1. fail-fast validation of the live seed bind -----------------------

[ -d "$AGENT_DIR" ] || fail \
    "config dir '$AGENT_DIR' not found — \$HOME must be the live seed bind." \
    "Run caged via 'podman compose up' (mounts <caged>/seed at /pi-agent), or mount it manually."

for f in models.json settings.json AGENTS.md; do
    [ -f "$AGENT_DIR/$f" ] || fail \
        "required config file missing: '$AGENT_DIR/$f' — the live seed mount is incomplete" \
        "(check CAGED_HOME: it must point at the caged/ repo's seed dir, and seed/.pi/agent must exist)."
done

# mcp.json is optional, but every command it references must exist — a
# dangling pointer would otherwise silently disable that MCP server.
if [ -f "$AGENT_DIR/mcp.json" ]; then
    for cmd in $(sed -nE 's/.*"command"[[:space:]]*:[[:space:]]*"([^"]*)".*/\1/p' "$AGENT_DIR/mcp.json" 2>/dev/null); do
        case "$cmd" in
            /*) [ -x "$cmd" ] || fail "mcp.json references missing executable: '$cmd'." ;;
        esac
    done
fi

# The sessions mount must exist and the seed must be writable (both ways).
[ -d "$AGENT_DIR/sessions" ] || fail \
    "sessions dir '$AGENT_DIR/sessions' not found — \$CAGED_WORKSPACE/sessions should be" \
    "mounted there (podman compose creates it)."
[ -w "$AGENT_DIR" ] || fail "'$AGENT_DIR' is not writable — the live seed bind must be rw."

# --- 2. bootstrap (best-effort) ------------------------------------------

for dir in "$PI_HOME" "$PI_HOME/agent"; do
    mkdir -p "$dir"
    chown "$(id -un):$(id -gn)" "$dir" 2>/dev/null || true
done

exec tini -s -- "$@"
