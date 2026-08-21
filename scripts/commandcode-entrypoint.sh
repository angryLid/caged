#!/bin/sh
# Validate the live seed and launch Command Code under tini.

set -e

COMMANDCODE_HOME="${COMMANDCODE_HOME:-/agent-home/.commandcode}"

fail() {
    echo "command-code: error: $*" >&2
    exit 1
}

[ -d "$COMMANDCODE_HOME" ] || fail \
    "state directory '$COMMANDCODE_HOME' not found — /agent-home must be the live seed bind."
[ -w "$COMMANDCODE_HOME" ] || fail \
    "state directory '$COMMANDCODE_HOME' is not writable — the live seed bind must be rw."
[ -d /workspace ] || fail "workspace '/workspace' not found."

for dir in "$COMMANDCODE_HOME" /tmp/.npm /tmp/.cache /tmp/.config; do
    mkdir -p "$dir"
    chown "$(id -un):$(id -gn)" "$dir" 2>/dev/null || true
done

# --- declarative skills install (best-effort) ------------------------------
# Command Code scans ~/.commandcode/skills/ for skills. The skill repos are
# cloned into the IMAGE at build time (see Containerfile.base) under
# /opt/caged/skills/vendor; at container start we only copy the enabled
# skills from there into the seed's skills dir — no network, no git. The
# config (seed/skills.json) lives at the seed root, so it is managed with
# the rest of the config. Non-fatal — if the config or baked vendor is
# missing, we log a warning and still launch.
if [ -f /agent-home/skills.json ] && [ -f /opt/caged/skills-sync.mjs ]; then
    echo "command-code: installing skills (best-effort)..."
    if ! node /opt/caged/skills-sync.mjs \
            --config /agent-home/skills.json \
            --seed /agent-home \
            --vendor /opt/caged/skills/vendor \
            --target cmdc \
            --link-only; then
        echo "command-code: warning: skills install did not complete (exit $?) — continuing" >&2
    fi
elif [ -f /opt/caged/skills-sync.mjs ]; then
    echo "command-code: warning: seed/skills.json missing — skipping skills install" >&2
else
    echo "command-code: warning: skills-sync.mjs missing from image — skipping skills install" >&2
fi

# Command Code hardcodes its session catalog under
# $HOME/.commandcode/projects/<cwd-slug>/ (and /rewind's file backups under
# $HOME/.commandcode/file-history/); $HOME is /agent-home here. Relocate both
# to the shared workspace bind so every agent container mounts the same
# sessions and checkpoints. A lazy migration moves pre-existing data first;
# afterwards the seed paths become symlinks to /workspace/.commandcode.
WORKSPACE_CC_HOME="/workspace/.commandcode"

relocate_to_workspace() {
    subdir="$1"
    seed_path="$COMMANDCODE_HOME/$subdir"
    ws_path="$WORKSPACE_CC_HOME/$subdir"
    if [ -L "$seed_path" ]; then
        # Already relocated; just make sure the target exists.
        mkdir -p "$ws_path"
    elif [ -e "$seed_path" ]; then
        # Pre-existing real data in the seed: move it into the workspace.
        mkdir -p "$WORKSPACE_CC_HOME"
        if [ -e "$ws_path" ]; then
            mv "$seed_path"/* "$ws_path"/ 2>/dev/null || true
            rmdir "$seed_path" 2>/dev/null || true
        else
            mv "$seed_path" "$ws_path"
        fi
        ln -s "$ws_path" "$seed_path"
    else
        mkdir -p "$ws_path"
        ln -s "$ws_path" "$seed_path"
    fi
}

relocate_to_workspace projects
relocate_to_workspace file-history

exec tini -s -- "$@"
