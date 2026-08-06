#!/usr/bin/env bash
# Run pi inside the caged container.
#
#   ./scripts/run.sh "refactor this module"    # one-shot non-interactive
#   ./scripts/run.sh                            # interactive TUI
#
# Mounts:
#   - current dir (or $CAGED_WORKSPACE) read-write at /workspace
#   - named volume caged-pi-agent at /pi-agent (secrets/sessions persist)
#
# Hardening applied here (image itself stays generic):
#   --read-only                root filesystem is immutable
#   --tmpfs /tmp               writable scratch, no exec/suid
#   --cap-drop ALL             no kernel capabilities
#   --security-opt no-new-privileges
#   --userns=keep-id           keep 1000:1000 mapping for sane host perms
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ORIG_DIR="$(pwd)"
cd "$SCRIPT_DIR/.."

IMAGE="${CAGED_IMAGE:-caged:latest}"
WORKSPACE="${CAGED_WORKSPACE:-$ORIG_DIR}"
VOLUME="${CAGED_VOLUME:-caged-pi-agent}"

# Create the named volume first so entrypoint's best-effort chown is not a surprise.
podman volume exists "$VOLUME" 2>/dev/null || {
    echo "==> creating named volume $VOLUME"
    podman volume create "$VOLUME"
}

# --userns=keep-id makes $HOME within the container map to $CAGED_HOME_UID if set.
HOME_UID="${CAGED_HOME_UID:-}"

USRNS_ARGS=()
if [[ -n "$HOME_UID" ]]; then
    USRNS_ARGS+=(--userns=keep-id:uid="$HOME_UID,gid=$HOME_UID")
else
    USRNS_ARGS+=(--userns=keep-id)
fi

exec podman run --rm -it \
    --name caged-pi \
    --read-only \
    --tmpfs /tmp:rw,noexec,nosuid,size=512m \
    --cap-drop ALL \
    --security-opt no-new-privileges \
    "${USRNS_ARGS[@]}" \
    --pull=never \
    -v "$WORKSPACE:/workspace:rw" \
    -v "$VOLUME:/pi-agent" \
    -w /workspace \
    "$IMAGE" "$@"
