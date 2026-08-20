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

exec tini -s -- "$@"
