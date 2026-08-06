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
#     at runtime via compose.yaml, not baked into the image

ARG NODE_IMAGE=node:24-slim

FROM ${NODE_IMAGE} AS base

ARG PI_VERSION=0.83.0

# Minimal runtime essentials:
#   git          - pi's bash tool frequently manages repos / commits on user code
#   ca-certificates - TLS for npm/model provider calls
#   curl         - net debugging / provider curl use
#   tini         - proper PID 1 for Node (zombie reaping of bash subprocesses)
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        git ca-certificates curl tini \
    && rm -rf /var/lib/apt/lists/*

# Install pi (pinned) globally. Open network at build time (npm registry).
RUN npm install -g @earendil-works/pi-coding-agent@${PI_VERSION}

# Non-root runtime user + persistent dirs.
# The node base image ships a `node` user at UID 1000; we free that UID up
# for our own `pi` user so "uid 1000" stays stable across base image updates.
# The user's home is /agent-home — named generically (not "pi-agent") so the
# image stays reusable for other agents/tools that hang state off $HOME.
RUN userdel -r node 2>/dev/null || true \
    && useradd --create-home --home-dir /agent-home --uid 1000 --shell /bin/bash pi \
    && mkdir -p /workspace /agent-home/.pi/agent \
    && chown -R pi:pi /workspace /agent-home

# pi's config (~/.pi) is intentionally NOT copied into the image: at runtime
# compose.yaml bind-mounts <caged>/seed/.pi over /agent-home/.pi (rw), so
# ~/.pi is exactly the host's seed/.pi directory — a single source of truth
# with no image copy to drift or go stale. Only ~/.pi is a writable host
# mount; the rest of $HOME stays read-only (rootfs) with caches redirected
# to /tmp. The entrypoint validates that the bind is in place and fails fast
# otherwise. Keys stay out of seed/: models.json references $ENV names only.

# HOME=/agent-home so $HOME/.pi (pi's default config location) lands on the
# persistent volume.
ENV HOME=/agent-home \
    WORKSPACE=/workspace

COPY scripts/entrypoint.sh /usr/local/bin/caged-entrypoint
RUN chmod +x /usr/local/bin/caged-entrypoint

USER pi
WORKDIR /workspace

# `pi` requires a prompt; pass one or use -it to get the interactive TUI.
ENTRYPOINT ["/usr/local/bin/caged-entrypoint"]
CMD ["pi"]
