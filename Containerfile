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
#
# Layer ordering for cache friendliness: the most volatile / frequently
# changing layers (pi install, skills clone, entrypoint) sit at the BOTTOM,
# so the slow, rarely-changing installs (apt, chrome-devtools-mcp, glab,
# acli, user) are cached and reused across rebuilds. PI_VERSION is passed as
# a build-arg from compose (default below) so a version bump is a single-layer
# rebuild, not a Dockerfile edit that invalidates everything after it.

ARG NODE_IMAGE=node:24-slim

FROM ${NODE_IMAGE} AS base

# Minimal runtime essentials:
#   git          - pi's bash tool frequently manages repos / commits on user code
#   ca-certificates - TLS for npm/model provider calls
#   curl         - net debugging / provider curl use
#   tini         - proper PID 1 for Node (zombie reaping of bash subprocesses)
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        git ca-certificates curl tini \
    && rm -rf /var/lib/apt/lists/*

# chrome-devtools-mcp, pinned, installed INTO the image (not via npx): the
# runtime /tmp is a noexec tmpfs, so npx'ing from $npm_config_cache=/tmp/.npm
# fails with "Permission denied".
RUN npm install -g chrome-devtools-mcp@1.6.0

# glab — official GitLab CLI (https://gitlab.com/gitlab-org/cli).
# Single static Go binary: pinned version + sha256 verified against the
# official per-release checksums.txt. TARGETARCH comes from BuildKit and both
# amd64/arm64 linux assets exist, so the same Dockerfile builds for either.
ARG GLAB_VERSION=1.112.0
ARG TARGETARCH
RUN set -eux; \
    case "${TARGETARCH}" in \
      amd64) sha=f1c52907558b665f2032b615787d353cd06e54240b501a81f9489bfc8f6a8ebf;; \
      arm64) sha=54a5fe7de0db23e34151c55e561c28e59e6ef6a7731f7d0ce8a00fa58cd8d8f8;; \
      *) echo "unsupported arch: ${TARGETARCH}" >&2; exit 1;; \
    esac; \
    curl -fsSL -o /tmp/glab.tar.gz \
      "https://gitlab.com/api/v4/projects/gitlab-org%2Fcli/packages/generic/glab/${GLAB_VERSION}/glab_${GLAB_VERSION}_linux_${TARGETARCH}.tar.gz"; \
    echo "${sha}  /tmp/glab.tar.gz" | sha256sum -c -; \
    mkdir -p /tmp/glab \
    && tar -xzf /tmp/glab.tar.gz -C /tmp/glab \
    && install -m 0755 /tmp/glab/bin/glab /usr/local/bin/glab \
    && rm -rf /tmp/glab /tmp/glab.tar.gz \
    && glab version

# acli — official Atlassian Command Line Interface (Jira Cloud, Confluence,
# Bitbucket, admin APIs; https://developer.atlassian.com/cloud/acli/).
# Single static Go binary packaged as a .deb. Atlassian only publishes
# `latest`-style URLs, so the pin comes from the versioned pool/... filename
# + sha256 taken from Atlassian's own apt repo Packages index
# (acli.atlassian.com/linux/deb) — if that exact version disappears from the
# repo, the build fails loudly instead of silently installing newer code.
ARG ACLI_VERSION=1.3.22
ARG TARGETARCH
RUN set -eux; \
    case "${TARGETARCH}" in \
      amd64) sha=a19714a3ba5df60334b9d28d2664ce29619a2896a447f68aa6fded66d7b67abd;; \
      arm64) sha=5ebed8959c041fa2d2a6db600b73377648979bce8972a0e9d6c0fdaade6fecb7;; \
      *) echo "unsupported arch: ${TARGETARCH}" >&2; exit 1;; \
    esac; \
    curl -fsSL -o /tmp/acli.deb \
      "https://acli.atlassian.com/linux/deb/pool/stable/a/ac/acli_${ACLI_VERSION}-stable_linux_${TARGETARCH}.deb"; \
    echo "${sha}  /tmp/acli.deb" | sha256sum -c -; \
    dpkg-deb -x /tmp/acli.deb /tmp/acli \
    && install -m 0755 /tmp/acli/usr/bin/acli /usr/local/bin/acli \
    && rm -rf /tmp/acli /tmp/acli.deb \
    && acli --version

# Non-root runtime user + persistent dirs.
# The node base image ships a `node` user at UID 1000; we free that UID up
# for our own `pi` user so "uid 1000" stays stable across base image updates.
# The user's home is /agent-home — named generically (not "pi-agent") so the
# image stays reusable for other agents/tools that hang state off $HOME.
RUN userdel -r node 2>/dev/null || true \
    && useradd --create-home --home-dir /agent-home --uid 1000 --shell /bin/bash pi \
    && mkdir -p /workspace /agent-home/.pi/agent \
    && chown -R pi:pi /workspace /agent-home

# Install pi (pinned) globally. Open network at build time (npm registry).
# Volatile layer: sits after all the slow, rarely-changing installs above so
# a PI_VERSION bump only rebuilds this layer (and the few below it), keeping
# apt/chrome/glab/acli/user cached.
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
