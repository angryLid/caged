#!/usr/bin/env bash
# Build the caged image.
#   ./scripts/build.sh [--no-cache]
set -euo pipefail

cd "$(dirname "$0")/.."

IMAGE="${CAGED_IMAGE:-caged:latest}"
ARGS=(-t "$IMAGE" -f Containerfile .)

if [[ "${1:-}" == "--no-cache" ]]; then
    ARGS+=(--no-cache)
fi

echo "==> podman build ${ARGS[*]}"
exec podman build "${ARGS[@]}"
