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
# glab/gh/jira CLIs, the shared non-root `agent` user. What remains here is pi-specific and
# volatile — the pi npm install, the build-time skill clone, the entrypoint — so a
# PI_VERSION bump only rebuilds these bottom layers, and a CLI/base-image update is a
# single-file change in Containerfile.base.
#
# Note: this image is an intermediate stage, not what pi runs on. The browser
# layer (./Containerfile.browser, Playwright + Chromium) builds on top of it,
# and pi (TUI) and pi-web-ui both run on that layer — see docs/BROWSER.md.

ARG CAGED_BASE_IMAGE=caged-base:latest

FROM ${CAGED_BASE_IMAGE}

# The complete seed is mounted at /agent-home at runtime. pi uses .pi and
# CLI configs follow their own defaults under $XDG_CONFIG_HOME (= .config).
RUN mkdir -p /agent-home/.pi/agent /agent-home/.config \
    && chown -R agent:agent /agent-home

# Install pi globally, defaulting to latest so rapid upstream iterations are
# picked up on every rebuild; pin a specific version via PI_VERSION=x.y.z.
# Volatile layer: sits after the cached base layers above so a PI_VERSION
# change only rebuilds this layer (and the few below it).
ARG PI_VERSION=latest
RUN npm install -g @earendil-works/pi-coding-agent@${PI_VERSION}

# The agent home is intentionally NOT copied into the image: at runtime
# scripts/start-container.sh bind-mounts <caged>/seed over /agent-home (rw),
# so .pi, .dsh, and shared CLI authentication are all live host state. The
# entrypoint validates the expected pi config below /agent-home and fails fast
# otherwise. Keys stay out of seed/: models.json references $ENV names only.

COPY scripts/entrypoint.sh /usr/local/bin/caged-entrypoint
RUN chmod +x /usr/local/bin/caged-entrypoint

USER agent
WORKDIR /workspace

# `pi` requires a prompt; pass one or use -it to get the interactive TUI.
ENTRYPOINT ["/usr/local/bin/caged-entrypoint"]
CMD ["pi"]
