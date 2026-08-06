# caged

Hardened podman/docker container to run
[`@earendil-works/pi-coding-agent`](https://www.npmjs.com/package/@earendil-works/pi-coding-agent)
(`pi`) safely against your code.

> **What caged is**: a minimal, locked-down runtime for an AI coding agent that
> can execute arbitrary bash commands. Non-root user, read-only rootfs,
> no capabilities, no extra privileges, one disposable volume for all state.
>
> **What caged explicitly is NOT**: a network sandbox. pi needs open networking
> to reach model providers — that part is on purpose. See
> [SECURITY.md](docs/SECURITY.md) for the full threat model.

## Layout

```
caged/
├── Containerfile        # image definition (non-root, pinned pi version)
├── compose.yaml         # the single runtime entry (podman compose / podman-compose)
├── scripts/
│   ├── build.sh         # podman build -t caged:latest
│   └── entrypoint.sh    # volume bootstrap + tini, runs as USER pi
└── docs/SECURITY.md     # threat model & accepted trade-offs
```

## Quickstart

Requirements: podman >= 4 on macOS (or docker with `userns_mode` support) plus
`podman-compose` (`brew install podman-compose`).

```sh
# 1. build
cd caged && ./scripts/build.sh

# 2. interactive TUI — run from the repo you want as the workspace:
cd /path/to/your/repo
podman compose -f /path/to/caged/compose.yaml up

# 3. one-shot (non-interactive) run:
podman compose -f /path/to/caged/compose.yaml run --rm pi pi --print "refactor this module"
```

Both commands mount the **directory you run them from** as `/workspace`.

## What gets mounted

| Path in container | Backing | Read/write | Purpose |
|---|---|---|---|
| `/workspace`   | dir you ran `compose` from, or `$CAGED_WORKSPACE` | rw | **the code pi works on** |
| `/pi-agent`    | named volume `$CAGED_VOLUME` (default `caged-pi-agent`) | rw | pi config, sessions, auth, downloaded tooling (rg/fd) |

Named volume `caged-pi-agent` persists between runs. `podman volume rm caged-pi-agent`
gives you a completely clean slate.

## Authentication

pi stores credentials in `auth.json` inside the agent dir
(`/pi-agent/agent/auth.json` on the volume). Two options:

```sh
# a) interactive auth inside the container
podman compose -f /path/to/caged/compose.yaml run --rm pi pi auth

# b) pre-provision the volume from the host
podman run --rm -v caged-pi-agent:/pi-agent caged:latest pi auth
```

Never put API keys in `/workspace` — anything there is readable by pi.

## Environment knobs

`compose.yaml` interpolates these from the calling shell; defaults listed.

| Env var | Default | Meaning |
|---|---|---|
| `CAGED_IMAGE` | `caged:latest` | image tag to run |
| `CAGED_WORKSPACE` | `$PWD` | host dir mounted at `/workspace` |
| `CAGED_VOLUME` | `caged-pi-agent` | named volume mounted at `/pi-agent` |

## Runtime hardening (applied by compose.yaml)

* `--read-only` — root filesystem immutable (only `/workspace`, `/pi-agent`, `/tmp` writable)
* `--tmpfs /tmp` — scratch, `noexec,nosuid`
* `--cap-drop ALL` — container process gets zero kernel capabilities
* `--security-opt no-new-privileges` — no setuid-style privilege escalation
* `--userns=keep-id` — stays UID 1000, maps cleanly to your host user

See [docs/SECURITY.md](docs/SECURITY.md) for the detailed threat model and the
explicitly accepted risks (open network, rw workspace).

## Known limitations

* Running on macOS: podman runs inside a Linux VM, so `/workspace` bind-mount
  performance matters for large repos — see the earlier discussion about
  small-file I/O. `npm install` in the workspace will be slower than native.
* The image is pinned to `@earendil-works/pi-coding-agent@0.83.0`; bump
  `ARG PI_VERSION` in the `Containerfile` and rebuild to upgrade.

## License / notes

Internal project. Built for podman 6.x on macOS; should work on any podman >= 4
or docker with `userns_mode` support.
