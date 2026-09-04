#!/bin/sh
# dsh entrypoint.
#
# Runs as the non-root user `agent` (USER agent in the image). Responsibilities:
#   1. Fail-fast validation of the LIVE shared agent home (seed) BEFORE
#      launching dsh. $DSH_HOME remains /agent-home/.dsh inside that shared
#      home. If it is missing or not writable we exit non-zero with a clear
#      message — never let dsh start half-configured.
#   2. Best-effort bootstrap of cache dirs on the /tmp tmpfs (node never
#      touches the RO home or the repo-clean $DSH_HOME).
#   3. Launch the requested command under tini so spawned bash subprocesses
#      (dsh's bash tool) get reaped properly.
#
# The Web UI binds 0.0.0.0:3080 (with the host side published to loopback only)
# via seed/.dsh/cordis.patch.yml — no in-container bridge is needed. See that
# file for the rationale.

set -e

# the start script sets DSH_HOME=/agent-home/.dsh; honour an override.
DSH_HOME_PATH="${DSH_HOME:-/agent-home/.dsh}"

fail() {
    echo "dsh: error: $*" >&2
    exit 1
}

# --- 1. fail-fast validation of the live seed bind -----------------------

[ -d "$DSH_HOME_PATH" ] || fail \
    "config home '$DSH_HOME_PATH' not found — /agent-home must be the live seed bind containing .dsh." \
    "Run via 'scripts/start-container.sh dsh' (mounts <repo>/seed at /agent-home)," \
    "or mount it manually."
[ -w "$DSH_HOME_PATH" ] || fail \
    "'$DSH_HOME_PATH' is not writable — the live seed bind must be rw" \
    "(dsh auto-initializes profiles/ and stores settings/sessions here on first use)."

# --- 2. bootstrap (best-effort caches on the /tmp tmpfs) ------------------

for dir in /agent-home/.config /tmp/.npm /tmp/.cache; do
    mkdir -p "$dir"
    chown "$(id -un):$(id -gn)" "$dir" 2>/dev/null || true
done

# --- 3. declarative skills install (best-effort) --------------------------
# dsh's local skill provider scans $DSH_HOME/skills (rank "user-dsh"). The
# git skill source repos are cloned on the HOST into the seed
# (seed/skills-sync/vendor/skills) by scripts/build-caged-base.sh, and the
# seed is mounted at /agent-home — so this step only copies the enabled
# skills from there into the seed's skills dir: no network, no git at start.
# The vendor dir is derived from --seed, so it needs no flag. The config
# (seed/skills.json) lives at the seed root. Non-fatal — if the config or the
# vendor is missing, we log a warning and still launch.
if [ -f /agent-home/skills.json ] && [ -f /opt/caged/skills-sync.mjs ]; then
    echo "dsh: installing skills (best-effort)..."
    if ! node /opt/caged/skills-sync.mjs \
            --config /agent-home/skills.json \
            --seed /agent-home \
            --target dsh \
            --link-only; then
        echo "dsh: warning: skills install did not complete (exit $?) — continuing" >&2
    fi
elif [ -f /opt/caged/skills-sync.mjs ]; then
    echo "dsh: warning: seed/skills.json missing — skipping skills install" >&2
else
    echo "dsh: warning: skills-sync.mjs missing from image — skipping skills install" >&2
fi

# --- 4. best-effort: default Web workspace --------------------------------
# dsh's Web UI has no env var for a default workspace; it derives the default
# from the persisted workspace registry ($DSH_HOME/storages/workspace.json).
# Seed a /workspace registration so the UI opens on the mounted code dir
# instead of asking the user to "Choose workspace". Idempotent and best-effort
# (never blocks boot, never clobbers user registrations) — see
# scripts/dsh-ensure-workspace.mjs.
if [ -x /usr/local/bin/dsh-ensure-workspace ]; then
    dsh-ensure-workspace || echo "dsh: warn: default workspace seed skipped (non-fatal)" >&2 || true
fi

exec tini -s -- "$@"