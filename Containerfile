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
# glab/acli CLIs, the shared non-root `agent` user. What remains here is pi-specific and
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

# The complete seed is mounted at /agent-home at runtime. pi uses .pi and
# shared CLI authentication uses the common cli-auth subdirectories.
RUN mkdir -p /agent-home/.pi/agent /agent-home/cli-auth/glab /agent-home/cli-auth/acli \
    && chown -R agent:agent /agent-home

# Install pi (pinned) globally. Open network at build time (npm registry).
# Volatile layer: sits after the cached base layers above so a PI_VERSION
# bump only rebuilds this layer (and the few below it).
ARG PI_VERSION=0.84.4
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
