#!/bin/sh
# Validate the live seed and launch Command Code under tini.

set -e

COMMANDCODE_HOME="${COMMANDCODE_HOME:-/agent-home/.commandcode}"

fail() {
    echo "command-code: error: $*" >&2
    exit 1
}

# --- shared Atlassian env assignment (best-effort) --------------------------
# Map the ATLASSIAN_HOST/EMAIL/API_TOKEN trio the operator injects onto the
# vars cfl/jira-cli read (CFL_URL/CFL_EMAIL/CFL_API_TOKEN; JIRA_SERVER/
# JIRA_LOGIN/JIRA_API_TOKEN). Baked into the base image; skip silently on
# older builds without it.
if [ -f /opt/caged/env-atlassian.sh ]; then
    . /opt/caged/env-atlassian.sh
fi

[ -d "$COMMANDCODE_HOME" ] || fail \
    "state directory '$COMMANDCODE_HOME' not found — /agent-home must be the live seed bind."
[ -w "$COMMANDCODE_HOME" ] || fail \
    "state directory '$COMMANDCODE_HOME' is not writable — the live seed bind must be rw."
[ -d /workspace ] || fail "workspace '/workspace' not found."

for dir in "$COMMANDCODE_HOME" /agent-home/.config /tmp/.npm /tmp/.cache; do
    mkdir -p "$dir"
    chown "$(id -un):$(id -gn)" "$dir" 2>/dev/null || true
done

# --- declarative global-prompt install (best-effort) ----------------------
# Command Code reads ~/.commandcode/AGENTS.md as its user-level memory. The
# shared source (seed/prompt-src/global.md, tracked in git) is installed here
# at start from seed/prompts.json; same shape as skills install below.
# Non-fatal — if the config or baked script is missing we log a warning and
# still launch.
if [ -f /agent-home/prompts.json ] && [ -f /opt/caged/prompt-sync.mjs ]; then
    echo "command-code: installing global prompt (best-effort)..."
    if ! node /opt/caged/prompt-sync.mjs \
            --config /agent-home/prompts.json \
            --seed /agent-home \
            --target cmdc; then
        echo "command-code: warning: global prompt install did not complete (exit $?) — continuing" >&2
    fi
elif [ -f /opt/caged/prompt-sync.mjs ]; then
    echo "command-code: warning: seed/prompts.json missing — skipping global prompt install" >&2
else
    echo "command-code: warning: prompt-sync.mjs missing from image — skipping global prompt install" >&2
fi

# --- declarative skills install (best-effort) ------------------------------
# Command Code scans ~/.commandcode/skills/ for skills. The git skill source
# repos are cloned on the HOST into the seed (seed/skills-sync/vendor/skills)
# by scripts/build-caged-base.sh, and the seed is mounted at /agent-home — so
# this step only copies the enabled skills from there into the seed's skills
# dir: no network, no git at start. The vendor dir is derived from --seed, so
# it needs no flag. The config (seed/skills.json) lives at the seed root, so
# it is managed with the rest of the config. Non-fatal — if the config or the
# vendor is missing, we log a warning and still launch.
if [ -f /agent-home/skills.json ] && [ -f /opt/caged/skills-sync.mjs ]; then
    echo "command-code: installing skills (best-effort)..."
    if ! node /opt/caged/skills-sync.mjs \
            --config /agent-home/skills.json \
            --seed /agent-home \
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
