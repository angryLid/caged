#!/bin/sh
# caged entrypoint.
#
# Runs as the non-root user `pi` (USER pi in the image). Responsibilities:
#   1. Make sure the persistent volume layout exists even if a fresh empty
#      named volume is mounted. Ownership is best-effort: under
#      cap_drop/rootless setups chown may be unprivileged, which is fine
#      because the image already ships the dirs owned by `pi`.
#   2. Launch the requested command under tini so spawned bash subprocesses
#      (pi's bash tool) get reaped properly.

set -e

for dir in "${PI_CODING_AGENT_DIR:-/pi-agent/agent}" \
           "${PI_CODING_AGENT_SESSION_DIR:-/pi-agent/sessions}"; do
    mkdir -p "$dir"
    chown "$(id -un):$(id -gn)" "$dir" 2>/dev/null || true
done

exec tini -s -- "$@"
