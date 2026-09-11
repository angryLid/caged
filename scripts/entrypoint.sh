#!/bin/sh
# caged entrypoint.
#
# Runs as the non-root user `agent` (USER agent in the image). Responsibilities:
#   1. Fail-fast validation BEFORE launching pi. There is deliberately no
#      config baked into the image: /agent-home must be the live bind mount of
#      the host `seed` directory (scripts/start-container.sh does this). If
#      the seed is missing, incomplete, or internally
#      inconsistent, we
#      exit non-zero with a clear message — never let pi start
#      half-configured.
#   2. Best-effort ownership bootstrap (matters for fresh named volumes) and
#      cache dirs on the /tmp tmpfs (npm/node never touch the RO home).
#   3. Declarative skills sync (best-effort) at container start.
#   4. Launch the requested command under tini so spawned bash subprocesses
#      (pi's bash tool) get reaped properly.

set -e

PI_HOME="${HOME:-/agent-home}/.pi"
AGENT_DIR="$PI_HOME/agent"

fail() {
    echo "caged: error: $*" >&2
    exit 1
}

# --- 1. fail-fast validation of the live seed bind -----------------------

[ -d "$AGENT_DIR" ] || fail \
    "config dir '$AGENT_DIR' not found — /agent-home must be the live seed bind containing .pi/agent." \
    "Run caged via 'scripts/start-container.sh' (mounts <caged>/seed at /agent-home), or mount it manually."

# --- 1.5 declarative global-prompt install (best-effort) -------------------
# The always-loaded environment primer (seed/prompt-src/global.md, tracked in
# git) is installed into this agent's AGENTS.md before the fail-fast check
# below, so a fresh clone passes. Non-fatal — a missing source/config still
# falls through to the AGENTS.md check, which fails fast with its own message.
if [ -f /agent-home/prompts.json ] && [ -f /opt/caged/prompt-sync.mjs ]; then
    echo "caged: installing global prompt (best-effort)..."
    if ! node /opt/caged/prompt-sync.mjs \
            --config /agent-home/prompts.json \
            --seed /agent-home \
            --target pi; then
        echo "caged: warning: global prompt install did not complete (exit $?) — continuing" >&2
    fi
elif [ -f /opt/caged/prompt-sync.mjs ]; then
    echo "caged: warning: seed/prompts.json missing — skipping global prompt install" >&2
else
    echo "caged: warning: prompt-sync.mjs missing from image — skipping global prompt install" >&2
fi

for f in models.json settings.json AGENTS.md; do
    [ -f "$AGENT_DIR/$f" ] || fail \
        "required config file missing: '$AGENT_DIR/$f' — the live seed mount is incomplete" \
        "(check CAGED_AGENT_HOME: it must point at <caged>/seed so /agent-home/.pi/agent has the seed files)."
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

# The seed must be writable (both ways) and pi's session dir must be usable.
# Sessions live on the shared workspace bind, NOT in the seed. The pi SDK has a
# single default (<agentDir>/sessions/<--encoded-cwd-->/) and neither pi-web-ui
# (which runs the SDK in-process, bypassing the TUI's settings resolution
# chain) nor the SDK itself honors the settings.json "sessionDir" key or
# PI_CODING_AGENT_SESSION_DIR for writes. So instead of pointing the setting at
# /workspace, we relocate the seed's sessions dir itself (the same pattern the
# commandcode entrypoint uses): pre-existing data moves into
# /workspace/.pi/sessions and the seed path becomes a symlink. Both the pi TUI
# and pi-web-ui then read AND write per-project sessions on the host workspace
# with no configuration, keeping the SDK default per-cwd subdirectory layout so
# the two agents share one location and see each other's sessions.
PI_SESSIONS_SEED="$AGENT_DIR/sessions"
PI_SESSIONS_WS="/workspace/.pi/sessions"
if [ -L "$PI_SESSIONS_SEED" ]; then
    # Already relocated; just make sure the target exists.
    mkdir -p "$PI_SESSIONS_WS"
elif [ -e "$PI_SESSIONS_SEED" ]; then
    # Pre-existing real data in the seed: copy it into the workspace (cp -a
    # merges into an existing target), then swap the seed path for a symlink.
    if mkdir -p "$PI_SESSIONS_WS" && cp -a "$PI_SESSIONS_SEED"/. "$PI_SESSIONS_WS"/; then
        rm -rf "$PI_SESSIONS_SEED"
        ln -s "$PI_SESSIONS_WS" "$PI_SESSIONS_SEED"
    else
        echo "caged: warning: could not relocate sessions to '$PI_SESSIONS_WS' — keeping them in the seed" >&2
    fi
else
    mkdir -p "$PI_SESSIONS_WS"
    ln -s "$PI_SESSIONS_WS" "$PI_SESSIONS_SEED"
fi
# One-time legacy migration: sessions written before the relocation (when
# settings.json pointed sessionDir at /workspace) sit FLAT at the top of the
# target, but the default picker only scans per-cwd subdirectories. File them
# under --workspace-- (the encoding of the container's fixed /workspace cwd).
for f in "$PI_SESSIONS_WS"/*.jsonl; do
    [ -f "$f" ] || break
    mkdir -p "$PI_SESSIONS_WS/--workspace--"
    mv "$f" "$PI_SESSIONS_WS/--workspace--/" 2>/dev/null || true
done
# Fail fast if the relocated sessions dir isn't writable (uid 1000 must own the
# host side) instead of letting pi start half-configured.
[ -w "$PI_SESSIONS_WS" ] || fail \
    "sessions dir '$PI_SESSIONS_WS' is not writable — the agent runs as uid 1000, so the" \
    "corresponding host directory must be writable by that uid."
[ -w "$AGENT_DIR" ] || fail "'$AGENT_DIR' is not writable — the live seed bind must be rw."

# --- 2. bootstrap (best-effort) ------------------------------------------

for dir in "$PI_HOME" "$PI_HOME/agent" /agent-home/.config /tmp/.npm /tmp/.cache; do
    mkdir -p "$dir"
    chown "$(id -un):$(id -gn)" "$dir" 2>/dev/null || true
done

# --- 3. declarative skills install (best-effort) -------------------------
# pi scans ~/.pi/agent/skills/ for skills. The git skill source repos are
# cloned on the HOST into the seed (seed/skills-sync/vendor/skills) by
# scripts/build-caged-base.sh, and the seed is mounted at /agent-home — so
# this step only copies the enabled skills from there into the seed's skills
# dirs: no network, no git at start. The vendor dir is derived from --seed,
# so it needs no flag. The config (seed/skills.json) lives at the seed root
# and is shared by every agent image (pi, dsh, cmdc); each entrypoint runs
# the same --link-only install, which copies each enabled skill into every
# configured target. Non-fatal — if the config or the vendor is missing, we
# log a warning and still launch pi.
if [ -f /agent-home/skills.json ] && [ -f /opt/caged/skills-sync.mjs ]; then
    echo "caged: installing skills (best-effort)..."
    if ! node /opt/caged/skills-sync.mjs \
            --config /agent-home/skills.json \
            --seed /agent-home \
            --target pi \
            --link-only; then
        echo "caged: warning: skills install did not complete (exit $?) — continuing" >&2
    fi
elif [ -f /opt/caged/skills-sync.mjs ]; then
    echo "caged: warning: seed/skills.json missing — skipping skills install" >&2
else
    echo "caged: warning: skills-sync.mjs missing from image — skipping skills install" >&2
fi

exec tini -s -- "$@"
