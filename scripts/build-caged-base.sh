#!/usr/bin/env bash
# scripts/build-caged-base.sh — build the shared caged-base image
# (./Containerfile.base: apt essentials including python3, glab, gh, jira,
# cfl, non-root user) and clone/pull the git skill sources into the seed.
#
# Called automatically by scripts/build-container.sh (run with the argument
# `pi` or `dsh`) before it builds the derived image;
# run it directly to rebuild just the base — e.g. after bumping
# GLAB_VERSION / GH_VERSION / JIRA_VERSION / CFL_VERSION, or editing Containerfile.base.
# If you override CAGED_BASE_IMAGE here, pass the same value to the derived
# build (or export it) so its FROM resolves to the image you built.
#
# The skill source repos are cloned HERE, on the host, into the seed
# (seed/skills-sync/vendor/skills) — NOT into the image: the seed is bind-
# mounted into every container anyway, so baking third-party repos into the
# image would only make it bigger and stale. Skip the clone with
# CAGED_SKIP_SKILLS_SYNC=1 (e.g. offline rebuilds — an existing vendor dir is
# reused as-is).

set -euo pipefail

# Resolve paths relative to this script: SCRIPT_DIR is scripts/, ROOT_DIR the project root.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

CAGED_BASE_IMAGE="${CAGED_BASE_IMAGE:-caged-base:latest}"

echo "==> Project Root: ${ROOT_DIR}"

# --- Skill sources: clone/pull on the host, into the seed -----------------
# `--clone-only` touches only the vendor dir; the per-agent installs happen at
# container start (each entrypoint runs --link-only --target <agent>). node is
# a host prerequisite here, as it already is for running skills-sync by hand.
if [ "${CAGED_SKIP_SKILLS_SYNC:-0}" != "1" ]; then
  echo "==> Syncing git skill sources into the seed (host clone, not baked into the image)..."
  if ! command -v node >/dev/null 2>&1; then
    echo "Error: node not found on the host — needed to clone the skill sources." >&2
    echo "Install Node.js, or skip the step with CAGED_SKIP_SKILLS_SYNC=1 (skills then" >&2
    echo "come from whatever is already in seed/skills-sync/vendor/)." >&2
    exit 1
  fi
  node "${SCRIPT_DIR}/skills-sync.mjs" --clone-only
else
  echo "==> CAGED_SKIP_SKILLS_SYNC=1 — reusing the existing seed skill vendor."
fi
echo "==> Building base image: ${CAGED_BASE_IMAGE} (GLAB_VERSION=${GLAB_VERSION:-1.112.0}, GH_VERSION=${GH_VERSION:-2.97.0}, JIRA_VERSION=${JIRA_VERSION:-1.7.0}, CFL_VERSION=${CFL_VERSION:-1.3.96}, PNPM_VERSION=${PNPM_VERSION:-10.15.0}, YARN_VERSION=${YARN_VERSION:-1.22.22})..."

# Repo root as the build context (same .dockerignore as the derived builds).
container build \
  --tag "${CAGED_BASE_IMAGE}" \
  --file "${ROOT_DIR}/Containerfile.base" \
  --build-arg GLAB_VERSION="${GLAB_VERSION:-1.112.0}" \
  --build-arg GH_VERSION="${GH_VERSION:-2.97.0}" \
  --build-arg JIRA_VERSION="${JIRA_VERSION:-1.7.0}" \
  --build-arg CFL_VERSION="${CFL_VERSION:-1.3.96}" \
  --build-arg PNPM_VERSION="${PNPM_VERSION:-10.15.0}" \
  --build-arg YARN_VERSION="${YARN_VERSION:-1.22.22}" \
  "${ROOT_DIR}"

echo "==> Base image ready: ${CAGED_BASE_IMAGE}"
