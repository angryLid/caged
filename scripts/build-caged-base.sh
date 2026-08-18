#!/usr/bin/env bash
# scripts/build-caged-base.sh — build the shared caged-base image
# (./Containerfile.base: apt essentials including python3, glab, acli,
# non-root user).
#
# Called automatically by scripts/build-container.sh (run with the argument
# `pi` or `dsh`) before it builds the derived image;
# run it directly to rebuild just the base — e.g. after bumping
# GLAB_VERSION / ACLI_VERSION or editing Containerfile.base. If you override
# CAGED_BASE_IMAGE here, pass the same value to the derived build (or export
# it) so its FROM resolves to the image you built.

set -euo pipefail

# Resolve paths relative to this script: SCRIPT_DIR is scripts/, ROOT_DIR the project root.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

CAGED_BASE_IMAGE="${CAGED_BASE_IMAGE:-caged-base:latest}"

echo "==> Project Root: ${ROOT_DIR}"
echo "==> Building base image: ${CAGED_BASE_IMAGE} (GLAB_VERSION=${GLAB_VERSION:-1.112.0}, ACLI_VERSION=${ACLI_VERSION:-1.3.22})..."

# Repo root as the build context (same .dockerignore as the derived builds).
container build \
  --tag "${CAGED_BASE_IMAGE}" \
  --file "${ROOT_DIR}/Containerfile.base" \
  --build-arg GLAB_VERSION="${GLAB_VERSION:-1.112.0}" \
  --build-arg ACLI_VERSION="${ACLI_VERSION:-1.3.22}" \
  "${ROOT_DIR}"

echo "==> Base image ready: ${CAGED_BASE_IMAGE}"
