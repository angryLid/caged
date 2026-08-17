# syntax=docker/dockerfile:1

# caged — hardened container for running @earendil-works/pi-coding-agent
#
# Design goals:
#   * run pi as a non-root, low-privilege user
#   * network is intentionally OPEN (pi needs to reach model providers)
#   * all state (config, sessions, downloaded helper tools) lives on a
#     single volume: /agent-home
#   * user code lives on a separate volume: /workspace
#   * hardening (read-only rootfs, NO_NEW_PRIVILEGES, cap-drop) is applied
#     at runtime via scripts/start-container.sh, not baked into the image
#
# This file builds FROM the shared base image ./Containerfile.base (built
# first by `scripts/build-container.sh pi` via scripts/build-caged-base.sh): the
# base carries the slow, rarely-changing layers — apt essentials, the pinned
# glab/acli CLIs, the non-root user. What remains here is pi-specific and
# volatile — chrome-devtools-mcp, the pi npm install, the build-time skill
# clone, the entrypoint — so a PI_VERSION bump only rebuilds these bottom
# layers, and a CLI/base-image update is a single-file change in
# Containerfile.base.

ARG CAGED_BASE_IMAGE=caged-base:latest

FROM ${CAGED_BASE_IMAGE}

# chrome-devtools-mcp, pinned, installed INTO the image (not via npx): the
# runtime /tmp is a noexec tmpfs, so npx'ing from $npm_config_cache=/tmp/.npm
# fails with "Permission denied".
RUN npm install -g chrome-devtools-mcp@1.6.0

# pi's `~/.pi` home dir on the persistent volume (the base only creates
# /agent-home; the .pi subdir is pi-specific).
RUN mkdir -p /agent-home/.pi/agent \
    && chown -R pi:pi /agent-home/.pi

# Install pi (pinned) globally. Open network at build time (npm registry).
# Volatile layer: sits after the cached base layers above so a PI_VERSION
# bump only rebuilds this layer (and the few below it).
ARG PI_VERSION=0.84.2
RUN npm install -g @earendil-works/pi-coding-agent@${PI_VERSION}

# Declarative skills — clone the configured skill repos into the image at
# BUILD time (network), so a container start only copies the enabled skills
# into the seed — no network / git at start. skills.json lives in the seed
# (seed/.pi/agent/skills.json) and is copied here to drive the build-time
# clone; the resulting repos are baked under /opt/caged/skills/vendor.
# Volatile layer: skills.json churns on seed edits, so it stays near the
# bottom.
COPY seed/.pi/agent/skills.json scripts/skills-sync.mjs  /opt/caged/

RUN node /opt/caged/skills-sync.mjs \
        --config /opt/caged/skills.json \
        --vendor /opt/caged/skills/vendor \
        --clone-only \
    && rm -f /opt/caged/skills.json

# pi's config (~/.pi) is intentionally NOT copied into the image: at runtime
# scripts/start-container.sh bind-mounts <caged>/seed/.pi over /agent-home/.pi (rw), so
# ~/.pi is exactly the host's seed/.pi directory — a single source of truth
# with no image copy to drift or go stale. Only ~/.pi is a writable host
# mount; the rest of $HOME stays read-only (rootfs) with caches redirected
# to /tmp. The entrypoint validates that the bind is in place and fails fast
# otherwise. Keys stay out of seed/: models.json references $ENV names only.

COPY scripts/entrypoint.sh /usr/local/bin/caged-entrypoint
RUN chmod +x /usr/local/bin/caged-entrypoint

USER pi
WORKDIR /workspace

# `pi` requires a prompt; pass one or use -it to get the interactive TUI.
ENTRYPOINT ["/usr/local/bin/caged-entrypoint"]
CMD ["pi"]
