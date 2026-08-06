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
├── seed/                # pi's home (~/.pi) — LIVE bind-mount source for $HOME
│   └── .pi/agent/       # models.json (providers), settings.json, mcp.json,
│                        # AGENTS.md, skills/, scripts/ (CDP helpers)
├── scripts/
│   └── entrypoint.sh    # seed validation (fail-fast) + tini, runs as USER pi
└── docs/SECURITY.md     # threat model & accepted trade-offs
```

## Quickstart

Requirements: podman >= 4 on macOS (or docker with `userns_mode` support) plus
`podman-compose` (`brew install podman-compose`).

```sh
# 1. build (only needed the first time, or when the Containerfile changes —
#    compose auto-builds when the image is missing; force with
#    `podman compose ... build --no-cache`)
cd caged && podman compose build

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
| `/agent-home/.pi` (`~/.pi`) | `<caged>/seed/.pi` (`$CAGED_PI_HOME`) | rw | **pi's live config home** — maps 1:1 to `seed/.pi`; everything pi configures lands back on the host |
| `/agent-home/.pi/agent` | *(part of the mount above)* — `seed/.pi/agent` | rw | pi's config dir (`models.json`, `settings.json`, `mcp.json`, `AGENTS.md`, `skills/`) |
| `/agent-home/.pi/agent/sessions` | `$CAGED_WORKSPACE/sessions` on the host | rw | **pi session data — per-project, on the host** |

`$HOME` is `/agent-home` and only `~/.pi` (`/agent-home/.pi`) is a live bind mount
of `caged/seed/.pi` — one level of indirection below `$HOME`, so the repo tree
only ever reflects pi's config home, never stray `$HOME` state. Whatever pi
writes under `~/.pi` (settings, models, mcp.json, skills, even `auth.json`)
lands directly in the repo tree. There is **no baked-in config inside the
image** and no fresh-volume seeding step — the seed *is* the live config.
Iterate on seed files and they take effect on the *next* container start —
no image rebuild required.

The rest of `$HOME` stays read-only (rootfs): home-derived caches are pointed
at the `/tmp` tmpfs (`npm_config_cache`, `XDG_CACHE_HOME`), keeping the
container stateful-free apart from the two mounts and scratch.

The entrypoint validates the mount **before** launching pi: if the seed is
missing or incomplete, `mcp.json` references a missing executable, or the
seed is read-only, it exits non-zero with a diagnostic instead of letting pi
run half-configured. This also catches a wrong `$CAGED_PI_HOME` — e.g. an
old value that pointed at a higher-level dir (a dangling `~/.pi/agent` fails
the required-files check immediately).

Keep runtime state out of git: `seed/.pi/agent/auth.json` and
`seed/.pi/agent/sessions/` are ignored (see `.gitignore`). `auth.json` is
written the first time you authenticate, so don't worry if it doesn't exist
yet.

**Session data lives per-project on the host** as a nested mount
(`/agent-home/.pi/agent/sessions` is masked by it): when you run `caged compose
… up` from `~/folder`, pi's sessions are written to `~/folder/sessions/`
(podman-compose creates the directory if missing). Deleting `seed/.pi/agent`
or `auth.json` does **not** touch your sessions or your API keys' cached
auth.

## Seed config (`seed/`)

`seed/.pi/` mirrors pi's config home `~/.pi` on the host and is mounted live
(not baked into the image):

* `.pi/agent/models.json` — providers: **DeepSeek**, **Volcengine Ark Coding**
  (minimax-m3 / doubao-seed / glm-5.2), **OpenRouter**, **Local** (private,
  env-configured base URL + key)
* `.pi/agent/settings.json` — trust + `pi-mcp-adapter` extension
* `.pi/agent/mcp.json` — chrome-devtools MCP (needs host Chrome on `:9222`, optional)
* `.pi/agent/skills/` — caged-persistence, create-post, bgm-metadata, markdown-link, mdx-notes
* `.pi/agent/AGENTS.md` — environment primer pi loads for the container
* `.pi/agent/scripts/` — `start-chrome-devtools-mcp.sh`, `devtools-forward.js` (CDP helpers, referenced by `mcp.json`)

To change the config, just edit `seed/.pi/agent/` — it is the live config,
mounted into the container (effective on next container start). No rebuild
round-trip.

## Provider keys

`models.json` references keys by env var name (`$MY_DEEPSEEK_API_KEY`,
`$VOLCENGINE_API_KEY`, `$MY_OPENROUTER_API_KEY`, and for the local
provider `$LOCAL_API_KEY` + `$LOCAL_LLM_BASE_URL`); pi expands these from
the container environment at runtime. Pass them when starting:

```sh
MY_DEEPSEEK_API_KEY=sk-... VOLCENGINE_API_KEY=ark-... \
  LOCAL_API_KEY=... LOCAL_LLM_BASE_URL=http://... \
  podman compose -f /path/to/caged/compose.yaml up
```

For interactive TUI auth flows that don't use `models.json`, pi stores
credentials in `auth.json` inside the agent dir:

pi stores credentials in `auth.json` inside the agent dir
(`/agent-home/.pi/agent/auth.json` on the volume). Two options:

```sh
podman compose -f /path/to/caged/compose.yaml run --rm pi pi auth
```

Never put API keys in `/workspace` — anything there is readable by pi.

## chrome-devtools MCP

`seed/.pi/agent/mcp.json` registers a chrome-devtools MCP server. It forwards
the container-local port `19222` to the host's Chrome CDP and requires:

1. Host Chrome running with `--remote-debugging-port=9222`
2. `host.docker.internal` resolvable from the container (podman on macOS
   provides it)

Without host Chrome listening, pi will report the MCP server as unavailable —
that's expected, not a caged bug.

## Environment knobs

`compose.yaml` interpolates these from the calling shell; defaults listed.

| Env var | Default | Meaning |
|---|---|---|
| `CAGED_IMAGE` | `caged:latest` | image tag to run |
| `CAGED_WORKSPACE` | `$PWD` | host dir mounted at `/workspace` |
| `CAGED_PI_HOME` | `./seed/.pi` (relative to the compose file) | host dir bind-mounted at `/agent-home/.pi` (`~/.pi`) — live seed: `seed/.pi` == `~/.pi`, synced both ways |
| `MY_DEEPSEEK_API_KEY` | *(unset)* | DeepSeek provider key (passed into container) |
| `VOLCENGINE_API_KEY` | *(unset)* | Volcengine Ark provider key (passed into container) |
| `MY_OPENROUTER_API_KEY` | *(unset)* | OpenRouter provider key (passed into container) |
| `LOCAL_API_KEY` | *(unset)* | Local LLM provider key (passed into container) |
| `LOCAL_LLM_BASE_URL` | *(unset)* | Local LLM base URL, e.g. `http://llm.local/v1` (passed into container) |

## Runtime hardening (applied by compose.yaml)

* `--read-only` — root filesystem immutable (only `/workspace`, `~/.pi` (`/agent-home/.pi`), and `/tmp` writable)
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
